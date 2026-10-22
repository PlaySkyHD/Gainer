using Gainer.Core.Nutrition;
using Gainer.Core.Security;
using Gainer.Core.Mutations;
using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace Gainer.Infrastructure.Persistence;

public sealed class NutritionTargetScheduleMutationHandler(
    AppDbContext context,
    IUserContext userContext,
    TimeProvider timeProvider,
    IChangeCollector? changeCollector = null) : INutritionTargetScheduleMutationHandler
{
    public async Task<NutritionTargetScheduleSnapshot> SaveAsync(
        SaveNutritionTargetScheduleMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        _ = CurrentUserId();
        NutritionTargetSchedule? schedule = await context.NutritionTargetSchedules
            .Include(item => item.Versions)
            .SingleOrDefaultAsync(item => item.Id == mutation.NutritionTargetScheduleId, cancellationToken);
        DateTime utcNow = timeProvider.GetUtcNow().UtcDateTime;
        DateOnly today = DateOnly.FromDateTime(utcNow);
        NutritionTargetVersionDraft[] incoming = mutation.Values.Versions.OrderBy(item => item.EffectiveFrom).ToArray();
        var materialized = new List<NutritionTargetVersion>(incoming.Length);
        if (schedule is null)
        {
            if (mutation.BaseVersion != 0) throw new NutritionTargetScheduleNotFoundException();
            schedule = new NutritionTargetSchedule
            {
                Id = mutation.NutritionTargetScheduleId,
                CreatedAtUtc = utcNow,
                UpdatedAtUtc = utcNow,
                Version = 1,
            };
            context.NutritionTargetSchedules.Add(schedule);
            foreach (NutritionTargetVersionDraft item in incoming)
            {
                NutritionTargetVersion addition = CreateVersion(schedule.Id, item);
                context.NutritionTargetVersions.Add(addition);
                materialized.Add(addition);
            }
        }
        else
        {
            if (schedule.Version != mutation.BaseVersion)
                throw new NutritionTargetScheduleConflictException("The nutrition target schedule changed since the supplied base version.");
            ReconcileVersions(schedule, incoming, today, materialized);
            schedule.UpdatedAtUtc = utcNow;
            schedule.Version++;
        }
        try { await context.SaveChangesAsync(cancellationToken); }
        catch (DbUpdateConcurrencyException)
        {
            throw new NutritionTargetScheduleConflictException("The nutrition target schedule changed concurrently.");
        }
        catch (DbUpdateException exception) when (exception.InnerException is PostgresException { SqlState: PostgresErrorCodes.UniqueViolation })
        {
            throw new NutritionTargetScheduleConflictException("A target schedule or effective date already exists.");
        }

        NutritionTargetScheduleSnapshot snapshot = SmartNutritionSnapshots.TargetSchedule(schedule, materialized);
        changeCollector?.CaptureUpsert(snapshot);
        return snapshot;
    }

    private void ReconcileVersions(
        NutritionTargetSchedule schedule,
        IReadOnlyCollection<NutritionTargetVersionDraft> incoming,
        DateOnly today,
        List<NutritionTargetVersion> materialized)
    {
        NutritionTargetVersion[] stored = schedule.Versions.ToArray();
        foreach (NutritionTargetVersion version in stored)
        {
            NutritionTargetVersionDraft? candidate = incoming.SingleOrDefault(item => item.TargetVersionId == version.Id);
            if (version.EffectiveFrom <= today)
            {
                ReconcileEffectiveVersion(version, candidate, incoming, today);
                materialized.Add(version);
                continue;
            }

            if (candidate is null)
            {
                context.NutritionTargetVersions.Remove(version);
                continue;
            }
            Apply(version, candidate);
            materialized.Add(version);
        }

        HashSet<Guid> storedIds = stored.Select(item => item.Id).ToHashSet();
        AddNewVersions(schedule, incoming.Where(item => !storedIds.Contains(item.TargetVersionId)), today, materialized);
    }

    private static void ReconcileEffectiveVersion(
        NutritionTargetVersion version,
        NutritionTargetVersionDraft? candidate,
        IReadOnlyCollection<NutritionTargetVersionDraft> incoming,
        DateOnly today)
    {
        if (candidate is null)
            throw new NutritionTargetScheduleConflictException("Effective target phases cannot be removed.");
        if (!Matches(version, candidate))
        {
            if (!CanCloseOpenPhase(version, candidate, incoming, today))
                throw new NutritionTargetScheduleConflictException("Effective target phases are immutable except for ending an open phase before a future successor.");
            version.EffectiveUntil = candidate.EffectiveUntil;
        }
    }

    private void AddNewVersions(
        NutritionTargetSchedule schedule,
        IEnumerable<NutritionTargetVersionDraft> additions,
        DateOnly today,
        List<NutritionTargetVersion> materialized)
    {
        foreach (NutritionTargetVersionDraft item in additions)
        {
            if (item.EffectiveFrom < today)
                throw new NutritionTargetScheduleConflictException("New target phases cannot start in the past.");
            NutritionTargetVersion addition = CreateVersion(schedule.Id, item);
            context.NutritionTargetVersions.Add(addition);
            materialized.Add(addition);
        }
    }

    private static bool Matches(NutritionTargetVersion stored, NutritionTargetVersionDraft candidate) =>
        stored.EffectiveFrom == candidate.EffectiveFrom &&
        stored.EffectiveUntil == candidate.EffectiveUntil &&
        string.Equals(stored.Name, candidate.Name, StringComparison.Ordinal) &&
        stored.Category == candidate.Category &&
        stored.InputMode == candidate.InputMode &&
        stored.Kilocalories == candidate.Kilocalories &&
        stored.ProteinGrams == candidate.ProteinGrams &&
        stored.CarbohydrateGrams == candidate.CarbohydrateGrams &&
        stored.FatGrams == candidate.FatGrams &&
        stored.ProteinPercent == candidate.ProteinPercent &&
        stored.CarbohydratePercent == candidate.CarbohydratePercent &&
        stored.FatPercent == candidate.FatPercent &&
        stored.SaltGrams == candidate.SaltGrams &&
        stored.Origin == candidate.Origin &&
        string.Equals(stored.AlgorithmVersion, candidate.AlgorithmVersion, StringComparison.Ordinal) &&
        string.Equals(stored.Reason, candidate.Reason, StringComparison.Ordinal);

    private static bool CanCloseOpenPhase(
        NutritionTargetVersion stored,
        NutritionTargetVersionDraft candidate,
        IReadOnlyCollection<NutritionTargetVersionDraft> incoming,
        DateOnly today)
    {
        if (stored.EffectiveUntil is not null || candidate.EffectiveUntil is null || candidate.EffectiveUntil < today)
            return false;
        NutritionTargetVersionDraft withoutChangedEnd = candidate with { EffectiveUntil = stored.EffectiveUntil };
        if (!Matches(stored, withoutChangedEnd)) return false;
        return incoming.Any(item =>
            item.TargetVersionId != candidate.TargetVersionId &&
            item.EffectiveFrom == candidate.EffectiveUntil.Value.AddDays(1));
    }

    private static void Apply(NutritionTargetVersion target, NutritionTargetVersionDraft input)
    {
        target.Name = input.Name;
        target.Category = input.Category;
        target.EffectiveFrom = input.EffectiveFrom;
        target.EffectiveUntil = input.EffectiveUntil;
        target.Kilocalories = input.Kilocalories;
        target.InputMode = input.InputMode;
        target.ProteinGrams = input.ProteinGrams;
        target.CarbohydrateGrams = input.CarbohydrateGrams;
        target.FatGrams = input.FatGrams;
        target.ProteinPercent = input.ProteinPercent;
        target.CarbohydratePercent = input.CarbohydratePercent;
        target.FatPercent = input.FatPercent;
        target.SaltGrams = input.SaltGrams;
        target.Origin = input.Origin;
        target.AlgorithmVersion = input.AlgorithmVersion;
        target.Reason = input.Reason;
    }

    private Guid CurrentUserId() =>
        userContext.UserId ?? throw new UnauthorizedAccessException("An authenticated user is required.");

    private static NutritionTargetVersion CreateVersion(Guid scheduleId, NutritionTargetVersionDraft input) => new()
    {
        Id = input.TargetVersionId,
        NutritionTargetScheduleId = scheduleId,
        Name = input.Name,
        Category = input.Category,
        EffectiveFrom = input.EffectiveFrom,
        EffectiveUntil = input.EffectiveUntil,
        Kilocalories = input.Kilocalories,
        InputMode = input.InputMode,
        ProteinGrams = input.ProteinGrams,
        CarbohydrateGrams = input.CarbohydrateGrams,
        FatGrams = input.FatGrams,
        ProteinPercent = input.ProteinPercent,
        CarbohydratePercent = input.CarbohydratePercent,
        FatPercent = input.FatPercent,
        SaltGrams = input.SaltGrams,
        Origin = input.Origin,
        AlgorithmVersion = input.AlgorithmVersion,
        Reason = input.Reason,
    };
}
