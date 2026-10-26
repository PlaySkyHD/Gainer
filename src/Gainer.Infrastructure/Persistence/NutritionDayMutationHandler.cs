using Gainer.Core.Mutations;
using Gainer.Core.Nutrition;
using Gainer.Core.Security;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;

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
        await using IDbContextTransaction? transaction = context.Database.CurrentTransaction is null
            ? await context.Database.BeginTransactionAsync(cancellationToken)
            : null;
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
            // Removals are flushed before the stable entry IDs and positions are reused by the replacement rows.
            context.NutritionEntries.RemoveRange(day.Entries.ToArray());
            await SaveOrConflictAsync(cancellationToken);
            day.UpdatedAtUtc = utcNow;
            day.Version++;
        }
        day.DayKind = mutation.DayKind;

        NutritionEntry[] replacementEntries = mutation.Entries
            .Select(input => CreateEntry(day.Id, input))
            .ToArray();
        foreach (NutritionEntry entry in replacementEntries)
        {
            context.NutritionEntries.Add(entry);
        }

        await SaveOrConflictAsync(cancellationToken);
        if (transaction is not null) await transaction.CommitAsync(cancellationToken);

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

    private async Task SaveOrConflictAsync(CancellationToken cancellationToken)
    {
        try
        {
            await context.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateConcurrencyException)
        {
            throw new NutritionDayConflictException("The nutrition day changed concurrently.");
        }
        // Unique violations are not a stale version: the lookup above already found the user's own day, so a key
        // violation means the id belongs to another user, and another id on a stored date or reused entry ids stay
        // on every retry. No pull heals them; the sync processor reports them as a permanent invalid payload.
    }

    private Guid CurrentUserId() =>
        userContext.UserId ?? throw new UnauthorizedAccessException("An authenticated user is required.");

    internal static NutritionEntry CreateEntry(Guid dayId, NutritionEntryInput input)
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
            PieceGrams = input.Portion?.PieceGrams,
            PieceCount = input.Portion?.PieceCount,
            Kilocalories = totals.Kilocalories,
            ProteinGrams = totals.ProteinGrams,
            CarbohydrateGrams = totals.CarbohydrateGrams,
            FatGrams = totals.FatGrams,
            SaltGrams = totals.SaltGrams,
            FiberGrams = totals.FiberGrams,
            Provider = input.Source?.Provider,
            Barcode = input.Source?.Barcode,
            RetrievedAtUtc = input.Source?.RetrievedAtUtc,
            BasisGrams = basis,
            KilocaloriesPerBasis = Round(input.Per100Grams.Kilocalories * factor),
            ProteinGramsPerBasis = Scale(input.Per100Grams.ProteinGrams, factor),
            CarbohydrateGramsPerBasis = Scale(input.Per100Grams.CarbohydrateGrams, factor),
            FatGramsPerBasis = Scale(input.Per100Grams.FatGrams, factor),
            SaltGramsPerBasis = Scale(input.Per100Grams.SaltGrams, factor),
            FiberGramsPerBasis = Scale(input.Per100Grams.FiberGrams, factor),
        };
    }

    private static decimal Round(decimal value) => decimal.Round(value, 2, MidpointRounding.AwayFromZero);
    private static decimal? Scale(decimal? value, decimal factor) => value is null ? null : Round(value.Value * factor);
}
