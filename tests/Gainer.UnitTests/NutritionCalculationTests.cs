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
    public void ZeroCalorieFoodsLikeSaltAreAllowed()
    {
        NutritionTotals salt = NutritionCalculator.Calculate(3m, new NutritionPer100Grams(0m, 0m, 0m, 0m, 100m));
        Assert.AreEqual(0m, salt.Kilocalories);
        Assert.AreEqual(3m, salt.SaltGrams);
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

        CollectionAssert.AreEquivalent(
            ExpectedEntryErrorFields,
            exception.Errors.Keys.ToArray());
    }
}
