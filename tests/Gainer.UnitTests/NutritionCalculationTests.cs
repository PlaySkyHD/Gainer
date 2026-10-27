using Gainer.Core.Nutrition;

namespace Gainer.UnitTests;

[TestClass]
public sealed class NutritionCalculationTests
{
    private static readonly string[] ExpectedEntryErrorFields = ["EntryId", "Meal", "Position", "ProductName"];

    [TestMethod]
    public void CalculateScalesPerHundredGramValuesAndRoundsAwayFromZero()
    {
        NutritionTotals result = NutritionCalculator.Calculate(
            amountGrams: 33.33m,
            new NutritionPer100Grams(250.55m, 20.25m, 10.15m, 3.05m));

        Assert.AreEqual(83.51m, result.Kilocalories);
        Assert.AreEqual(6.75m, result.ProteinGrams);
        Assert.AreEqual(3.38m, result.CarbohydrateGrams);
        Assert.AreEqual(1.02m, result.FatGrams);
    }

    [TestMethod]
    public void SaltIsScaledSummedAndStaysMissingWithoutValues()
    {
        NutritionTotals bread = NutritionCalculator.Calculate(50m, new NutritionPer100Grams(250m, 8m, 45m, 2m, 1.25m));
        NutritionTotals apple = NutritionCalculator.Calculate(150m, new NutritionPer100Grams(52m, null, 14m, null));
        Assert.AreEqual(0.63m, bread.SaltGrams);
        Assert.IsNull(apple.SaltGrams);

        NutritionTotals day = NutritionCalculator.Sum([bread, apple, bread]);
        Assert.AreEqual(1.26m, day.SaltGrams);
        Assert.IsNull(NutritionCalculator.Sum([apple]).SaltGrams);
        Assert.AreEqual(1.26m, NutritionCalculator.Scale(bread, 2m).SaltGrams);

        NutritionValidationException error = Assert.Throws<NutritionValidationException>(() =>
            NutritionCalculator.Calculate(100m, new NutritionPer100Grams(100m, null, null, null, 101m)));
        Assert.IsTrue(error.Errors.ContainsKey("SaltGramsPer100Grams"));
    }

    [TestMethod]
    public void FiberIsScaledSummedAndStaysMissingWithoutValues()
    {
        NutritionTotals oats = NutritionCalculator.Calculate(80m, new NutritionPer100Grams(370m, 13m, 59m, 7m, FiberGrams: 10m));
        NutritionTotals apple = NutritionCalculator.Calculate(150m, new NutritionPer100Grams(52m, null, 14m, null));
        Assert.AreEqual(8m, oats.FiberGrams);
        Assert.IsNull(apple.FiberGrams);

        NutritionTotals day = NutritionCalculator.Sum([oats, apple]);
        Assert.AreEqual(8m, day.FiberGrams);
        Assert.IsNull(NutritionCalculator.Sum([apple]).FiberGrams);
        Assert.AreEqual(16m, NutritionCalculator.Scale(oats, 2m).FiberGrams);

        foreach (decimal invalid in new[] { -1m, 101m })
        {
            NutritionValidationException error = Assert.Throws<NutritionValidationException>(() =>
                NutritionCalculator.Calculate(100m, new NutritionPer100Grams(100m, null, null, null, FiberGrams: invalid)));
            Assert.IsTrue(error.Errors.ContainsKey("FiberGramsPer100Grams"));
        }
    }

    [TestMethod]
    public void EstimatedComponentsCarryFiberAndRejectInvalidFiber()
    {
        MealEstimateComponentDraft soup = MealEstimateComponentDraft.Create(
            "Linsensuppe", 400m, 360m, 22m, 48m, 6m, MealEstimateConfidence.Medium, [], fiberGrams: 12m);
        Assert.AreEqual(12m, soup.FiberGrams);

        NutritionValidationException error = Assert.Throws<NutritionValidationException>(() =>
            MealEstimateComponentDraft.Create(
                "Linsensuppe", 400m, 360m, null, null, null, MealEstimateConfidence.Medium, [], fiberGrams: -1m));
        Assert.IsTrue(error.Errors.ContainsKey("FiberGrams"));
    }

    [TestMethod]
    public void ZeroCalorieFoodsLikeSaltAreAllowed()
    {
        NutritionTotals salt = NutritionCalculator.Calculate(3m, new NutritionPer100Grams(0m, 0m, 0m, 0m, 100m));
        Assert.AreEqual(0m, salt.Kilocalories);
        Assert.AreEqual(3m, salt.SaltGrams);
    }

    [TestMethod]
    public void EstimatedComponentsAllowZeroCalorieSaltAndRejectInvalidSalt()
    {
        MealEstimateComponentDraft salt = MealEstimateComponentDraft.Create(
            "Salz", 6m, 0m, 0m, 0m, 0m, MealEstimateConfidence.High, [], saltGrams: 6m);
        Assert.AreEqual(0m, salt.Kilocalories);
        Assert.AreEqual(6m, salt.SaltGrams);

        foreach (decimal invalid in new[] { -1m, 101m })
        {
            NutritionValidationException error = Assert.Throws<NutritionValidationException>(() =>
                MealEstimateComponentDraft.Create(
                    "Pizza", 350m, 890m, null, null, null, MealEstimateConfidence.Medium, [], saltGrams: invalid));
            Assert.IsTrue(error.Errors.ContainsKey("SaltGrams"));
        }
    }

    [TestMethod]
    public void PiecesMustMatchTheAmountAndNeedAPieceWeight()
    {
        NutritionEntryInput eggs = NutritionEntryInput.Create(
            Guid.NewGuid(), MealType.Breakfast, 0, "Ei", 200m, new NutritionPer100Grams(155m, 13m, 1m, 11m),
            portion: new NutritionPortion(50m, 4m));
        Assert.AreEqual(4m, eggs.Portion!.PieceCount);
        Assert.AreEqual(200m, eggs.Portion.AmountGrams);

        NutritionEntryInput remembered = NutritionEntryInput.Create(
            Guid.NewGuid(), MealType.Breakfast, 0, "Ei", 130m, new NutritionPer100Grams(155m, 13m, 1m, 11m),
            portion: new NutritionPortion(50m, null));
        Assert.IsNull(remembered.Portion!.PieceCount, "A piece weight alone is kept for later.");

        NutritionValidationException mismatch = Assert.Throws<NutritionValidationException>(() =>
            NutritionEntryInput.Create(
                Guid.NewGuid(), MealType.Breakfast, 0, "Ei", 180m, new NutritionPer100Grams(155m, null, null, null),
                portion: new NutritionPortion(50m, 4m)));
        Assert.IsTrue(mismatch.Errors.ContainsKey("AmountGrams"));
        Assert.Throws<NutritionValidationException>(() => NutritionPortion.From(null, 2m));
        Assert.IsNull(NutritionPortion.From(null, null));
    }

    [TestMethod]
    public void EstimatedPiecesAreKeptOnlyWhenConsistent()
    {
        MealEstimateComponentDraft eggs = MealEstimateComponentDraft.Create(
            "Ei", 220m, 341m, 28m, 2m, 24m, MealEstimateConfidence.Medium, [], pieceCount: 4m, pieceGrams: 55m);
        Assert.AreEqual(4m, eggs.PieceCount);
        Assert.AreEqual(55m, eggs.PieceGrams);

        MealEstimateComponentDraft mismatch = MealEstimateComponentDraft.Create(
            "Ei", 200m, 310m, 26m, 2m, 22m, MealEstimateConfidence.Medium, [], pieceCount: 4m, pieceGrams: 55m);
        Assert.IsNull(mismatch.PieceCount);
        Assert.IsNull(mismatch.PieceGrams);
    }

    [TestMethod]
    public void CalculateKeepsMissingMacrosMissing()
    {
        NutritionTotals result = NutritionCalculator.Calculate(
            150m,
            new NutritionPer100Grams(250m, 20m, null, null));

        Assert.AreEqual(375m, result.Kilocalories);
        Assert.AreEqual(30m, result.ProteinGrams);
        Assert.IsNull(result.CarbohydrateGrams);
        Assert.IsNull(result.FatGrams);
    }

    [TestMethod]
    [DataRow("amount", "0", "100")]
    [DataRow("amount", "-1", "100")]
    [DataRow("energy", "100", "-1")]
    [DataRow("protein", "100", "100")]
    public void CalculateRejectsInvalidValues(string invalidField, string amountText, string energyText)
    {
        decimal? protein = invalidField == "protein" ? -1m : 10m;

        NutritionValidationException exception = Assert.Throws<NutritionValidationException>(() =>
            NutritionCalculator.Calculate(
                decimal.Parse(amountText, System.Globalization.CultureInfo.InvariantCulture),
                new NutritionPer100Grams(
                    decimal.Parse(energyText, System.Globalization.CultureInfo.InvariantCulture),
                    protein,
                    10m,
                    10m)));

        Assert.IsTrue(exception.Errors.ContainsKey(invalidField switch
        {
            "amount" => "AmountGrams",
            "energy" => "KilocaloriesPer100Grams",
            _ => "ProteinGramsPer100Grams",
        }));
    }

    [TestMethod]
    public void EntryInputValidatesIdentityTextMealAndPosition()
    {
        NutritionValidationException exception = Assert.Throws<NutritionValidationException>(() =>
            NutritionEntryInput.Create(
                Guid.Empty,
                (MealType)999,
                -1,
                " ",
                100m,
                new NutritionPer100Grams(100m, null, null, null)));

        Assert.AreSequenceEqual(
            ExpectedEntryErrorFields,
            exception.Errors.Keys.ToArray(), SequenceOrder.InAnyOrder);
    }
}
