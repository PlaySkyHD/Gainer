using System.Text.Json;
using Gainer.Core.Nutrition;
using static Gainer.UnitTests.ContractFixture;

namespace Gainer.UnitTests;

/// <summary>The nutrition averages compute as in the app (contracts/fixtures/nutrition-averages.json).</summary>
[TestClass]
public sealed class NutritionAveragesFixtureTests
{
    private const string FileName = "nutrition-averages.json";
    private static readonly string[] AverageNames =
    [
        "averageKilocalories", "averageProteinGrams", "averageCarbohydrateGrams", "averageFatGrams",
        "averageFiberGrams", "averageSaltGrams", "averageTargetKilocalories",
    ];

    public static IEnumerable<object[]> Names => CaseNames(FileName);

    [TestMethod]
    [DynamicData(nameof(Names))]
    public void FixtureCaseMatchesCalculation(string caseName)
    {
        JsonElement item = Case(FileName, caseName);
        NutritionAveragesSnapshot result = NutritionAverages.Compute(
            item.GetProperty("days").EnumerateArray().Select(ToDay).ToArray(),
            item.GetProperty("targets").EnumerateArray()
                .Select(target => new NutritionAverageTargetInput(
                    Date(target.GetProperty("effectiveFrom")),
                    target.GetProperty("effectiveUntil").ValueKind == JsonValueKind.Null
                        ? null
                        : Date(target.GetProperty("effectiveUntil")),
                    target.GetProperty("kilocalories").GetDecimal(),
                    OptionalDecimal(target, "restDayKilocalories")))
                .ToArray(),
            Date(item.GetProperty("today")),
            item.GetProperty("windowDays").GetInt32());

        JsonElement expected = item.GetProperty("expected");
        Assert.AreEqual(Date(expected.GetProperty("from")), result.From);
        Assert.AreEqual(Date(expected.GetProperty("through")), result.Through);
        Assert.AreEqual(expected.GetProperty("includesToday").GetBoolean(), result.IncludesToday);
        Assert.AreEqual(expected.GetProperty("loggedDays").GetInt32(), result.LoggedDays);
        decimal?[] averages =
        [
            result.AverageKilocalories, result.AverageProteinGrams, result.AverageCarbohydrateGrams, result.AverageFatGrams,
            result.AverageFiberGrams, result.AverageSaltGrams, result.AverageTargetKilocalories,
        ];
        for (int i = 0; i < AverageNames.Length; i++)
        {
            AssertRounded(AverageNames[i], expected.GetProperty(AverageNames[i]), averages[i]);
        }
        Assert.AreEqual(expected.GetProperty("daysWithinTarget").GetInt32(), result.DaysWithinTarget);
        Assert.AreEqual(expected.GetProperty("daysWithTarget").GetInt32(), result.DaysWithTarget);

        JsonElement[] days = expected.GetProperty("days").EnumerateArray().ToArray();
        Assert.HasCount(days.Length, result.Days);
        for (int i = 0; i < days.Length; i++)
        {
            NutritionAverageDay day = result.Days[i];
            string label = day.Date.ToString("yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture);
            Assert.AreEqual(Date(days[i].GetProperty("localDate")), day.Date);
            AssertRounded(label, days[i].GetProperty("kilocalories"), day.Kilocalories);
            AssertRounded($"{label} target", days[i].GetProperty("targetKilocalories"), day.TargetKilocalories);
            Assert.AreEqual(days[i].GetProperty("withinTarget").GetBoolean(), day.WithinTarget, label);
        }
    }

    [TestMethod]
    public void WindowNeedsAtLeastOneDay() =>
        Assert.ThrowsExactly<ArgumentOutOfRangeException>(() => NutritionAverages.Compute([], [], new DateOnly(2026, 10, 19), 0));

    private static NutritionAverageDayInput ToDay(JsonElement day)
    {
        NutritionDayKind? kind = day.TryGetProperty("dayKind", out JsonElement value)
            ? value.GetString() == "rest" ? NutritionDayKind.Rest : NutritionDayKind.Training
            : null;
        NutritionTotals? totals = day.TryGetProperty("totals", out JsonElement sums)
            ? new NutritionTotals(
                sums.GetProperty("kilocalories").GetDecimal(),
                OptionalDecimal(sums, "proteinGrams"),
                OptionalDecimal(sums, "carbohydrateGrams"),
                OptionalDecimal(sums, "fatGrams"),
                OptionalDecimal(sums, "saltGrams"),
                OptionalDecimal(sums, "fiberGrams"))
            : null;
        return new NutritionAverageDayInput(Date(day.GetProperty("localDate")), totals, kind);
    }
}
