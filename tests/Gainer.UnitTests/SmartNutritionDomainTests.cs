using Gainer.Core.Nutrition;

namespace Gainer.UnitTests;

[TestClass]
public sealed class SmartNutritionDomainTests
{
    private static readonly string[] ExpectedPortionErrorFields = ["Name", "StandardPortion"];

    [TestMethod]
    public void ReusableMealDraftNormalizesAndOrdersComponents()
    {
        ReusableMealComponentDraft second = ReusableMealComponentDraft.Create(
            Guid.NewGuid(), 1, " Hähnchen ", 150m,
            new NutritionPer100Grams(165m, 31m, 0m, 3.6m));
        ReusableMealComponentDraft first = ReusableMealComponentDraft.Create(
            Guid.NewGuid(), 0, " Reis ", 200m,
            new NutritionPer100Grams(130m, 2.7m, 28m, 0.3m));

        ReusableMealDraft draft = ReusableMealDraft.Create(" Bowl ", " Meal prep ", 1m, [second, first]);

        Assert.AreEqual("Bowl", draft.Name);
        Assert.AreEqual("Meal prep", draft.Description);
        Assert.AreSequenceEqual(new[] { first.ComponentId, second.ComponentId }, draft.Components.Select(item => item.ComponentId).ToArray());
    }

    [TestMethod]
    public void ReusableMealDraftRejectsDuplicatePositionsAndEmptyComponents()
    {
        ReusableMealComponentDraft component = ReusableMealComponentDraft.Create(
            Guid.NewGuid(), 0, "Reis", 100m,
            new NutritionPer100Grams(130m, 2m, 28m, 0m));

        NutritionValidationException empty = Assert.Throws<NutritionValidationException>(() =>
            ReusableMealDraft.Create("Bowl", null, 1m, []));
        Assert.IsTrue(empty.Errors.ContainsKey("Components"));

        NutritionValidationException duplicate = Assert.Throws<NutritionValidationException>(() =>
            ReusableMealDraft.Create("Bowl", null, 1m, [component, component with { ComponentId = Guid.NewGuid() }]));
        Assert.IsTrue(duplicate.Errors.ContainsKey("Components"));
    }

    [TestMethod]
    [DataRow("0.5", "100", "15", "20", "5")]
    [DataRow("2", "400", "60", "80", "20")]
    public void ScaleTotalsUsesDeterministicAwayFromZeroRounding(
        string factorText,
        string kcalText,
        string proteinText,
        string carbsText,
        string fatText)
    {
        decimal factor = decimal.Parse(factorText, System.Globalization.CultureInfo.InvariantCulture);
        NutritionTotals result = NutritionCalculator.Scale(
            new NutritionTotals(200m, 30m, 40m, 10m), factor);

        Assert.AreEqual(decimal.Parse(kcalText, System.Globalization.CultureInfo.InvariantCulture), result.Kilocalories);
        Assert.AreEqual(decimal.Parse(proteinText, System.Globalization.CultureInfo.InvariantCulture), result.ProteinGrams);
        Assert.AreEqual(decimal.Parse(carbsText, System.Globalization.CultureInfo.InvariantCulture), result.CarbohydrateGrams);
        Assert.AreEqual(decimal.Parse(fatText, System.Globalization.CultureInfo.InvariantCulture), result.FatGrams);
    }

    [TestMethod]
    public void MacroEnergyAndMismatchFollowFourFourNineRule()
    {
        decimal energy = NutritionCalculator.CalculateMacroEnergy(180m, 250m, 80m);

        Assert.AreEqual(2440m, energy);
        Assert.IsFalse(NutritionCalculator.HasMacroEnergyMismatch(2500m, 180m, 250m, 80m));
        Assert.IsTrue(NutritionCalculator.HasMacroEnergyMismatch(3000m, 180m, 250m, 80m));
    }

    [TestMethod]
    public void SaltTargetDefaultsToSixGramsAndIsValidated()
    {
        NutritionTargetVersionDraft standard = NutritionTargetVersionDraft.CreateInGrams(
            Guid.NewGuid(), "Ziel", NutritionGoalCategory.Custom, new DateOnly(2026, 10, 1), null, 2500m, 180m, 260m, 80m);
        Assert.IsNull(standard.SaltGrams);
        Assert.AreEqual(6m, standard.EffectiveSaltGrams);

        NutritionTargetVersionDraft custom = NutritionTargetVersionDraft.CreateInPercent(
            Guid.NewGuid(), "Ziel", NutritionGoalCategory.Custom, new DateOnly(2026, 10, 1), null, 2000m, 30m, 40m, 30m,
            saltGrams: 5m);
        Assert.AreEqual(5m, custom.EffectiveSaltGrams);

        foreach (decimal invalid in new[] { 0m, -1m, 101m })
        {
            NutritionValidationException error = Assert.Throws<NutritionValidationException>(() =>
                NutritionTargetVersionDraft.CreateInGrams(
                    Guid.NewGuid(), "Ziel", NutritionGoalCategory.Custom, new DateOnly(2026, 10, 1), null,
                    2500m, 180m, 260m, 80m, saltGrams: invalid));
            Assert.IsTrue(error.Errors.ContainsKey("SaltGrams"));
        }
    }

    [TestMethod]
    public void FiberTargetDefaultsToThirtyGramsAndIsValidated()
    {
        NutritionTargetVersionDraft standard = NutritionTargetVersionDraft.CreateInGrams(
            Guid.NewGuid(), "Ziel", NutritionGoalCategory.Custom, new DateOnly(2026, 10, 1), null, 2500m, 180m, 260m, 80m);
        Assert.IsNull(standard.FiberGrams);
        Assert.AreEqual(30m, standard.EffectiveFiberGrams);

        NutritionTargetVersionDraft custom = NutritionTargetVersionDraft.CreateInPercent(
            Guid.NewGuid(), "Ziel", NutritionGoalCategory.Custom, new DateOnly(2026, 10, 1), null, 2000m, 30m, 40m, 30m,
            fiberGrams: 25m);
        Assert.AreEqual(25m, custom.EffectiveFiberGrams);

        foreach (decimal invalid in new[] { 0m, -1m, 101m })
        {
            NutritionValidationException error = Assert.Throws<NutritionValidationException>(() =>
                NutritionTargetVersionDraft.CreateInGrams(
                    Guid.NewGuid(), "Ziel", NutritionGoalCategory.Custom, new DateOnly(2026, 10, 1), null,
                    2500m, 180m, 260m, 80m, fiberGrams: invalid));
            Assert.IsTrue(error.Errors.ContainsKey("FiberGrams"));
        }
    }

    [TestMethod]
    public void ReusableMealComponentsScaleFiberAndRejectInvalidFiber()
    {
        ReusableMealComponentDraft beans = ReusableMealComponentDraft.Create(
            Guid.NewGuid(), 0, "Kidneybohnen", 200m, new NutritionPer100Grams(110m, 7m, 15m, 1m, FiberGrams: 6m));
        Assert.AreEqual(12m, beans.Totals.FiberGrams);

        NutritionValidationException error = Assert.Throws<NutritionValidationException>(() =>
            ReusableMealComponentDraft.Create(
                Guid.NewGuid(), 0, "Kidneybohnen", 200m, new NutritionPer100Grams(110m, 7m, 15m, 1m, FiberGrams: 101m)));
        Assert.IsTrue(error.Errors.ContainsKey("FiberGramsPer100Grams"));
    }

    [TestMethod]
    public void TargetScheduleSortsVersionsAndFindsEffectiveVersion()
    {
        NutritionTargetVersionDraft later = NutritionTargetVersionDraft.CreateInGrams(
            Guid.NewGuid(), "Maintenance", NutritionGoalCategory.Maintenance,
            new DateOnly(2026, 9, 1), null, 2700m, 190m, 300m, 80m);
        NutritionTargetVersionDraft earlier = NutritionTargetVersionDraft.CreateInGrams(
            Guid.NewGuid(), "Sommer Cut", NutritionGoalCategory.Cut,
            new DateOnly(2026, 8, 1), new DateOnly(2026, 8, 31), 2500m, 180m, 260m, 80m);

        NutritionTargetScheduleDraft schedule = NutritionTargetScheduleDraft.Create([later, earlier]);

        Assert.AreSequenceEqual(new[] { earlier.TargetVersionId, later.TargetVersionId }, schedule.Versions.Select(item => item.TargetVersionId).ToArray());
        Assert.AreEqual(earlier.TargetVersionId, schedule.GetEffective(new DateOnly(2026, 8, 31))?.TargetVersionId);
        Assert.AreEqual(later.TargetVersionId, schedule.GetEffective(new DateOnly(2026, 9, 2))?.TargetVersionId);
        Assert.IsNull(schedule.GetEffective(new DateOnly(2026, 7, 31)));
    }

    [TestMethod]
    public void PercentageTargetDerivesCanonicalGramValuesWithFourFourNineRounding()
    {
        NutritionTargetVersionDraft target = NutritionTargetVersionDraft.CreateInPercent(
            Guid.NewGuid(), "Sommer Cut", NutritionGoalCategory.Cut,
            new DateOnly(2026, 8, 1), new DateOnly(2026, 10, 31),
            2000m, 30m, 40m, 30m);

        Assert.AreEqual(NutritionTargetInputMode.Percent, target.InputMode);
        Assert.AreEqual(150m, target.ProteinGrams);
        Assert.AreEqual(200m, target.CarbohydrateGrams);
        Assert.AreEqual(66.67m, target.FatGrams);
        Assert.AreEqual(30m, target.ProteinPercent);
        Assert.AreEqual(2000.03m, target.MacroEnergyKilocalories);
        Assert.IsFalse(target.RequiresEnergyMismatchConfirmation);
    }

    [TestMethod]
    public void TargetScheduleRejectsOverlapsAndAllowsGaps()
    {
        NutritionTargetVersionDraft august = NutritionTargetVersionDraft.CreateInGrams(
            Guid.NewGuid(), "Cut", NutritionGoalCategory.Cut,
            new DateOnly(2026, 8, 1), new DateOnly(2026, 8, 31), 2500m, 180m, 260m, 80m);
        NutritionTargetVersionDraft overlapping = NutritionTargetVersionDraft.CreateInGrams(
            Guid.NewGuid(), "Maintenance", NutritionGoalCategory.Maintenance,
            new DateOnly(2026, 8, 31), null, 2700m, 190m, 300m, 80m);

        NutritionValidationException conflict = Assert.Throws<NutritionValidationException>(() =>
            NutritionTargetScheduleDraft.Create([august, overlapping]));
        Assert.IsTrue(conflict.Errors.ContainsKey("Versions"));

        NutritionTargetVersionDraft september = overlapping with { EffectiveFrom = new DateOnly(2026, 9, 2) };
        NutritionTargetScheduleDraft schedule = NutritionTargetScheduleDraft.Create([august, september]);
        Assert.IsNull(schedule.GetEffective(new DateOnly(2026, 9, 1)));
    }

    [TestMethod]
    public void PercentageTargetsRequirePositiveDistributionThatTotalsOneHundred()
    {
        NutritionValidationException invalid = Assert.Throws<NutritionValidationException>(() =>
            NutritionTargetVersionDraft.CreateInPercent(
                Guid.NewGuid(), "Cut", NutritionGoalCategory.Cut,
                new DateOnly(2026, 8, 1), null, 2000m, 30m, 35m, 30m));

        Assert.IsTrue(invalid.Errors.ContainsKey("MacroDistribution"));
    }

    [TestMethod]
    public void TargetVersionsRejectAutomatedOriginsAndMetadata()
    {
        NutritionValidationException automated = Assert.Throws<NutritionValidationException>(() =>
            NutritionTargetVersionDraft.Create(
                Guid.NewGuid(), new DateOnly(2026, 8, 1), 2500m, 180m, 260m, 80m,
                (NutritionTargetOrigin)2, "policy-v1", "Automated suggestion"));

        Assert.IsTrue(automated.Errors.ContainsKey("Origin"));
        Assert.IsTrue(automated.Errors.ContainsKey("AlgorithmVersion"));
        Assert.IsTrue(automated.Errors.ContainsKey("Reason"));
    }

    [TestMethod]
    public void TargetScheduleRejectsDuplicateEffectiveDatesAndOutOfRangeValues()
    {
        NutritionTargetVersionDraft version = NutritionTargetVersionDraft.Create(
            Guid.NewGuid(), new DateOnly(2026, 8, 1), 2500m, 180m, 260m, 80m,
            NutritionTargetOrigin.Manual, null, null);

        NutritionValidationException duplicate = Assert.Throws<NutritionValidationException>(() =>
            NutritionTargetScheduleDraft.Create([version, version with { TargetVersionId = Guid.NewGuid() }]));
        Assert.IsTrue(duplicate.Errors.ContainsKey("Versions"));

        NutritionValidationException tooHigh = Assert.Throws<NutritionValidationException>(() =>
            NutritionTargetVersionDraft.Create(
                Guid.NewGuid(), new DateOnly(2026, 8, 1), NutritionLimits.MaxDailyKilocalories + 1m,
                180m, 260m, 80m, NutritionTargetOrigin.Manual, null, null));
        Assert.IsTrue(tooHigh.Errors.ContainsKey("Kilocalories"));

        NutritionValidationException empty = Assert.Throws<NutritionValidationException>(() =>
            NutritionTargetScheduleDraft.Create([]));
        Assert.IsTrue(empty.Errors.ContainsKey("Versions"));

        NutritionValidationException invalidRange = Assert.Throws<NutritionValidationException>(() =>
            NutritionTargetVersionDraft.CreateInGrams(
                Guid.NewGuid(), "Cut", NutritionGoalCategory.Cut,
                new DateOnly(2026, 9, 1), new DateOnly(2026, 8, 31),
                2500m, 180m, 260m, 80m));
        Assert.IsTrue(invalidRange.Errors.ContainsKey("EffectiveUntil"));
    }

    [TestMethod]
    public void MealEstimateDraftPreservesMissingMacrosAndUncertainty()
    {
        MealEstimateComponentDraft component = MealEstimateComponentDraft.Create(
            "Sauce", 50m, 120m, null, 8m, null,
            MealEstimateConfidence.Low, ["fat could not be estimated"]);

        MealEstimateDraft draft = MealEstimateDraft.Create(
            [component], "openai", "schema-v1", DateTime.UnixEpoch);

        Assert.HasCount(1, draft.Components);
        Assert.IsNull(draft.Components[0].ProteinGrams);
        Assert.IsNull(draft.Components[0].FatGrams);
        Assert.AreEqual(MealEstimateConfidence.Low, draft.Components[0].Confidence);
        Assert.Contains("fat could not be estimated", draft.Components[0].DataGaps.ToArray());
    }

    [TestMethod]
    public void MealEstimateDraftRejectsEmptyOrOversizedResults()
    {
        NutritionValidationException empty = Assert.Throws<NutritionValidationException>(() =>
            MealEstimateDraft.Create([], "openai", "schema-v1", DateTime.UnixEpoch));
        Assert.IsTrue(empty.Errors.ContainsKey("Components"));

        MealEstimateComponentDraft component = MealEstimateComponentDraft.Create(
            "Food", 100m, 100m, null, null, null, MealEstimateConfidence.Medium, []);
        NutritionValidationException oversized = Assert.Throws<NutritionValidationException>(() =>
            MealEstimateDraft.Create(
                Enumerable.Repeat(component, NutritionLimits.MaxEstimateComponents + 1),
                "openai", "schema-v1", DateTime.UnixEpoch));
        Assert.IsTrue(oversized.Errors.ContainsKey("Components"));
    }

    [TestMethod]
    public void BoundaryLimitsAcceptMaximumsAndRejectValuesBeyondThem()
    {
        string maxName = new('x', NutritionLimits.MaxReusableMealNameLength);
        ReusableMealComponentDraft component = ReusableMealComponentDraft.Create(
            Guid.NewGuid(), 0, "Food", NutritionLimits.MaxAmountGrams,
            new NutritionPer100Grams(NutritionLimits.MaxKilocaloriesPer100Grams, null, null, null));

        ReusableMealDraft valid = ReusableMealDraft.Create(maxName, null, NutritionLimits.MaxPortionFactor, [component]);
        Assert.AreEqual(maxName, valid.Name);

        NutritionValidationException invalid = Assert.Throws<NutritionValidationException>(() =>
            ReusableMealDraft.Create(maxName + "x", null, NutritionLimits.MaxPortionFactor + 0.01m, [component]));
        CollectionAssert.IsSubsetOf(ExpectedPortionErrorFields, invalid.Errors.Keys.ToArray());
    }
}
