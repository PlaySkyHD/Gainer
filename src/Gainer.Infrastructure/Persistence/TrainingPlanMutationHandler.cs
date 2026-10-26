using Gainer.Core.Mutations;
using Gainer.Core.Security;
using Gainer.Core.Training;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;

namespace Gainer.Infrastructure.Persistence;

public sealed class TrainingPlanMutationHandler(
    AppDbContext context,
    IUserContext userContext,
    TimeProvider timeProvider,
    IChangeCollector? changeCollector = null) : ITrainingPlanMutationHandler
{
    private const string UnavailableExerciseMessage = "Every exercise must be available to the current user and selectable.";

    public async Task<TrainingPlanSnapshot> CreateAsync(
        CreateTrainingPlanMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        Guid userId = CurrentUserId();
        TrainingPlanValues values = TrainingPlanValidation.Normalize(mutation.Plan);
        await EnsureExercisesSelectableAsync(userId, values, [], cancellationToken);
        int sortOrder = await context.TrainingPlans.AsNoTracking()
            .Select(item => (int?)item.SortOrder)
            .MaxAsync(cancellationToken) is { } maximum ? maximum + 1 : 0;

        DateTime now = timeProvider.GetUtcNow().UtcDateTime;
        var plan = new TrainingPlan
        {
            Id = values.PlanId,
            SortOrder = sortOrder,
            CreatedAtUtc = now,
            UpdatedAtUtc = now,
            Version = 1,
        };
        Apply(plan, values);
        context.TrainingPlans.Add(plan);
        AddEntries(plan.Id, values.Entries);
        await SaveOrConflictAsync(cancellationToken);
        return Capture(plan, values.Entries);
    }

    public async Task<TrainingPlanSnapshot> UpdateAsync(
        UpdateTrainingPlanMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        Guid userId = CurrentUserId();
        TrainingPlanValues values = TrainingPlanValidation.Normalize(mutation.Plan);
        TrainingPlan plan = await FindOwnedAsync(values.PlanId, cancellationToken);
        if (plan.Version != mutation.BaseVersion || plan.IsArchived)
        {
            throw new TrainingPlanConflictException("The plan cannot be updated from this version.");
        }
        List<TrainingPlanEntry> existing = await context.TrainingPlanEntries
            .Where(item => item.PlanId == plan.Id).ToListAsync(cancellationToken);
        await EnsureExercisesSelectableAsync(userId, values, existing.Select(item => item.ExerciseId).ToHashSet(), cancellationToken);

        await using IDbContextTransaction? transaction = context.Database.CurrentTransaction is null
            ? await context.Database.BeginTransactionAsync(cancellationToken)
            : null;
        // Removals are flushed before the stable entry IDs are reused by the replacement rows.
        context.TrainingPlanEntries.RemoveRange(existing);
        await SaveOrConflictAsync(cancellationToken);
        Apply(plan, values);
        plan.UpdatedAtUtc = timeProvider.GetUtcNow().UtcDateTime;
        plan.Version++;
        AddEntries(plan.Id, values.Entries);
        await SaveOrConflictAsync(cancellationToken);
        if (transaction is not null) await transaction.CommitAsync(cancellationToken);
        return Capture(plan, values.Entries);
    }

    public async Task<TrainingPlanSnapshot> ArchiveAsync(
        ArchiveTrainingPlanMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        _ = CurrentUserId();
        TrainingPlan plan = await FindOwnedAsync(mutation.PlanId, cancellationToken);
        if (plan.Version != mutation.BaseVersion || plan.IsArchived)
        {
            throw new TrainingPlanConflictException("The plan cannot be archived from this version.");
        }
        plan.IsArchived = true;
        plan.UpdatedAtUtc = timeProvider.GetUtcNow().UtcDateTime;
        plan.Version++;
        await SaveOrConflictAsync(cancellationToken);
        return Capture(plan, await LoadEntriesAsync(plan.Id, cancellationToken));
    }

    public async Task<IReadOnlyList<TrainingPlanSnapshot>> ReorderAsync(
        ReorderTrainingPlansMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        _ = CurrentUserId();
        Guid[] planIds = mutation.Plans.Select(item => item.PlanId).ToArray();
        List<TrainingPlan> plans = await context.TrainingPlans
            .Where(item => planIds.Contains(item.Id)).ToListAsync(cancellationToken);
        if (plans.Count != planIds.Length)
        {
            throw new TrainingPlanNotFoundException();
        }

        DateTime now = timeProvider.GetUtcNow().UtcDateTime;
        var snapshots = new List<TrainingPlanSnapshot>(plans.Count);
        for (int position = 0; position < mutation.Plans.Count; position++)
        {
            TrainingPlanVersion expected = mutation.Plans[position];
            TrainingPlan plan = plans.Single(item => item.Id == expected.PlanId);
            if (plan.Version != expected.BaseVersion || plan.IsArchived)
            {
                throw new TrainingPlanConflictException("A plan cannot be reordered from this version.");
            }
            plan.SortOrder = position;
            plan.UpdatedAtUtc = now;
            plan.Version++;
        }
        await SaveOrConflictAsync(cancellationToken);
        foreach (TrainingPlanVersion expected in mutation.Plans)
        {
            TrainingPlan plan = plans.Single(item => item.Id == expected.PlanId);
            snapshots.Add(Capture(plan, await LoadEntriesAsync(plan.Id, cancellationToken)));
        }
        return snapshots;
    }

    private async Task<TrainingPlan> FindOwnedAsync(Guid planId, CancellationToken cancellationToken) =>
        await context.TrainingPlans.SingleOrDefaultAsync(item => item.Id == planId, cancellationToken)
        ?? throw new TrainingPlanNotFoundException();

    /// <summary>Base and own, non-archived exercises are selectable; archived ones only when the plan already referenced them.</summary>
    private async Task EnsureExercisesSelectableAsync(
        Guid userId,
        TrainingPlanValues values,
        HashSet<Guid> previouslyReferenced,
        CancellationToken cancellationToken)
    {
        Guid[] exerciseIds = values.Entries.Select(item => item.ExerciseId).Distinct().ToArray();
        if (exerciseIds.Length == 0)
        {
            return;
        }
        List<Exercise> exercises = await context.Exercises.AsNoTracking()
            .Where(item => exerciseIds.Contains(item.Id))
            .Where(item => item.OwnerUserId == null || item.OwnerUserId == userId)
            .ToListAsync(cancellationToken);
        bool allSelectable = exercises.Count == exerciseIds.Length && exercises.All(item =>
            !item.IsArchived || previouslyReferenced.Contains(item.Id));
        if (!allSelectable)
        {
            throw new TrainingPlanValidationException(new Dictionary<string, string>(StringComparer.Ordinal)
            {
                ["Entries.ExerciseId"] = UnavailableExerciseMessage,
            });
        }
    }

    private void AddEntries(Guid planId, IReadOnlyList<TrainingPlanEntryValues> entries)
    {
        for (int position = 0; position < entries.Count; position++)
        {
            TrainingPlanEntryValues entry = entries[position];
            context.TrainingPlanEntries.Add(new TrainingPlanEntry
            {
                Id = entry.EntryId,
                PlanId = planId,
                Position = position,
                ExerciseId = entry.ExerciseId,
                WarmupSets = entry.WarmupSets,
                WorkingSets = entry.WorkingSets,
                Notes = entry.Notes,
                SupersetId = entry.SupersetId,
            });
        }
    }

    private async Task<List<TrainingPlanEntryValues>> LoadEntriesAsync(Guid planId, CancellationToken cancellationToken) =>
        await context.TrainingPlanEntries.AsNoTracking()
            .Where(item => item.PlanId == planId)
            .OrderBy(item => item.Position)
            .Select(item => new TrainingPlanEntryValues(
                item.Id, item.ExerciseId, item.WarmupSets, item.WorkingSets, item.Notes, item.SupersetId))
            .ToListAsync(cancellationToken);

    private static void Apply(TrainingPlan plan, TrainingPlanValues values)
    {
        plan.Name = values.Name;
        plan.Notes = values.Notes;
        plan.PreviousValueSource = PreviousValueSources.Parse(values.PreviousValueSource);
    }

    private TrainingPlanSnapshot Capture(TrainingPlan plan, IReadOnlyList<TrainingPlanEntryValues> entries)
    {
        var snapshot = new TrainingPlanSnapshot(
            plan.Id,
            plan.Name,
            plan.Notes,
            PreviousValueSources.ToStorageValue(plan.PreviousValueSource),
            entries,
            plan.SortOrder,
            plan.IsArchived,
            plan.CreatedAtUtc,
            plan.UpdatedAtUtc,
            plan.Version);
        changeCollector?.CaptureUpsert(snapshot);
        return snapshot;
    }

    private async Task SaveOrConflictAsync(CancellationToken cancellationToken)
    {
        try
        {
            await context.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateConcurrencyException)
        {
            throw new TrainingPlanConflictException("The plan changed concurrently.");
        }
        catch (DbUpdateException exception) when (context.IsKeyViolation<TrainingPlan>(exception))
        {
            throw new TrainingPlanConflictException("A plan with this identifier already exists.");
        }
    }

    private Guid CurrentUserId() => userContext.UserId
        ?? throw new UnauthorizedAccessException("An authenticated user is required.");
}
