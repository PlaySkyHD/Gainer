using Gainer.Core.Mutations;
using Gainer.Core.Nutrition;
using Gainer.Core.Security;
using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace Gainer.Infrastructure.Persistence;

public sealed class ReusableMealMutationHandler(
    AppDbContext context,
    IUserContext userContext,
    TimeProvider timeProvider,
    IChangeCollector? changeCollector = null) : IReusableMealMutationHandler
{
    public async Task<ReusableMealSnapshot> SaveAsync(
        SaveReusableMealMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        _ = CurrentUserId();
        ReusableMeal? meal = await context.ReusableMeals
            .Include(item => item.Components)
            .SingleOrDefaultAsync(item => item.Id == mutation.ReusableMealId, cancellationToken);
        DateTime utcNow = timeProvider.GetUtcNow().UtcDateTime;
        if (meal is null)
        {
            if (mutation.BaseVersion != 0) throw new ReusableMealNotFoundException();
            meal = new ReusableMeal
            {
                Id = mutation.ReusableMealId,
                CreatedAtUtc = utcNow,
                UpdatedAtUtc = utcNow,
                Version = 1,
                Status = ReusableMealStatus.Active,
            };
            context.ReusableMeals.Add(meal);
        }
        else
        {
            if (meal.Version != mutation.BaseVersion)
                throw new ReusableMealConflictException("The reusable meal changed since the supplied base version.");
            if (meal.Status == ReusableMealStatus.Archived)
                throw new ReusableMealConflictException("An archived reusable meal cannot be edited.");
            context.ReusableMealComponents.RemoveRange(meal.Components.ToArray());
            meal.UpdatedAtUtc = utcNow;
            meal.Version++;
        }

        meal.Name = mutation.Values.Name;
        meal.Description = mutation.Values.Description;
        meal.StandardPortion = mutation.Values.StandardPortion;
        ReusableMealComponent[] replacements = mutation.Values.Components
            .Select(item => CreateComponent(meal.Id, item))
            .ToArray();
        context.ReusableMealComponents.AddRange(replacements);
        await SaveAsync(cancellationToken);
        ReusableMealSnapshot snapshot = SmartNutritionSnapshots.ReusableMeal(meal, replacements);
        changeCollector?.CaptureUpsert(snapshot);
        return snapshot;
    }

    public async Task<ReusableMealSnapshot> ArchiveAsync(
        ArchiveReusableMealMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        _ = CurrentUserId();
        ReusableMeal meal = await context.ReusableMeals
            .Include(item => item.Components)
            .SingleOrDefaultAsync(item => item.Id == mutation.ReusableMealId, cancellationToken)
            ?? throw new ReusableMealNotFoundException();
        if (meal.Version != mutation.BaseVersion)
            throw new ReusableMealConflictException("The reusable meal changed since the supplied base version.");
        if (meal.Status != ReusableMealStatus.Archived)
        {
            meal.Status = ReusableMealStatus.Archived;
            meal.UpdatedAtUtc = timeProvider.GetUtcNow().UtcDateTime;
            meal.Version++;
            await SaveAsync(cancellationToken);
        }
        ReusableMealSnapshot snapshot = SmartNutritionSnapshots.ReusableMeal(meal);
        changeCollector?.CaptureUpsert(snapshot);
        return snapshot;
    }

    private async Task SaveAsync(CancellationToken cancellationToken)
    {
        try { await context.SaveChangesAsync(cancellationToken); }
        catch (DbUpdateConcurrencyException)
        {
            throw new ReusableMealConflictException("The reusable meal changed concurrently.");
        }
        catch (DbUpdateException exception) when (exception.InnerException is PostgresException { SqlState: PostgresErrorCodes.UniqueViolation })
        {
            throw new ReusableMealConflictException("A reusable meal component identifier or position already exists.");
        }
    }

    private Guid CurrentUserId() =>
        userContext.UserId ?? throw new UnauthorizedAccessException("An authenticated user is required.");

    private static ReusableMealComponent CreateComponent(Guid reusableMealId, ReusableMealComponentDraft input) => new()
    {
        Id = input.ComponentId,
        ReusableMealId = reusableMealId,
        Position = input.Position,
        Name = input.Name,
        Brand = input.Brand,
        AmountGrams = input.AmountGrams,
        PieceGrams = input.Portion?.PieceGrams,
        PieceCount = input.Portion?.PieceCount,
        Kilocalories = input.Totals.Kilocalories,
        ProteinGrams = input.Totals.ProteinGrams,
        CarbohydrateGrams = input.Totals.CarbohydrateGrams,
        FatGrams = input.Totals.FatGrams,
        SaltGrams = input.Totals.SaltGrams,
        FiberGrams = input.Totals.FiberGrams,
        KilocaloriesPer100Grams = input.Per100Grams.Kilocalories,
        ProteinGramsPer100Grams = input.Per100Grams.ProteinGrams,
        CarbohydrateGramsPer100Grams = input.Per100Grams.CarbohydrateGrams,
        FatGramsPer100Grams = input.Per100Grams.FatGrams,
        SaltGramsPer100Grams = input.Per100Grams.SaltGrams,
        FiberGramsPer100Grams = input.Per100Grams.FiberGrams,
        BasisGrams = input.Source?.BasisGrams ?? 100m,
        Provider = input.Source?.Provider,
        Barcode = input.Source?.Barcode,
        RetrievedAtUtc = input.Source?.RetrievedAtUtc,
    };
}
