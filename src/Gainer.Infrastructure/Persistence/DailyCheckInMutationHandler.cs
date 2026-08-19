using Gainer.Core.BodyTracking;
using Gainer.Core.Security;
using Gainer.Core.Values;
using Gainer.Core.Mutations;
using Microsoft.EntityFrameworkCore;
using Npgsql;

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
        try
        {
            await context.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateException exception) when (IsUniqueViolation(exception))
        {
            throw new DailyCheckInConflictException("A check-in already exists for this id or local date.");
        }
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
        if (!Kilograms.TryCreate(values.WeightKg, out Kilograms weight) || !weight.IsPositive)
        {
            errors[nameof(values.WeightKg)] = "Weight must be positive.";
        }
        ValidateOptional<Kilocalories>(values.CaloriesKcal, nameof(values.CaloriesKcal), Kilocalories.TryCreate, errors);
        ValidateOptional<Grams>(values.ProteinGrams, nameof(values.ProteinGrams), Grams.TryCreate, errors);
        ValidateOptional<Grams>(values.CarbohydrateGrams, nameof(values.CarbohydrateGrams), Grams.TryCreate, errors);
        ValidateOptional<Grams>(values.FatGrams, nameof(values.FatGrams), Grams.TryCreate, errors);
        if (values.Steps is { } steps && !Gainer.Core.Values.Steps.TryCreate(steps, out _))
        {
            errors[nameof(values.Steps)] = "Steps cannot be negative.";
        }
        if (values.SleepMinutes is { } sleep && !Gainer.Core.Values.SleepMinutes.TryCreate(sleep, out _))
        {
            errors[nameof(values.SleepMinutes)] = "Sleep must be between 0 and 1440 minutes.";
        }
        if (errors.Count > 0)
        {
            throw new DailyCheckInValidationException(errors);
        }
    }

    private static void ValidateOptional<T>(
        decimal? value,
        string field,
        TryCreateDecimal<T> tryCreate,
        IDictionary<string, string> errors)
    {
        if (value is { } number && !tryCreate(number, out _))
        {
            errors[field] = $"{field} cannot be negative.";
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
    }

    private static bool IsUniqueViolation(DbUpdateException exception) =>
        exception.InnerException is PostgresException { SqlState: PostgresErrorCodes.UniqueViolation };

    private delegate bool TryCreateDecimal<T>(decimal value, out T result);
}
