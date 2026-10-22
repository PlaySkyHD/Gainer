using Gainer.Core.Mutations;
using Gainer.Core.Nutrition;
using Gainer.Core.Security;
using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace Gainer.Infrastructure.Persistence;

/// <summary>
/// Saves a day template as a complete state; entries are replaced on every save. Deleting removes the row,
/// like a nutrition day; days the template was applied to hold copies and stay unchanged.
/// </summary>
public sealed class NutritionDayTemplateMutationHandler(
    AppDbContext context,
    IUserContext userContext,
    TimeProvider timeProvider,
    IChangeCollector? changeCollector = null) : INutritionDayTemplateMutationHandler
{
    public async Task<NutritionDayTemplateSnapshot> SaveAsync(
        SaveNutritionDayTemplateMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        _ = CurrentUserId();
        NutritionDayTemplate? template = await context.NutritionDayTemplates
            .Include(item => item.Entries)
            .SingleOrDefaultAsync(item => item.Id == mutation.TemplateId, cancellationToken);
        DateTime utcNow = timeProvider.GetUtcNow().UtcDateTime;
        if (template is null)
        {
            if (mutation.BaseVersion != 0) throw new NutritionDayTemplateNotFoundException();
            if (await context.NutritionDayTemplates.CountAsync(cancellationToken) >= NutritionLimits.MaxDayTemplates)
            {
                throw new NutritionValidationException(new Dictionary<string, string>
                {
                    ["Templates"] = $"A user can have at most {NutritionLimits.MaxDayTemplates} day templates.",
                });
            }
            template = new NutritionDayTemplate
            {
                Id = mutation.TemplateId,
                CreatedAtUtc = utcNow,
                UpdatedAtUtc = utcNow,
                Version = 1,
            };
            context.NutritionDayTemplates.Add(template);
        }
        else
        {
            if (template.Version != mutation.BaseVersion)
                throw new NutritionDayTemplateConflictException("The day template changed since the supplied base version.");
            context.NutritionDayTemplateEntries.RemoveRange(template.Entries.ToArray());
            await SaveOrConflictAsync(cancellationToken);
            template.UpdatedAtUtc = utcNow;
            template.Version++;
        }
        template.Name = mutation.Name;
        template.DayKind = mutation.DayKind;

        NutritionDayTemplateEntry[] entries = mutation.Entries
            .Select(input => ToTemplateEntry(template.Id, NutritionDayMutationHandler.CreateEntry(Guid.Empty, input)))
            .ToArray();
        context.NutritionDayTemplateEntries.AddRange(entries);
        await SaveOrConflictAsync(cancellationToken);

        NutritionDayTemplateSnapshot snapshot = Snapshot(template, entries);
        changeCollector?.CaptureUpsert(snapshot);
        return snapshot;
    }

    public async Task<long> DeleteAsync(
        DeleteNutritionDayTemplateMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        _ = CurrentUserId();
        NutritionDayTemplate template = await context.NutritionDayTemplates
            .SingleOrDefaultAsync(item => item.Id == mutation.TemplateId, cancellationToken)
            ?? throw new NutritionDayTemplateNotFoundException();
        if (template.Version != mutation.BaseVersion)
            throw new NutritionDayTemplateConflictException("The day template changed since the supplied base version.");

        long deletedVersion = template.Version + 1;
        context.NutritionDayTemplates.Remove(template);
        await SaveOrConflictAsync(cancellationToken);
        changeCollector?.CaptureDeletion(ResourceKey.Create(ResourceKind.NutritionDayTemplate, template.Id), deletedVersion);
        return deletedVersion;
    }

    internal static NutritionDayTemplateSnapshot Snapshot(
        NutritionDayTemplate template,
        IEnumerable<NutritionDayTemplateEntry>? entrySource = null)
    {
        NutritionEntrySnapshot[] entries = (entrySource ?? template.Entries)
            .OrderBy(item => item.Meal)
            .ThenBy(item => item.Position)
            .ThenBy(item => item.Id)
            .Select(NutritionSnapshots.Entry)
            .ToArray();
        return new NutritionDayTemplateSnapshot(
            template.Id,
            template.Name,
            template.DayKind,
            entries,
            NutritionCalculator.Sum(entries.Select(item => item.Totals)),
            template.CreatedAtUtc,
            template.UpdatedAtUtc,
            template.Version);
    }

    private async Task SaveOrConflictAsync(CancellationToken cancellationToken)
    {
        try { await context.SaveChangesAsync(cancellationToken); }
        catch (DbUpdateConcurrencyException)
        {
            throw new NutritionDayTemplateConflictException("The day template changed concurrently.");
        }
        catch (DbUpdateException exception) when (exception.InnerException is PostgresException { SqlState: PostgresErrorCodes.UniqueViolation })
        {
            throw new NutritionDayTemplateConflictException("A day template or entry already exists for this identifier or position.");
        }
    }

    private Guid CurrentUserId() =>
        userContext.UserId ?? throw new UnauthorizedAccessException("An authenticated user is required.");

    private static NutritionDayTemplateEntry ToTemplateEntry(Guid templateId, NutritionEntry entry)
    {
        var templateEntry = new NutritionDayTemplateEntry { Id = entry.Id, NutritionDayTemplateId = templateId };
        templateEntry.CopyValuesFrom(entry);
        return templateEntry;
    }
}
