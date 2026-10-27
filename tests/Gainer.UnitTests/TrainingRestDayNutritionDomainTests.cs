using Gainer.Core.Mutations;
using Gainer.Core.Nutrition;

namespace Gainer.UnitTests;

[TestClass]
public sealed class TrainingRestDayNutritionDomainTests
{
    [TestMethod]
    public void CompleteRestDayTargetIsKeptOnTheVersion()
    {
        NutritionRestDayTargetDraft rest = NutritionRestDayTargetDraft.Create(NutritionTargetInputMode.Grams, new NutritionMacroTargets(2200m, 180m, 190m, 80m));
        NutritionTargetVersionDraft version = NutritionTargetVersionDraft.Restore(new NutritionTargetPhase(Guid.NewGuid(), "Ziele", NutritionGoalCategory.Custom, new DateOnly(2026, 10, 22)), NutritionTargetInputMode.Grams, new NutritionMacroTargets(2600m, 180m, 290m, 80m), new NutritionTargetOptions(NutritionTargetOrigin.Manual, null, null), rest);

        Assert.AreEqual(2200m, version.RestDay?.Kilocalories);
        Assert.AreEqual(2200m, rest.MacroEnergyKilocalories);
        Assert.IsFalse(rest.RequiresEnergyMismatchConfirmation);
    }

    [TestMethod]
    public void PercentRestDayTargetMustMatchItsDerivedGrams()
    {
        NutritionTotals derived = NutritionCalculator.CalculateMacroTargetsFromPercent(2200m, 30m, 40m, 30m);
        NutritionRestDayTargetDraft rest = NutritionRestDayTargetDraft.Create(NutritionTargetInputMode.Percent, new NutritionMacroTargets(2200m, derived.ProteinGrams!.Value, derived.CarbohydrateGrams!.Value, derived.FatGrams!.Value, 30m, 40m, 30m));
        Assert.AreEqual(NutritionTargetInputMode.Percent, rest.InputMode);

        NutritionValidationException error = Assert.Throws<NutritionValidationException>(() =>
            NutritionRestDayTargetDraft.Create(NutritionTargetInputMode.Percent, new NutritionMacroTargets(2200m, derived.ProteinGrams.Value, derived.CarbohydrateGrams.Value, derived.FatGrams.Value, 30m, 40m, 20m)));
        Assert.IsTrue(error.Errors.Keys.All(key => key.StartsWith("RestDay.", StringComparison.Ordinal)));
    }

    [TestMethod]
    public void IncompleteRestDayTargetIsRejected()
    {
        NutritionValidationException error = Assert.Throws<NutritionValidationException>(() =>
            NutritionRestDayTargetDraft.Create(NutritionTargetInputMode.Grams, new NutritionMacroTargets(2200m, 180m, 190m, 0m)));
        Assert.IsTrue(error.Errors.ContainsKey("RestDay.FatGrams"));
    }

    [TestMethod]
    public void RestDayEnergyMismatchIsFlagged()
    {
        NutritionRestDayTargetDraft rest = NutritionRestDayTargetDraft.Create(NutritionTargetInputMode.Grams, new NutritionMacroTargets(2200m, 180m, 300m, 80m));
        Assert.IsTrue(rest.RequiresEnergyMismatchConfirmation);
    }

    [TestMethod]
    public void VersionWithoutRestDayTargetIsUnchanged()
    {
        NutritionTargetVersionDraft version = NutritionTargetVersionDraft.CreateInGrams(new NutritionTargetPhase(Guid.NewGuid(), "Ziele", NutritionGoalCategory.Custom, new DateOnly(2026, 10, 22)), new NutritionMacroTargets(2600m, 180m, 290m, 80m));
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
