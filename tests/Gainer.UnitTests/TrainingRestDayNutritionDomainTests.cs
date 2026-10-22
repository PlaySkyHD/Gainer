using Gainer.Core.Mutations;
using Gainer.Core.Nutrition;

namespace Gainer.UnitTests;

[TestClass]
public sealed class TrainingRestDayNutritionDomainTests
{
    [TestMethod]
    public void CompleteRestDayTargetIsKeptOnTheVersion()
    {
        NutritionRestDayTargetDraft rest = NutritionRestDayTargetDraft.Create(
            NutritionTargetInputMode.Grams, 2200m, 180m, 190m, 80m, null, null, null);
        NutritionTargetVersionDraft version = NutritionTargetVersionDraft.Restore(
            Guid.NewGuid(), "Ziele", NutritionGoalCategory.Custom, new DateOnly(2026, 10, 22), null,
            2600m, NutritionTargetInputMode.Grams, 180m, 290m, 80m, null, null, null,
            NutritionTargetOrigin.Manual, null, null, restDay: rest);

        Assert.AreEqual(2200m, version.RestDay?.Kilocalories);
        Assert.AreEqual(2200m, rest.MacroEnergyKilocalories);
        Assert.IsFalse(rest.RequiresEnergyMismatchConfirmation);
    }

    [TestMethod]
    public void PercentRestDayTargetMustMatchItsDerivedGrams()
    {
        NutritionTotals derived = NutritionCalculator.CalculateMacroTargetsFromPercent(2200m, 30m, 40m, 30m);
        NutritionRestDayTargetDraft rest = NutritionRestDayTargetDraft.Create(
            NutritionTargetInputMode.Percent, 2200m, derived.ProteinGrams!.Value, derived.CarbohydrateGrams!.Value,
            derived.FatGrams!.Value, 30m, 40m, 30m);
        Assert.AreEqual(NutritionTargetInputMode.Percent, rest.InputMode);

        NutritionValidationException error = Assert.Throws<NutritionValidationException>(() =>
            NutritionRestDayTargetDraft.Create(
                NutritionTargetInputMode.Percent, 2200m, derived.ProteinGrams.Value, derived.CarbohydrateGrams.Value,
                derived.FatGrams.Value, 30m, 40m, 20m));
        Assert.IsTrue(error.Errors.Keys.All(key => key.StartsWith("RestDay.", StringComparison.Ordinal)));
    }

    [TestMethod]
    public void IncompleteRestDayTargetIsRejected()
    {
        NutritionValidationException error = Assert.Throws<NutritionValidationException>(() =>
            NutritionRestDayTargetDraft.Create(NutritionTargetInputMode.Grams, 2200m, 180m, 190m, 0m, null, null, null));
        Assert.IsTrue(error.Errors.ContainsKey("RestDay.FatGrams"));
    }

    [TestMethod]
    public void RestDayEnergyMismatchIsFlagged()
    {
        NutritionRestDayTargetDraft rest = NutritionRestDayTargetDraft.Create(
            NutritionTargetInputMode.Grams, 2200m, 180m, 300m, 80m, null, null, null);
        Assert.IsTrue(rest.RequiresEnergyMismatchConfirmation);
    }

    [TestMethod]
    public void VersionWithoutRestDayTargetIsUnchanged()
    {
        NutritionTargetVersionDraft version = NutritionTargetVersionDraft.CreateInGrams(
            Guid.NewGuid(), "Ziele", NutritionGoalCategory.Custom, new DateOnly(2026, 10, 22), null, 2600m, 180m, 290m, 80m);
        Assert.IsNull(version.RestDay);
    }

    [TestMethod]
    public void UnknownDayKindIsRejected()
    {
        NutritionValidationException error = Assert.Throws<NutritionValidationException>(() =>
            SaveNutritionDayMutation.Create(Metadata(), Guid.NewGuid(), new DateOnly(2026, 10, 22), 0, [], (NutritionDayKind)99));
        Assert.IsTrue(error.Errors.ContainsKey("DayKind"));

        SaveNutritionDayMutation rest = SaveNutritionDayMutation.Create(
            Metadata(), Guid.NewGuid(), new DateOnly(2026, 10, 22), 0, [], NutritionDayKind.Rest);
        Assert.AreEqual(NutritionDayKind.Rest, rest.DayKind);
    }

    private static MutationMetadata Metadata() => MutationMetadata.Create(Guid.NewGuid(), Guid.NewGuid(), 1);
}
