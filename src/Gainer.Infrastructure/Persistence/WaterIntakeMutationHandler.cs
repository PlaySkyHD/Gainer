using Gainer.Core.Mutations;
using Gainer.Core.Nutrition;
using Gainer.Core.Security;
using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace Gainer.Infrastructure.Persistence;

/// <summary>
/// Adds to or sets the water amount of one local day. A missing day is created from base version 0;
/// a day is never deleted, 0 ml stays a stored state.
/// </summary>
public sealed class WaterIntakeMutationHandler(
    AppDbContext context,
    IUserContext userContext,
    TimeProvider timeProvider,
    IChangeCollector? changeCollector = null) : IWaterIntakeMutationHandler
{
    public async Task<WaterIntakeDaySnapshot> ChangeAsync(
        ChangeWaterIntakeMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        _ = userContext.UserId ?? throw new UnauthorizedAccessException("An authenticated user is required.");
        WaterIntakeDay? day = await context.WaterIntakeDays
            .SingleOrDefaultAsync(item => item.Id == mutation.WaterIntakeDayId, cancellationToken);
        DateTime utcNow = timeProvider.GetUtcNow().UtcDateTime;
        if (day is null)
        {
            if (mutation.BaseVersion != 0) throw new WaterIntakeNotFoundException();
            day = new WaterIntakeDay
            {
                Id = mutation.WaterIntakeDayId,
                LocalDate = mutation.LocalDate,
                AmountMl = mutation.ApplyTo(0),
                CreatedAtUtc = utcNow,
                UpdatedAtUtc = utcNow,
                Version = 1,
            };
            context.WaterIntakeDays.Add(day);
        }
        else
        {
            if (day.LocalDate != mutation.LocalDate || day.Version != mutation.BaseVersion)
            {
                throw new WaterIntakeConflictException("The water intake changed since the supplied base version.");
            }
            day.AmountMl = mutation.ApplyTo(day.AmountMl);
            day.UpdatedAtUtc = utcNow;
            day.Version++;
        }

        try
        {
            await context.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateConcurrencyException)
        {
            throw new WaterIntakeConflictException("The water intake changed concurrently.");
        }
        catch (DbUpdateException exception) when (exception.InnerException is PostgresException { SqlState: PostgresErrorCodes.UniqueViolation })
        {
            // Another id already holds this local date: a different stored state exists.
            throw new WaterIntakeConflictException("A water intake already exists for this local date.");
        }

        WaterIntakeDaySnapshot snapshot = Snapshot(day);
        changeCollector?.CaptureUpsert(snapshot);
        return snapshot;
    }

    internal static WaterIntakeDaySnapshot Snapshot(WaterIntakeDay day) =>
        new(day.Id, day.LocalDate, day.AmountMl, day.CreatedAtUtc, day.UpdatedAtUtc, day.Version);
}
