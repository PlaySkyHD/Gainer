using Gainer.Core.Nutrition;
using Gainer.Core.Security;
using Gainer.Core.Mutations;
using Microsoft.EntityFrameworkCore;

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
        // Only the "one schedule per user" index stands for another stored schedule of this user. The lookup already
        // found the user's own id, so a key violation means a foreign schedule or version id; that and other unique
        // violations reach the sync processor as a permanent invalid payload.
        catch (DbUpdateException exception) when (
            context.IsUniqueIndexViolation<NutritionTargetSchedule>(exception, nameof(NutritionTargetSchedule.UserId)))
        {
            throw new NutritionTargetScheduleConflictException("The user already has a nutrition target schedule.");
        }

        NutritionTargetScheduleSnapshot snapshot = SmartNutritionSnapshots.TargetSchedule(schedule, materialized);
        changeCollector?.CaptureUpsert(snapshot);
        return snapshot;
    }

    /// <summary>
    /// Applies the incoming schedule. S is the start of the newest incoming version: days before S stay
    /// unchanged except for ending the version that covers S - 1; the version starting at S may change;
    /// later versions may only be dropped while they have not begun. The rules depend on S rather than on
    /// the server date so that offline edits still sync days later.
    /// </summary>
    private void ReconcileVersions(
        NutritionTargetSchedule schedule,
        IReadOnlyList<NutritionTargetVersionDraft> incoming,
        DateOnly today,
        List<NutritionTargetVersion> materialized)
    {
        DateOnly changeStart = incoming[^1].EffectiveFrom;
        DateOnly dayBefore = changeStart.AddDays(-1);
        Dictionary<Guid, NutritionTargetVersionDraft> incomingById = incoming.ToDictionary(item => item.TargetVersionId);
        foreach (NutritionTargetVersion version in schedule.Versions.ToArray())
        {
            incomingById.Remove(version.Id, out NutritionTargetVersionDraft? candidate);
            if (version.EffectiveFrom >= changeStart && candidate is null)
            {
                if (version.EffectiveFrom <= today.AddDays(1))
                    throw new NutritionTargetScheduleConflictException("Target versions that have begun cannot be removed.");
                context.NutritionTargetVersions.Remove(version);
                continue;
            }
            if (candidate is null)
                throw new NutritionTargetScheduleConflictException("Target versions before the change cannot be removed.");
            if (candidate.EffectiveFrom != version.EffectiveFrom)
                throw new NutritionTargetScheduleConflictException("The start of a stored target version cannot change.");
            if (version.EffectiveFrom == changeStart)
            {
                Apply(version, candidate);
            }
            else if (!Matches(version, candidate))
            {
                bool coversDayBefore = version.EffectiveUntil is null || version.EffectiveUntil >= dayBefore;
                if (!coversDayBefore ||
                    candidate.EffectiveUntil != dayBefore ||
                    !Matches(version, candidate with { EffectiveUntil = version.EffectiveUntil }))
                    throw new NutritionTargetScheduleConflictException("Target versions before the change are immutable except for ending the previous one.");
                version.EffectiveUntil = candidate.EffectiveUntil;
            }
            materialized.Add(version);
        }

        foreach (NutritionTargetVersionDraft addition in incomingById.Values)
        {
            if (addition.EffectiveFrom != changeStart)
                throw new NutritionTargetScheduleConflictException("New target versions can only start where the change starts.");
            NutritionTargetVersion created = CreateVersion(schedule.Id, addition);
            context.NutritionTargetVersions.Add(created);
            materialized.Add(created);
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
        stored.FiberGrams == candidate.FiberGrams &&
        RestDayMatches(stored, candidate.RestDay) &&
        stored.Origin == candidate.Origin &&
        string.Equals(stored.AlgorithmVersion, candidate.AlgorithmVersion, StringComparison.Ordinal) &&
        string.Equals(stored.Reason, candidate.Reason, StringComparison.Ordinal);

    private static bool RestDayMatches(NutritionTargetVersion stored, NutritionRestDayTargetDraft? rest) =>
        rest is null
            ? stored.RestKilocalories is null
            : stored.RestKilocalories == rest.Kilocalories &&
              stored.RestInputMode == rest.InputMode &&
              stored.RestProteinGrams == rest.ProteinGrams &&
              stored.RestCarbohydrateGrams == rest.CarbohydrateGrams &&
              stored.RestFatGrams == rest.FatGrams &&
              stored.RestProteinPercent == rest.ProteinPercent &&
              stored.RestCarbohydratePercent == rest.CarbohydratePercent &&
              stored.RestFatPercent == rest.FatPercent;

    private static void ApplyRestDay(NutritionTargetVersion target, NutritionRestDayTargetDraft? rest)
    {
        target.RestInputMode = rest?.InputMode;
        target.RestKilocalories = rest?.Kilocalories;
        target.RestProteinGrams = rest?.ProteinGrams;
        target.RestCarbohydrateGrams = rest?.CarbohydrateGrams;
        target.RestFatGrams = rest?.FatGrams;
        target.RestProteinPercent = rest?.ProteinPercent;
        target.RestCarbohydratePercent = rest?.CarbohydratePercent;
        target.RestFatPercent = rest?.FatPercent;
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
        target.FiberGrams = input.FiberGrams;
        ApplyRestDay(target, input.RestDay);
        target.Origin = input.Origin;
        target.AlgorithmVersion = input.AlgorithmVersion;
        target.Reason = input.Reason;
    }

    private Guid CurrentUserId() =>
        userContext.UserId ?? throw new UnauthorizedAccessException("An authenticated user is required.");

    private static NutritionTargetVersion CreateVersion(Guid scheduleId, NutritionTargetVersionDraft input)
    {
        var version = new NutritionTargetVersion
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
            FiberGrams = input.FiberGrams,
            Origin = input.Origin,
            AlgorithmVersion = input.AlgorithmVersion,
            Reason = input.Reason,
        };
        ApplyRestDay(version, input.RestDay);
        return version;
    }
}
