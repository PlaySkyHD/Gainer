using Gainer.Core.Mutations;
using Gainer.Core.Nutrition;
using Gainer.Core.Security;
using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace Gainer.Infrastructure.Persistence;

public sealed class NutritionDayMutationHandler(
    AppDbContext context,
    IUserContext userContext,
    TimeProvider timeProvider,
    IChangeCollector? changeCollector = null) : INutritionDayMutationHandler
{
    public async Task<NutritionDaySnapshot> SaveAsync(
        SaveNutritionDayMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        _ = CurrentUserId();
        NutritionDay? day = await context.NutritionDays
            .Include(item => item.Entries)
            .SingleOrDefaultAsync(item => item.Id == mutation.NutritionDayId, cancellationToken);
        DateTime utcNow = timeProvider.GetUtcNow().UtcDateTime;
        if (day is null)
        {
            if (mutation.BaseVersion != 0)
            {
                throw new NutritionDayNotFoundException();
            }
            day = new NutritionDay
            {
                Id = mutation.NutritionDayId,
                LocalDate = mutation.LocalDate,
                CreatedAtUtc = utcNow,
                UpdatedAtUtc = utcNow,
                Version = 1,
            };
            context.NutritionDays.Add(day);
        }
        else
        {
            if (day.LocalDate != mutation.LocalDate || day.Version != mutation.BaseVersion)
            {
                throw new NutritionDayConflictException("The nutrition day changed since the supplied base version.");
            }
            context.NutritionEntries.RemoveRange(day.Entries.ToArray());
            day.UpdatedAtUtc = utcNow;
            day.Version++;
        }

        NutritionEntry[] replacementEntries = mutation.Entries
            .Select(input => CreateEntry(day.Id, input))
            .ToArray();
        foreach (NutritionEntry entry in replacementEntries)
        {
            context.NutritionEntries.Add(entry);
        }

        try
        {
            await context.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateConcurrencyException)
        {
            throw new NutritionDayConflictException("The nutrition day changed concurrently.");
        }
        catch (DbUpdateException exception) when (exception.InnerException is PostgresException { SqlState: PostgresErrorCodes.UniqueViolation })
        {
            throw new NutritionDayConflictException("A nutrition day or entry already exists for this identifier, date, or position.");
        }

        NutritionDaySnapshot snapshot = NutritionSnapshots.Day(day, replacementEntries);
        changeCollector?.CaptureUpsert(snapshot);
        return snapshot;
    }

    public async Task<long> DeleteAsync(
        DeleteNutritionDayMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        _ = CurrentUserId();
        NutritionDay day = await context.NutritionDays
            .SingleOrDefaultAsync(item => item.Id == mutation.NutritionDayId, cancellationToken)
            ?? throw new NutritionDayNotFoundException();
        if (day.Version != mutation.BaseVersion)
        {
            throw new NutritionDayConflictException("The nutrition day changed since the supplied base version.");
        }

        long deletedVersion = day.Version + 1;
        context.NutritionDays.Remove(day);
        try
        {
            await context.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateConcurrencyException)
        {
            throw new NutritionDayConflictException("The nutrition day changed concurrently.");
        }
        changeCollector?.CaptureDeletion(ResourceKey.Create(ResourceKind.NutritionDay, day.Id), deletedVersion);
        return deletedVersion;
    }

    private Guid CurrentUserId() =>
        userContext.UserId ?? throw new UnauthorizedAccessException("An authenticated user is required.");

    private static NutritionEntry CreateEntry(Guid dayId, NutritionEntryInput input)
    {
        NutritionTotals totals = NutritionCalculator.Calculate(input.AmountGrams, input.Per100Grams);
        decimal basis = input.Source?.BasisGrams ?? 100m;
        if (basis <= 0m)
        {
            throw new NutritionValidationException(new Dictionary<string, string>
            {
                ["BasisGrams"] = "BasisGrams must be positive.",
            });
        }
        decimal factor = basis / 100m;
        return new NutritionEntry
        {
            Id = input.EntryId,
            NutritionDayId = dayId,
            Meal = input.Meal,
            Position = input.Position,
            ProductName = input.ProductName,
            Brand = input.Brand,
            AmountGrams = input.AmountGrams,
            Kilocalories = totals.Kilocalories,
            ProteinGrams = totals.ProteinGrams,
            CarbohydrateGrams = totals.CarbohydrateGrams,
            FatGrams = totals.FatGrams,
            Provider = input.Source?.Provider,
            Barcode = input.Source?.Barcode,
            RetrievedAtUtc = input.Source?.RetrievedAtUtc,
            BasisGrams = basis,
            KilocaloriesPerBasis = Round(input.Per100Grams.Kilocalories * factor),
            ProteinGramsPerBasis = Scale(input.Per100Grams.ProteinGrams, factor),
            CarbohydrateGramsPerBasis = Scale(input.Per100Grams.CarbohydrateGrams, factor),
            FatGramsPerBasis = Scale(input.Per100Grams.FatGrams, factor),
        };
    }

    private static decimal Round(decimal value) => decimal.Round(value, 2, MidpointRounding.AwayFromZero);
    private static decimal? Scale(decimal? value, decimal factor) => value is null ? null : Round(value.Value * factor);
}
