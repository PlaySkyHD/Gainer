using Gainer.Core.Insights;

namespace Gainer.UnitTests;

[TestClass]
public sealed class InsightAlgorithmTests
{
    [TestMethod]
    public void WeightGoldenVectorReportsCoverageAverageAndWeeklyOlsTrend()
    {
        WeightInsights result = InsightAlgorithms.Weight([
            new(new DateOnly(2026, 8, 1), 80m),
            new(new DateOnly(2026, 8, 2), 80.2m),
            new(new DateOnly(2026, 8, 4), 80.6m),
        ], new DateOnly(2026, 8, 1), new DateOnly(2026, 8, 7));
        Assert.AreEqual("weight-average-v1", result.AverageAlgorithmVersion);
        Assert.AreEqual(3, result.ObservedDays);
        Assert.AreEqual(0.4286m, result.Coverage);
        Assert.AreEqual(80.27m, result.AverageKg);
        Assert.AreEqual(1.40m, result.TrendKgPerWeek);
    }

    [TestMethod]
    public void FewerThanThreeWeightsAndMissingNutritionRemainExplicit()
    {
        WeightInsights weight = InsightAlgorithms.Weight([
            new(new DateOnly(2026, 8, 1), 80m),
            new(new DateOnly(2026, 8, 7), 81m),
        ], new DateOnly(2026, 8, 1), new DateOnly(2026, 8, 7));
        Assert.IsNull(weight.TrendKgPerWeek);
        NutritionInsights nutrition = InsightAlgorithms.Nutrition([
            new(new DateOnly(2026, 8, 1), 2500m, 180m, null, null),
            new(new DateOnly(2026, 8, 3), null, 160m, null, null),
        ], new DateOnly(2026, 8, 1), new DateOnly(2026, 8, 3));
        Assert.AreEqual(0.6667m, nutrition.Coverage);
        Assert.AreEqual(2500m, nutrition.CaloriesKcal.Value);
        Assert.AreEqual(1, nutrition.CaloriesKcal.ObservedDays);
        Assert.AreEqual(170m, nutrition.ProteinGrams.Value);
        Assert.IsNull(nutrition.FatGrams.Value);
    }

    [TestMethod]
    public void TrainingAggregatesRecordedSetsWithVersionedEpleyEstimate()
    {
        Guid workout = Guid.NewGuid();
        Guid exercise = Guid.NewGuid();
        DateTime completed = new(2026, 8, 18, 12, 0, 0, DateTimeKind.Utc);
        BlockStatistics block = new(workout, completed, Guid.NewGuid(), exercise, [
            new RecordedSet(100m, 10),
            new RecordedSet(90m, 13),
            new RecordedSet(0m, 8),
        ], null, false);
        TrainingInsights result = InsightAlgorithms.Training([block], 1);
        Assert.AreEqual("training-volume-v2", result.VolumeAlgorithmVersion);
        Assert.AreEqual("e1rm-epley-v2", result.EstimatedOneRepMaxAlgorithmVersion);
        Assert.AreEqual(2170m, result.VolumeKgRepetitions);
        Assert.AreEqual(133.33m, TrainingStatistics.RoundForOutput(result.BestSet!.EstimatedOneRepMaxKg));
        Assert.AreEqual(1, result.WorkoutCount);
        Assert.IsFalse(result.BodyweightMissing);
    }
}
