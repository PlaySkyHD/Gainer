using System.Text.Json;
using Gainer.Core.Insights;
using static Gainer.UnitTests.ContractFixture;

namespace Gainer.UnitTests;

/// <summary>The training heatmap computes as in the app (contracts/fixtures/training-heatmap.json).</summary>
[TestClass]
public sealed class TrainingHeatmapFixtureTests
{
    private const string FileName = "training-heatmap.json";

    public static IEnumerable<object[]> Names => CaseNames(FileName);

    [TestMethod]
    [DynamicData(nameof(Names))]
    public void FixtureCaseMatchesCalculation(string caseName)
    {
        JsonElement fixtureCase = Case(FileName, caseName);
        TimeZoneInfo timeZone = TimeZoneInfo.FindSystemTimeZoneById(fixtureCase.GetProperty("timeZone").GetString()!);
        TrainingHeatmapSnapshot heatmap = TrainingHeatmap.Build(
            fixtureCase.GetProperty("sessions").EnumerateArray()
                .Select(item => new TrainingInterval(Utc(item.GetProperty("startedAtUtc")), Utc(item.GetProperty("endedAtUtc")))),
            Date(fixtureCase.GetProperty("today")),
            timeZone);

        JsonElement expected = fixtureCase.GetProperty("expected");
        Assert.AreEqual(Date(expected.GetProperty("start")), heatmap.Start);
        Assert.AreEqual(expected.GetProperty("weekCount").GetInt32(), heatmap.WeekCount);
        Assert.HasCount(expected.GetProperty("trainingDays").GetInt32(), heatmap.Days);
        Assert.AreSequenceEqual(
            expected.GetProperty("bounds").EnumerateArray().Select(item => item.GetDouble()).ToArray(),
            heatmap.Bounds.Select(bound => Math.Round(bound, 2)).ToArray());
        Assert.AreSequenceEqual(
            expected.GetProperty("days").EnumerateArray()
                .Select(item => new TrainingHeatmapDay(
                    Date(item.GetProperty("date")), item.GetProperty("minutes").GetInt32(), item.GetProperty("level").GetInt32()))
                .ToArray(),
            heatmap.Days.ToArray());
    }
}
