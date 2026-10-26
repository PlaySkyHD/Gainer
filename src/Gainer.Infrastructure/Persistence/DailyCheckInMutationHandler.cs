using Gainer.Core.BodyTracking;
using Gainer.Core.Security;
using Gainer.Core.Values;
using Gainer.Core.Mutations;
using Microsoft.EntityFrameworkCore;

namespace Gainer.Infrastructure.Persistence;

public sealed class DailyCheckInMutationHandler(
    AppDbContext context,
    IUserContext userContext,
    TimeProvider timeProvider,
    IChangeCollector? changeCollector = null) : IDailyCheckInMutationHandler
{
    public async Task<DailyCheckInSnapshot> CreateAsync(
        CreateDailyCheckInMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        _ = CurrentUserId();
        Validate(mutation.Values);
        // Only the user's own stored check-in with this id is a competing stand. Another id on a stored date and a
        // foreign id stay on every retry and no pull heals them; their unique violations reach the sync processor,
        // which reports them as a permanent invalid payload (like a nutrition day).
        if (await context.DailyCheckIns.AsNoTracking().AnyAsync(item => item.Id == mutation.CheckInId, cancellationToken))
        {
            throw new DailyCheckInConflictException("A check-in already exists for this id.");
        }
        DateTime utcNow = timeProvider.GetUtcNow().UtcDateTime;
        var checkIn = new DailyCheckIn
        {
            Id = mutation.CheckInId,
            LocalDate = mutation.LocalDate,
            CreatedAtUtc = utcNow,
            UpdatedAtUtc = utcNow,
            Version = 1,
        };
        Apply(checkIn, mutation.Values);
        context.DailyCheckIns.Add(checkIn);
        await context.SaveChangesAsync(cancellationToken);
        DailyCheckInSnapshot snapshot = BodyTrackingSnapshots.CheckIn(checkIn);
        changeCollector?.CaptureUpsert(snapshot);
        return snapshot;
    }

    public async Task<DailyCheckInSnapshot> CorrectAsync(
        CorrectDailyCheckInMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        _ = CurrentUserId();
        Validate(mutation.Values);
        DailyCheckIn checkIn = await context.DailyCheckIns
            .SingleOrDefaultAsync(item => item.Id == mutation.CheckInId, cancellationToken)
            ?? throw new DailyCheckInNotFoundException();
        if (checkIn.Version != mutation.BaseVersion)
        {
            throw new DailyCheckInConflictException("The check-in changed since the supplied base version.");
        }

        Apply(checkIn, mutation.Values);
        checkIn.UpdatedAtUtc = timeProvider.GetUtcNow().UtcDateTime;
        checkIn.Version++;
        try
        {
            await context.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateConcurrencyException)
        {
            throw new DailyCheckInConflictException("The check-in changed concurrently.");
        }
        DailyCheckInSnapshot snapshot = BodyTrackingSnapshots.CheckIn(checkIn);
        changeCollector?.CaptureUpsert(snapshot);
        return snapshot;
    }

    private Guid CurrentUserId() =>
        userContext.UserId ?? throw new UnauthorizedAccessException("An authenticated user is required.");

    private static void Validate(DailyCheckInValues values)
    {
        var errors = new Dictionary<string, string>(StringComparer.Ordinal);
        if (!Kilograms.TryCreate(values.WeightKg, out Kilograms weight) || !weight.IsPositive ||
            values.WeightKg > BodyTrackingLimits.MaxWeightKg)
        {
            errors[nameof(values.WeightKg)] = $"Weight must be positive and at most {BodyTrackingLimits.MaxWeightKg} kg.";
        }
        ValidateOptional<Kilocalories>(values.CaloriesKcal, nameof(values.CaloriesKcal), BodyTrackingLimits.MaxCheckInKilocalories, Kilocalories.TryCreate, errors);
        ValidateOptional<Grams>(values.ProteinGrams, nameof(values.ProteinGrams), BodyTrackingLimits.MaxCheckInMacroGrams, Grams.TryCreate, errors);
        ValidateOptional<Grams>(values.CarbohydrateGrams, nameof(values.CarbohydrateGrams), BodyTrackingLimits.MaxCheckInMacroGrams, Grams.TryCreate, errors);
        ValidateOptional<Grams>(values.FatGrams, nameof(values.FatGrams), BodyTrackingLimits.MaxCheckInMacroGrams, Grams.TryCreate, errors);
        if (values.Steps is { } steps && !Gainer.Core.Values.Steps.TryCreate(steps, out _))
        {
            errors[nameof(values.Steps)] = "Steps cannot be negative.";
        }
        if (values.SleepMinutes is { } sleep && !Gainer.Core.Values.SleepMinutes.TryCreate(sleep, out _))
        {
            errors[nameof(values.SleepMinutes)] = "Sleep must be between 0 and 1440 minutes.";
        }
        if (values.RestingHeartRateBpm is < 25 or > 150)
        {
            errors[nameof(values.RestingHeartRateBpm)] = "Resting heart rate must be between 25 and 150 bpm.";
        }
        if (values.RestingHrvMs is < 1 or > 300)
        {
            errors[nameof(values.RestingHrvMs)] = "Resting HRV must be between 1 and 300 ms.";
        }
        if (errors.Count > 0)
        {
            throw new DailyCheckInValidationException(errors);
        }
    }

    private static void ValidateOptional<T>(
        decimal? value,
        string field,
        decimal maximum,
        TryCreateDecimal<T> tryCreate,
        Dictionary<string, string> errors)
    {
        if (value is { } number && (!tryCreate(number, out _) || number > maximum))
        {
            errors[field] = $"{field} must be between 0 and {maximum}.";
        }
    }

    private static void Apply(DailyCheckIn checkIn, DailyCheckInValues values)
    {
        checkIn.WeightKg = values.WeightKg;
        checkIn.CaloriesKcal = values.CaloriesKcal;
        checkIn.ProteinGrams = values.ProteinGrams;
        checkIn.CarbohydrateGrams = values.CarbohydrateGrams;
        checkIn.FatGrams = values.FatGrams;
        checkIn.Steps = values.Steps;
        checkIn.SleepMinutes = values.SleepMinutes;
        checkIn.RestingHeartRateBpm = values.RestingHeartRateBpm;
        checkIn.RestingHrvMs = values.RestingHrvMs;
    }

    private delegate bool TryCreateDecimal<T>(decimal value, out T result);
}
