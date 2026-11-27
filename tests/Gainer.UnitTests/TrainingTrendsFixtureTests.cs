using System.Text.Json;
using Gainer.Core.Insights;
using Gainer.Core.Training;
using static Gainer.UnitTests.ContractFixture;

namespace Gainer.UnitTests;

/// <summary>The trend tiles compute as in the app (contracts/fixtures/training-trends.json).</summary>
[TestClass]
public sealed class TrainingTrendsFixtureTests
{
    private const string FileName = "training-trends.json";

    public static IEnumerable<object[]> Names => CaseNames(FileName);

    [TestMethod]
    [DynamicData(nameof(Names))]
    public void FixtureCaseMatchesCalculation(string caseName)
    {
        JsonElement fixtureCase = Case(FileName, caseName);
        var ids = new FixtureNames();
        TimeZoneInfo timeZone = TimeZoneInfo.FindSystemTimeZoneById(fixtureCase.GetProperty("timeZone").GetString()!);
        CheckInWeight[] checkIns = fixtureCase.GetProperty("checkIns").EnumerateArray()
            .Select(item => new CheckInWeight(Date(item.GetProperty("localDate")), item.GetProperty("weightKg").GetDecimal()))
            .ToArray();
        Dictionary<Guid, ExerciseFactorInput> factors = fixtureCase.GetProperty("exercises").EnumerateArray()
            .Select(item => new ExerciseFactorInput(
                ids.Of(item.GetProperty("id")), OptionalDecimal(item, "bodyweightFactor"), OptionalDecimal(item, "weightFactor")))
            .ToDictionary(item => item.ExerciseId);
        TrainingWorkoutInput[] workouts = fixtureCase.GetProperty("workouts").EnumerateArray()
            .Select(item => ToWorkout(item, ids))
            .ToArray();

        IReadOnlyList<WorkoutTrendEntry> entries = TrainingTrends.Entries(
            workouts, checkIns, factors, timeZone, fixtureCase.GetProperty("includeWarmups").GetBoolean());
        TrainingTrendsSnapshot trends = TrainingTrends.Compute(
            entries.ToArray(), checkIns, ParsePeriod(fixtureCase.GetProperty("period").GetString()!),
            Date(fixtureCase.GetProperty("today")));

        JsonElement expected = fixtureCase.GetProperty("expected");
        Assert.AreEqual(Date(expected.GetProperty("start")), trends.Start);
        Assert.AreSequenceEqual(
            expected.GetProperty("bucketStarts").EnumerateArray().Select(Date).ToArray(),
            trends.Buckets.Select(bucket => bucket.Start).ToArray());
        Assert.AreEqual(expected.GetProperty("workoutCount").GetInt32(), trends.WorkoutCount);
        AssertRounded("workoutsPerWeek", expected.GetProperty("workoutsPerWeek"), trends.WorkoutsPerWeek);
        AssertOptionalInt("averageDurationSeconds", expected.GetProperty("averageDurationSeconds"),
            trends.AverageDuration is { } average ? (int)average.TotalSeconds : null);
        Assert.AreEqual(expected.GetProperty("totalDurationSeconds").GetInt32(), (int)trends.TotalDuration.TotalSeconds);
        AssertRounded("volumeKg", expected.GetProperty("volumeKg"), trends.VolumeKg);
        Assert.AreEqual(expected.GetProperty("setCount").GetInt32(), trends.SetCount);
        Assert.AreEqual(expected.GetProperty("repetitions").GetInt32(), trends.Repetitions);
        AssertRounded("repetitionsPerSet", expected.GetProperty("repetitionsPerSet"), trends.RepetitionsPerSet);
        AssertRounded("latestBodyweightKg", expected.GetProperty("latestBodyweightKg"), trends.LatestBodyweightKg);

        JsonElement series = expected.GetProperty("series");
        AssertSeries(series, "workoutsPerWeek", trends, bucket => bucket.Workouts);
        AssertSeries(series, "averageDuration", trends, bucket => bucket.AverageMinutes);
        AssertSeries(series, "totalDuration", trends, bucket => bucket.TotalMinutes);
        AssertSeries(series, "volume", trends, bucket => bucket.VolumeKg);
        AssertSeries(series, "sets", trends, bucket => bucket.Sets);
        AssertSeries(series, "repetitions", trends, bucket => bucket.Repetitions);
        AssertSeries(series, "repetitionsPerSet", trends, bucket => bucket.RepetitionsPerSet);
        AssertSeries(series, "bodyweight", trends, bucket => bucket.BodyweightKg);
    }

    [TestMethod]
    public void EveryPeriodOfTheAppIsCovered()
    {
        string[] periods = CaseNames(FileName)
            .Select(name => Case(FileName, (string)name[0]).GetProperty("period").GetString()!)
            .Distinct()
            .ToArray();
        foreach (TrendPeriod period in Enum.GetValues<TrendPeriod>())
        {
            Assert.Contains(period, periods.Select(ParsePeriod).ToArray());
        }
    }

    private static void AssertSeries(JsonElement series, string metric, TrainingTrendsSnapshot trends, Func<TrendBucket, decimal?> select)
    {
        JsonElement[] values = series.GetProperty(metric).EnumerateArray().ToArray();
        Assert.HasCount(values.Length, trends.Buckets, metric);
        for (int i = 0; i < values.Length; i++)
        {
            AssertRounded($"{metric}[{i}]", values[i], select(trends.Buckets[i]));
        }
    }

    private static TrendPeriod ParsePeriod(string value) => value switch
    {
        "fourWeeks" => TrendPeriod.FourWeeks,
        "threeMonths" => TrendPeriod.ThreeMonths,
        "year" => TrendPeriod.Year,
        "all" => TrendPeriod.All,
        _ => throw new ArgumentOutOfRangeException(nameof(value), value, "Unknown period."),
    };

    private static TrainingWorkoutInput ToWorkout(JsonElement item, FixtureNames ids) => new(
        ids.Of(item.GetProperty("workoutId")),
        Utc(item.GetProperty("startedAtUtc")),
        OptionalUtc(item, "endedAtUtc"),
        OptionalUtc(item, "deletedAtUtc"),
        item.GetProperty("exercises").EnumerateArray()
            .Select(block => new TrainingBlockInput(
                ids.Of(block.GetProperty("workoutExerciseId")),
                ids.Of(block.GetProperty("sourceExerciseId")),
                ExerciseTypes.Parse(block.GetProperty("exerciseTypeSnapshot").GetString()),
                block.GetProperty("sets").EnumerateArray().Select(ToSet).ToArray()))
            .ToArray());

    internal static TrainingSetInput ToSet(JsonElement set) => new(
        WorkoutSetTypes.ParseOrNormal(set.GetProperty("setType").GetString()),
        OptionalDecimal(set, "weightKg"),
        OptionalInt(set, "repetitions"));
}
