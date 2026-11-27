using Gainer.Core.Nutrition;

namespace Gainer.UnitTests;

/// <summary>The target of a day follows the app's dayTarget (day_target.dart).</summary>
[TestClass]
public sealed class DayTargetTests
{
    private static readonly NutritionTargetVersionDraft WithRestDay = Version(new NutritionRestDayTargetDraft(
        NutritionTargetInputMode.Grams, 1800m, 140m, 150m, 70m, null, null, null, 1790m, false));

    private static readonly NutritionTargetVersionDraft WithoutRestDay = Version(null);

    [TestMethod]
    public void WithoutRestDayTargetTheVersionAppliesAndTheDayKindIsIrrelevant()
    {
        DayTargetValues target = DayTarget.On(WithoutRestDay, NutritionDayKind.Rest, () => throw new AssertFailedException("not asked"));

        Assert.AreEqual(new DayTargetValues(null, false, 2000m, 150m, 200m, 70m), target);
    }

    [TestMethod]
    public void AutomaticRestDayTakesTheRestDayTarget() =>
        Assert.AreEqual(
            new DayTargetValues(NutritionDayKind.Rest, false, 1800m, 140m, 150m, 70m),
            DayTarget.On(WithRestDay, null, () => NutritionDayKind.Rest));

    [TestMethod]
    public void ChosenKindWinsOverTheAutomaticOne() =>
        Assert.AreEqual(
            new DayTargetValues(NutritionDayKind.Training, true, 2000m, 150m, 200m, 70m),
            DayTarget.On(WithRestDay, NutritionDayKind.Training, () => NutritionDayKind.Rest));

    private static NutritionTargetVersionDraft Version(NutritionRestDayTargetDraft? restDay) => new(
        Guid.Empty, "Ziel", NutritionGoalCategory.Custom, new DateOnly(2026, 10, 1), null, 2000m, NutritionTargetInputMode.Grams,
        150m, 200m, 70m, null, null, null, NutritionTargetOrigin.Manual, null, null, 2030m, false, RestDay: restDay);
}
