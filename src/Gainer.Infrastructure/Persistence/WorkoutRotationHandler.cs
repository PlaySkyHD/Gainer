using Gainer.Core.Mutations;
using Gainer.Core.Security;
using Gainer.Core.Training;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;

namespace Gainer.Infrastructure.Persistence;

public sealed class WorkoutRotationHandler(
    AppDbContext context,
    IUserContext userContext,
    TimeProvider timeProvider,
    IChangeCollector? changeCollector = null) : IWorkoutRotationHandler
{
    public async Task<WorkoutRotationSnapshot> SaveAsync(
        SaveWorkoutRotationMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        _ = CurrentUserId();
        Validate(mutation.Entries);
        DateTime now = timeProvider.GetUtcNow().UtcDateTime;
        await using IDbContextTransaction? transaction = context.Database.CurrentTransaction is null
            ? await context.Database.BeginTransactionAsync(cancellationToken)
            : null;

        WorkoutRotation rotation;
        HashSet<Guid> previousTemplateIds = [];
        if (mutation.BaseVersion == 0)
        {
            bool alreadyExists = await context.WorkoutRotations.AnyAsync(cancellationToken);
            if (alreadyExists)
            {
                throw new WorkoutRotationConflictException("The user already has a workout rotation.");
            }
            await EnsureTemplatesAreSelectableAsync(
                mutation.Entries.Select(item => item.TemplateId).ToArray(),
                previousTemplateIds,
                cancellationToken);
            rotation = new WorkoutRotation
            {
                Id = mutation.RotationId,
                CreatedAtUtc = now,
                UpdatedAtUtc = now,
                Version = 1,
            };
            context.WorkoutRotations.Add(rotation);
        }
        else
        {
            rotation = await context.WorkoutRotations.SingleOrDefaultAsync(
                item => item.Id == mutation.RotationId,
                cancellationToken) ?? throw new WorkoutRotationNotFoundException();
            if (rotation.Version != mutation.BaseVersion)
            {
                throw new WorkoutRotationConflictException("The rotation changed since the supplied base version.");
            }
            List<WorkoutRotationItem> existing = await context.WorkoutRotationItems
                .Where(item => item.RotationId == rotation.Id)
                .ToListAsync(cancellationToken);
            previousTemplateIds.UnionWith(existing.Select(item => item.TemplateId));
            await EnsureTemplatesAreSelectableAsync(
                mutation.Entries.Select(item => item.TemplateId).ToArray(),
                previousTemplateIds,
                cancellationToken);
            context.WorkoutRotationItems.RemoveRange(existing);
            if (rotation.LastCompletedTemplateId is { } last &&
                !mutation.Entries.Any(item => item.TemplateId == last))
            {
                rotation.LastCompletedTemplateId = null;
            }
            rotation.UpdatedAtUtc = now;
            rotation.Version++;
        }

        if (mutation.BaseVersion > 0)
        {
            await SaveOrConflictAsync(cancellationToken);
        }
        for (int position = 0; position < mutation.Entries.Count; position++)
        {
            WorkoutRotationEntry entry = mutation.Entries[position];
            context.WorkoutRotationItems.Add(new WorkoutRotationItem
            {
                Id = entry.ItemId,
                RotationId = rotation.Id,
                TemplateId = entry.TemplateId,
                Position = position,
            });
        }
        await SaveOrConflictAsync(cancellationToken);
        if (transaction is not null) await transaction.CommitAsync(cancellationToken);
        WorkoutRotationSnapshot snapshot = await SnapshotAsync(rotation, cancellationToken);
        changeCollector?.CaptureUpsert(snapshot);
        return snapshot;
    }

    public async Task<WorkoutRotationSnapshot> AdvanceAsync(
        AdvanceWorkoutRotationMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        _ = CurrentUserId();
        WorkoutRotation rotation = await context.WorkoutRotations.SingleOrDefaultAsync(
            item => item.Id == mutation.RotationId,
            cancellationToken) ?? throw new WorkoutRotationNotFoundException();
        if (rotation.Version != mutation.BaseVersion)
        {
            throw new WorkoutRotationConflictException("The rotation changed since the supplied base version.");
        }
        bool containsTemplate = await context.WorkoutRotationItems.AnyAsync(
            item => item.RotationId == rotation.Id && item.TemplateId == mutation.CompletedTemplateId,
            cancellationToken);
        if (!containsTemplate)
        {
            throw new WorkoutRotationValidationException(new Dictionary<string, string>
            {
                [nameof(mutation.CompletedTemplateId)] = "The completed template is not part of this rotation.",
            });
        }
        rotation.LastCompletedTemplateId = mutation.CompletedTemplateId;
        rotation.UpdatedAtUtc = timeProvider.GetUtcNow().UtcDateTime;
        rotation.Version++;
        await SaveOrConflictAsync(cancellationToken);
        WorkoutRotationSnapshot snapshot = await SnapshotAsync(rotation, cancellationToken);
        changeCollector?.CaptureUpsert(snapshot);
        return snapshot;
    }

    public async Task<WorkoutRotationSnapshot?> GetAsync(CancellationToken cancellationToken = default)
    {
        _ = CurrentUserId();
        WorkoutRotation? rotation = await context.WorkoutRotations.AsNoTracking().SingleOrDefaultAsync(cancellationToken);
        return rotation is null ? null : await SnapshotAsync(rotation, cancellationToken);
    }

    private async Task<WorkoutRotationSnapshot> SnapshotAsync(
        WorkoutRotation rotation,
        CancellationToken cancellationToken)
    {
        List<RotationRow> rows = await (
            from item in context.WorkoutRotationItems.AsNoTracking()
            join template in context.WorkoutTemplates.AsNoTracking() on item.TemplateId equals template.Id
            where item.RotationId == rotation.Id
            orderby item.Position
            select new RotationRow(item.Id, item.TemplateId, template.IsArchived))
            .ToListAsync(cancellationToken);
        Guid? nextTemplateId = FindNext(rows, rotation.LastCompletedTemplateId);
        return new WorkoutRotationSnapshot(
            rotation.Id,
            rows.Select(item => new WorkoutRotationEntry(item.ItemId, item.TemplateId)).ToList(),
            rotation.LastCompletedTemplateId,
            nextTemplateId,
            rotation.CreatedAtUtc,
            rotation.UpdatedAtUtc,
            rotation.Version);
    }

    private static Guid? FindNext(IReadOnlyList<RotationRow> rows, Guid? lastCompletedTemplateId)
    {
        if (!rows.Any(item => !item.IsArchived))
        {
            return null;
        }
        int lastIndex = lastCompletedTemplateId is null
            ? -1
            : rows.ToList().FindIndex(item => item.TemplateId == lastCompletedTemplateId);
        for (int offset = 1; offset <= rows.Count; offset++)
        {
            RotationRow candidate = rows[(lastIndex + offset + rows.Count) % rows.Count];
            if (!candidate.IsArchived)
            {
                return candidate.TemplateId;
            }
        }
        return null;
    }

    private async Task EnsureTemplatesAreSelectableAsync(
        IReadOnlyCollection<Guid> templateIds,
        IReadOnlySet<Guid> previouslyPresent,
        CancellationToken cancellationToken)
    {
        List<WorkoutTemplate> templates = await context.WorkoutTemplates
            .AsNoTracking()
            .Where(item => templateIds.Contains(item.Id))
            .ToListAsync(cancellationToken);
        if (templates.Count != templateIds.Count ||
            templates.Any(item => item.IsArchived && !previouslyPresent.Contains(item.Id)))
        {
            throw new WorkoutRotationValidationException(new Dictionary<string, string>
            {
                ["Entries.TemplateId"] = "Every template must belong to the user and be selectable.",
            });
        }
    }

    private static void Validate(IReadOnlyList<WorkoutRotationEntry> entries)
    {
        var errors = new Dictionary<string, string>(StringComparer.Ordinal);
        if (entries.Count > 100)
        {
            errors[nameof(entries)] = "A rotation cannot contain more than 100 templates.";
        }
        if (entries.Any(item => item.ItemId == Guid.Empty || item.TemplateId == Guid.Empty) ||
            entries.Select(item => item.ItemId).Distinct().Count() != entries.Count ||
            entries.Select(item => item.TemplateId).Distinct().Count() != entries.Count)
        {
            errors[nameof(entries)] = "Rotation item and template identifiers must be non-empty and unique.";
        }
        if (errors.Count > 0)
        {
            throw new WorkoutRotationValidationException(errors);
        }
    }

    private async Task SaveOrConflictAsync(CancellationToken cancellationToken)
    {
        try
        {
            await context.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateConcurrencyException)
        {
            throw new WorkoutRotationConflictException("The rotation changed concurrently.");
        }
        catch (DbUpdateException)
        {
            throw new WorkoutRotationConflictException("The rotation conflicts with stored data.");
        }
    }

    private Guid CurrentUserId() => userContext.UserId
        ?? throw new UnauthorizedAccessException("An authenticated user is required.");

    private sealed record RotationRow(Guid ItemId, Guid TemplateId, bool IsArchived);
}
