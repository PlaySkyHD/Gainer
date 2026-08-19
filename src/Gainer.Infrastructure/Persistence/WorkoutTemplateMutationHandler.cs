using Gainer.Core.Mutations;
using Gainer.Core.Security;
using Gainer.Core.Training;
using Gainer.Core.Values;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;

namespace Gainer.Infrastructure.Persistence;

public sealed class WorkoutTemplateMutationHandler(
    AppDbContext context,
    IUserContext userContext,
    TimeProvider timeProvider,
    IChangeCollector? changeCollector = null) : IWorkoutTemplateMutationHandler
{
    public async Task<WorkoutTemplateSnapshot> SaveAsync(
        SaveWorkoutTemplateMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        Guid userId = CurrentUserId();
        (string name, IReadOnlyList<WorkoutTemplateItemValues> values) = ValidateAndNormalize(mutation);
        DateTime now = timeProvider.GetUtcNow().UtcDateTime;

        await using IDbContextTransaction? transaction = context.Database.CurrentTransaction is null
            ? await context.Database.BeginTransactionAsync(cancellationToken)
            : null;
        WorkoutTemplate template;
        HashSet<Guid> previouslyReferencedExerciseIds = [];
        if (mutation.BaseVersion == 0)
        {
            template = new WorkoutTemplate
            {
                Id = mutation.TemplateId,
                Name = name,
                CreatedAtUtc = now,
                UpdatedAtUtc = now,
                Version = 1,
            };
            context.WorkoutTemplates.Add(template);
        }
        else
        {
            template = await context.WorkoutTemplates.SingleOrDefaultAsync(
                item => item.Id == mutation.TemplateId,
                cancellationToken) ?? throw new WorkoutTemplateNotFoundException();
            if (template.Version != mutation.BaseVersion || template.IsArchived)
            {
                throw new WorkoutTemplateConflictException("The template cannot be updated from this version.");
            }
            List<WorkoutTemplateItem> existingItems = await context.WorkoutTemplateItems
                .Where(item => item.TemplateId == template.Id)
                .ToListAsync(cancellationToken);
            previouslyReferencedExerciseIds.UnionWith(existingItems.Select(item => item.ExerciseId));
            context.WorkoutTemplateItems.RemoveRange(existingItems);
            template.Name = name;
            template.UpdatedAtUtc = now;
            template.Version++;
        }

        await EnsureExercisesAreSelectableAsync(
            userId,
            values.Select(item => item.ExerciseId).Distinct().ToArray(),
            previouslyReferencedExerciseIds,
            cancellationToken);
        if (mutation.BaseVersion > 0)
        {
            try
            {
                // Flush removals before reusing stable item IDs; the surrounding transaction keeps replacement atomic.
                await context.SaveChangesAsync(cancellationToken);
            }
            catch (DbUpdateConcurrencyException)
            {
                throw new WorkoutTemplateConflictException("The template changed concurrently.");
            }
        }
        for (int position = 0; position < values.Count; position++)
        {
            WorkoutTemplateItemValues value = values[position];
            context.WorkoutTemplateItems.Add(new WorkoutTemplateItem
            {
                Id = value.ItemId,
                TemplateId = template.Id,
                ExerciseId = value.ExerciseId,
                Position = position,
                PlannedSets = value.PlannedSets,
                MinimumRepetitions = value.MinimumRepetitions,
                MaximumRepetitions = value.MaximumRepetitions,
                TargetRir = value.TargetRir,
                RestSeconds = value.RestSeconds,
                Notes = value.Notes,
            });
        }

        try
        {
            await context.SaveChangesAsync(cancellationToken);
            if (transaction is not null) await transaction.CommitAsync(cancellationToken);
        }
        catch (DbUpdateConcurrencyException)
        {
            throw new WorkoutTemplateConflictException("The template changed concurrently.");
        }
        catch (DbUpdateException)
        {
            throw new WorkoutTemplateConflictException("The template conflicts with stored data.");
        }

        WorkoutTemplateSnapshot snapshot = Snapshot(template, values);
        changeCollector?.CaptureUpsert(snapshot);
        return snapshot;
    }

    public async Task<WorkoutTemplateSnapshot> ArchiveAsync(
        ArchiveWorkoutTemplateMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        _ = CurrentUserId();
        WorkoutTemplate template = await context.WorkoutTemplates.SingleOrDefaultAsync(
            item => item.Id == mutation.TemplateId,
            cancellationToken) ?? throw new WorkoutTemplateNotFoundException();
        if (template.Version != mutation.BaseVersion || template.IsArchived)
        {
            throw new WorkoutTemplateConflictException("The template cannot be archived from this version.");
        }
        List<WorkoutTemplateItemValues> items = await LoadItemValuesAsync(template.Id, cancellationToken);
        template.IsArchived = true;
        template.UpdatedAtUtc = timeProvider.GetUtcNow().UtcDateTime;
        template.Version++;
        try
        {
            await context.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateConcurrencyException)
        {
            throw new WorkoutTemplateConflictException("The template changed concurrently.");
        }
        WorkoutTemplateSnapshot snapshot = Snapshot(template, items);
        changeCollector?.CaptureUpsert(snapshot);
        return snapshot;
    }

    private async Task EnsureExercisesAreSelectableAsync(
        Guid userId,
        IReadOnlyCollection<Guid> exerciseIds,
        IReadOnlySet<Guid> previouslyReferencedExerciseIds,
        CancellationToken cancellationToken)
    {
        List<Exercise> exercises = await context.Exercises
            .AsNoTracking()
            .Where(item => exerciseIds.Contains(item.Id))
            .Where(item => item.OwnerUserId == null || item.OwnerUserId == userId)
            .ToListAsync(cancellationToken);
        bool allSelectable = exercises.Count == exerciseIds.Count && exercises.All(item =>
            !item.IsArchived || previouslyReferencedExerciseIds.Contains(item.Id));
        if (!allSelectable)
        {
            throw new WorkoutTemplateValidationException(new Dictionary<string, string>
            {
                ["Items.ExerciseId"] = "Every exercise must be available to the current user and selectable.",
            });
        }
    }

    private async Task<List<WorkoutTemplateItemValues>> LoadItemValuesAsync(
        Guid templateId,
        CancellationToken cancellationToken) =>
        await context.WorkoutTemplateItems
            .AsNoTracking()
            .Where(item => item.TemplateId == templateId)
            .OrderBy(item => item.Position)
            .Select(item => new WorkoutTemplateItemValues(
                item.Id,
                item.ExerciseId,
                item.PlannedSets,
                item.MinimumRepetitions,
                item.MaximumRepetitions,
                item.TargetRir,
                item.RestSeconds,
                item.Notes))
            .ToListAsync(cancellationToken);

    private Guid CurrentUserId() => userContext.UserId
        ?? throw new UnauthorizedAccessException("An authenticated user is required.");

    private static (string Name, IReadOnlyList<WorkoutTemplateItemValues> Items) ValidateAndNormalize(
        SaveWorkoutTemplateMutation mutation)
    {
        var errors = new Dictionary<string, string>(StringComparer.Ordinal);
        string name = mutation.Name.Trim();
        if (name.Length is < 1 or > 160)
        {
            errors[nameof(mutation.Name)] = "Name must contain between 1 and 160 characters.";
        }
        if (mutation.Items.Count is < 1 or > 100)
        {
            errors[nameof(mutation.Items)] = "A template must contain between 1 and 100 exercises.";
        }
        if (mutation.Items.Any(item => item.ItemId == Guid.Empty) ||
            mutation.Items.Select(item => item.ItemId).Distinct().Count() != mutation.Items.Count)
        {
            errors["Items.ItemId"] = "Template item identifiers must be non-empty and unique.";
        }

        var normalized = new List<WorkoutTemplateItemValues>(mutation.Items.Count);
        for (int index = 0; index < mutation.Items.Count; index++)
        {
            WorkoutTemplateItemValues item = mutation.Items[index];
            string prefix = $"Items[{index}]";
            if (item.ExerciseId == Guid.Empty)
            {
                errors[$"{prefix}.ExerciseId"] = "Exercise identifier cannot be empty.";
            }
            if (item.PlannedSets is < 1 or > 100)
            {
                errors[$"{prefix}.PlannedSets"] = "Planned sets must be between 1 and 100.";
            }
            if (item.MinimumRepetitions is < 1 or > 1_000 ||
                item.MaximumRepetitions < item.MinimumRepetitions || item.MaximumRepetitions > 1_000)
            {
                errors[$"{prefix}.Repetitions"] = "Repetitions must be positive and maximum must not be below minimum.";
            }
            if (item.TargetRir is { } rir && !RepetitionsInReserve.TryCreate(rir, out _))
            {
                errors[$"{prefix}.TargetRir"] = "RIR must be between 0 and 10.";
            }
            if (item.RestSeconds is < 0 or > 86_400)
            {
                errors[$"{prefix}.RestSeconds"] = "Rest must be between 0 and 86400 seconds.";
            }
            if (item.Notes?.Trim().Length > 2_000)
            {
                errors[$"{prefix}.Notes"] = "Notes cannot exceed 2000 characters.";
            }
            normalized.Add(item with
            {
                Notes = string.IsNullOrWhiteSpace(item.Notes) ? null : item.Notes.Trim(),
            });
        }
        if (errors.Count > 0)
        {
            throw new WorkoutTemplateValidationException(errors);
        }
        return (name, normalized);
    }

    private static WorkoutTemplateSnapshot Snapshot(
        WorkoutTemplate template,
        IReadOnlyList<WorkoutTemplateItemValues> items) => new(
        template.Id,
        template.Name,
        template.IsArchived,
        items,
        template.CreatedAtUtc,
        template.UpdatedAtUtc,
        template.Version);
}
