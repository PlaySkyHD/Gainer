using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;
using Gainer.Core.Insights;
using Gainer.Core.Training;
using static Gainer.UnitTests.ContractFixture;

namespace Gainer.UnitTests;

/// <summary>The training analysis computes as in the app (contracts/fixtures/training-analysis.json).</summary>
[TestClass]
public sealed class TrainingAnalysisFixtureTests
{
    private const string FileName = "training-analysis.json";

    public static IEnumerable<object[]> Names => CaseNames(FileName);

    [TestMethod]
    [DynamicData(nameof(Names))]
    public void FixtureCaseMatchesCalculation(string caseName)
    {
        JsonElement fixtureCase = Case(FileName, caseName);
        var ids = new FixtureNames();
        TrainingAnalysisSnapshot analysis = Compute(fixtureCase, ids);

        JsonObject actual = ToJson(analysis, ids);
        AssertMatches("expected", fixtureCase.GetProperty("expected"), actual);
    }

    [TestMethod]
    public void EveryStatusSignalAndRecommendationIsCovered()
    {
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (object[] name in CaseNames(FileName))
        {
            foreach (JsonElement exercise in Case(FileName, (string)name[0]).GetProperty("expected").GetProperty("exercises").EnumerateArray())
            {
                seen.Add(exercise.GetProperty("status").GetString()!);
                seen.Add(exercise.GetProperty("recommendation").GetProperty("kind").GetString()!);
                foreach (JsonElement signal in exercise.GetProperty("fatigueSignals").EnumerateArray())
                {
                    seen.Add(signal.GetProperty("kind").GetString()!);
                }
            }
        }

        foreach (string value in Enum.GetNames<ExerciseProgressStatus>()
                     .Concat(Enum.GetNames<FatigueSignalKind>())
                     .Concat(Enum.GetNames<RecommendationKind>()))
        {
            Assert.Contains(Camel(value), seen);
        }
    }

    [TestMethod]
    public void TheUnboundedPeriodIsRejected()
    {
        Assert.ThrowsExactly<ArgumentOutOfRangeException>(() => TrainingAnalysis.Compute(
            [], [], new Dictionary<Guid, ExerciseFactorInput>(), LocalDays.Default, TrendPeriod.All, new DateOnly(2026, 11, 25)));
    }

    [TestMethod]
    public void NumbersAreFormattedGerman()
    {
        Assert.AreEqual("1.002,5", TrainingAnalysis.FormatNumber(1002.5m));
        Assert.AreEqual("92,5", TrainingAnalysis.FormatNumber(92.50m));
        Assert.AreEqual("81,26", TrainingAnalysis.FormatNumber(81.255m));
        Assert.AreEqual("120", TrainingAnalysis.FormatNumber(120.00m));
    }

    private static TrainingAnalysisSnapshot Compute(JsonElement fixtureCase, FixtureNames ids)
    {
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
        TrendPeriod period = Enum.Parse<TrendPeriod>(fixtureCase.GetProperty("period").GetString()!, ignoreCase: true);
        return TrainingAnalysis.Compute(workouts, checkIns, factors, timeZone, period, Date(fixtureCase.GetProperty("today")));
    }

    private static JsonObject ToJson(TrainingAnalysisSnapshot analysis, FixtureNames ids) => new()
    {
        ["start"] = Iso(analysis.Start),
        ["exercises"] = new JsonArray(analysis.Exercises.Select(item => (JsonNode)ExerciseJson(item, ids)).ToArray()),
        ["overall"] = new JsonObject
        {
            ["weeks"] = new JsonArray(analysis.Overall.Weeks.Select(week => (JsonNode)new JsonObject
            {
                ["start"] = Iso(week.Start),
                ["complete"] = week.Complete,
                ["volumeKg"] = Round(week.VolumeKg),
                ["workingSets"] = week.WorkingSets,
            }).ToArray()),
            ["weeklyVolumeChangePercent"] = Round(analysis.Overall.WeeklyVolumeChangePercent),
            ["exercisesWithFatigue"] = analysis.Overall.ExercisesWithFatigue,
            ["eligibleExercises"] = analysis.Overall.EligibleExercises,
            ["fatigued"] = analysis.Overall.Fatigued,
        },
    };

    private static JsonObject ExerciseJson(ExerciseAnalysis item, FixtureNames ids) => new()
    {
        ["exerciseId"] = ids.NameOf(item.ExerciseId),
        ["name"] = item.Name,
        ["exerciseType"] = ExerciseTypes.ToStorageValue(item.ExerciseType),
        ["status"] = Camel(item.Status.ToString()),
        ["sessions"] = new JsonArray(item.Sessions.Select(session => (JsonNode)new JsonObject
        {
            ["workoutId"] = ids.NameOf(session.WorkoutId),
            ["day"] = Iso(session.Day),
            ["workingSets"] = session.WorkingSets,
            ["volumeKg"] = Round(session.VolumeKg),
            ["estimatedOneRepMaxKg"] = Round(session.EstimatedOneRepMaxKg),
            ["topWeightKg"] = Round(session.TopWeightKg),
            ["topSetMinRepetitions"] = session.TopSetMinRepetitions,
            ["topSetMaxRepetitions"] = session.TopSetMaxRepetitions,
        }).ToArray()),
        ["bestEstimatedOneRepMaxKg"] = Round(item.BestEstimatedOneRepMaxKg),
        ["sessionsSinceBest"] = item.SessionsSinceBest,
        ["estimatedOneRepMaxFirstKg"] = Round(item.EstimatedOneRepMaxFirstKg),
        ["estimatedOneRepMaxLastKg"] = Round(item.EstimatedOneRepMaxLastKg),
        ["estimatedOneRepMaxChangePercent"] = Round(item.EstimatedOneRepMaxChangePercent),
        ["topWeightChangePercent"] = Round(item.TopWeightChangePercent),
        ["topRepetitionsChange"] = Round(item.TopRepetitionsChange),
        ["volumeChangePercent"] = Round(item.VolumeChangePercent),
        ["volumePerWeekKg"] = Round(item.VolumePerWeekKg),
        ["workingSetsPerWeek"] = Round(item.WorkingSetsPerWeek),
        ["fatigueSignals"] = new JsonArray(item.FatigueSignals.Select(signal => (JsonNode)new JsonObject
        {
            ["kind"] = Camel(signal.Kind.ToString()),
            ["sessions"] = signal.Sessions,
            ["fromRepetitions"] = signal.FromRepetitions,
            ["toRepetitions"] = signal.ToRepetitions,
            ["weightKg"] = Round(signal.WeightKg),
            ["zeroRirSets"] = signal.ZeroRirSets,
            ["ratedSets"] = signal.RatedSets,
            ["volumeChangePercent"] = Round(signal.VolumeChangePercent),
            ["estimatedOneRepMaxChangePercent"] = Round(signal.EstimatedOneRepMaxChangePercent),
        }).ToArray()),
        ["recommendation"] = new JsonObject
        {
            ["kind"] = Camel(item.Recommendation.Kind.ToString()),
            ["suggestedWeightKg"] = Round(item.Recommendation.SuggestedWeightKg),
            ["suggestedRepetitions"] = item.Recommendation.SuggestedRepetitions,
            ["repetitionRangeLow"] = item.Recommendation.RepetitionRangeLow,
            ["repetitionRangeHigh"] = item.Recommendation.RepetitionRangeHigh,
            ["weightStepKg"] = Round(item.Recommendation.WeightStepKg),
            ["text"] = item.Recommendation.Text,
        },
    };

    /// <summary>Every expected property must match the computed one and no computed property may be missing.</summary>
    private static void AssertMatches(string path, JsonElement expected, JsonNode? actual)
    {
        switch (expected.ValueKind)
        {
            case JsonValueKind.Object:
                JsonObject actualObject = actual!.AsObject();
                string[] expectedNames = expected.EnumerateObject().Select(item => item.Name).Order(StringComparer.Ordinal).ToArray();
                Assert.AreSequenceEqual(expectedNames, actualObject.Select(item => item.Key).Order(StringComparer.Ordinal).ToArray(), path);
                foreach (JsonProperty property in expected.EnumerateObject())
                {
                    AssertMatches($"{path}.{property.Name}", property.Value, actualObject[property.Name]);
                }
                break;
            case JsonValueKind.Array:
                JsonArray actualArray = actual!.AsArray();
                JsonElement[] items = expected.EnumerateArray().ToArray();
                Assert.HasCount(items.Length, actualArray, path);
                for (int i = 0; i < items.Length; i++) AssertMatches($"{path}[{i}]", items[i], actualArray[i]);
                break;
            case JsonValueKind.Number:
                Assert.AreEqual(expected.GetDecimal(), JsonSerializer.Deserialize<decimal>(actual!.ToJsonString()), path);
                break;
            case JsonValueKind.Null:
                Assert.IsNull(actual, path);
                break;
            case JsonValueKind.String:
                Assert.AreEqual(expected.GetString(), actual!.GetValue<string>(), path);
                break;
            default:
                Assert.AreEqual(expected.GetBoolean(), actual!.GetValue<bool>(), path);
                break;
        }
    }

    private static string Camel(string value) => JsonNamingPolicy.CamelCase.ConvertName(value);

    private static string Iso(DateOnly date) => date.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);

    private static decimal? Round(decimal? value) => TrainingStatistics.RoundForOutput(value);

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
                block.GetProperty("sets").EnumerateArray()
                    .Select(set => new TrainingSetInput(
                        WorkoutSetTypes.ParseOrNormal(set.GetProperty("setType").GetString()),
                        OptionalDecimal(set, "weightKg"),
                        OptionalInt(set, "repetitions"),
                        OptionalDecimal(set, "rir")))
                    .ToArray(),
                block.GetProperty("exerciseNameSnapshot").GetString()))
            .ToArray());
}
