using System.Globalization;
using System.Text.Json;
using Gainer.Core.Insights;
using Gainer.Core.Training;

namespace Gainer.UnitTests;

/// <summary>
/// Prüft die Rechenregeln gegen die gemeinsame Fixture (D7). Jeder Fall der Datei ist ein eigener Testlauf;
/// die Datei wird über die Projektverlinkung in das Ausgabeverzeichnis kopiert.
/// </summary>
[TestClass]
public sealed class TrainingStatisticsFixtureTests
{
    [TestMethod]
    public void FixtureNamesTheImplementedAlgorithmVersions()
    {
        JsonElement versions = LoadFixture().GetProperty("algorithmVersions");
        Assert.AreEqual(InsightAlgorithmVersions.TrainingVolume, versions.GetProperty("volume").GetString());
        Assert.AreEqual(InsightAlgorithmVersions.EstimatedOneRepMax, versions.GetProperty("e1rm").GetString());
    }

    public static IEnumerable<object[]> CaseNames()
    {
        foreach (JsonElement item in LoadFixture().GetProperty("cases").EnumerateArray())
        {
            yield return [item.GetProperty("name").GetString()!];
        }
    }

    [TestMethod]
    [DynamicData(nameof(CaseNames))]
    public void FixtureCaseMatchesCalculation(string caseName)
    {
        JsonElement fixtureCase = LoadFixture().GetProperty("cases").EnumerateArray()
            .Single(item => item.GetProperty("name").GetString() == caseName);
        var ids = new FixtureIds();
        bool includeWarmups = fixtureCase.GetProperty("includeWarmups").GetBoolean();
        TimeZoneInfo timeZone = TimeZoneInfo.FindSystemTimeZoneById(fixtureCase.GetProperty("timeZone").GetString()!);
        CheckInWeight[] checkIns = fixtureCase.GetProperty("checkIns").EnumerateArray()
            .Select(item => new CheckInWeight(
                DateOnly.ParseExact(item.GetProperty("localDate").GetString()!, "yyyy-MM-dd", CultureInfo.InvariantCulture),
                item.GetProperty("weightKg").GetDecimal()))
            .ToArray();
        Dictionary<Guid, ExerciseFactorInput> factors = fixtureCase.GetProperty("exercises").EnumerateArray()
            .Select(item => new ExerciseFactorInput(
                ids.Of(item.GetProperty("id").GetString()!),
                OptionalDecimal(item, "bodyweightFactor"),
                OptionalDecimal(item, "weightFactor")))
            .ToDictionary(item => item.ExerciseId);
        List<TrainingWorkoutInput> workouts = fixtureCase.GetProperty("workouts").EnumerateArray()
            .Select(item => ToWorkout(item, ids))
            .ToList();

        JsonElement expected = fixtureCase.GetProperty("expected");
        if (expected.TryGetProperty("workouts", out JsonElement expectedWorkouts))
        {
            foreach (JsonElement expectedWorkout in expectedWorkouts.EnumerateArray())
            {
                string workoutName = expectedWorkout.GetProperty("workoutId").GetString()!;
                TrainingWorkoutInput workout = workouts.Single(item => item.WorkoutId == ids.Of(workoutName));
                IReadOnlyList<BlockStatistics> blocks = TrainingStatistics.WorkoutBlocks(
                    workout, checkIns, factors, timeZone, includeWarmups);
                foreach (JsonElement expectedBlock in expectedWorkout.GetProperty("exercises").EnumerateArray())
                {
                    string blockName = expectedBlock.GetProperty("workoutExerciseId").GetString()!;
                    BlockStatistics block = blocks.Single(item => item.WorkoutExerciseId == ids.Of(blockName));
                    AssertBlock($"{caseName}/{blockName}", expectedBlock, block);
                }
            }
        }

        if (expected.TryGetProperty("exercises", out JsonElement expectedExercises))
        {
            foreach (JsonElement expectedExercise in expectedExercises.EnumerateArray())
            {
                string exerciseName = expectedExercise.GetProperty("exerciseId").GetString()!;
                ExerciseRecords records = TrainingStatistics.History(
                    ids.Of(exerciseName), workouts, checkIns, factors, timeZone, includeWarmups).Records();
                string label = $"{caseName}/{exerciseName}";
                JsonElement expectedRecords = expectedExercise.GetProperty("records");
                AssertEvents($"{label} maxWeight", ids, expectedRecords.GetProperty("maxWeight"), records.MaxWeight);
                AssertEvents($"{label} estimatedOneRepMax", ids, expectedRecords.GetProperty("estimatedOneRepMax"), records.EstimatedOneRepMax);
                AssertEvents($"{label} volume", ids, expectedRecords.GetProperty("volume"), records.Volume);
                AssertEvents($"{label} maxRepetitions", ids, expectedRecords.GetProperty("maxRepetitions"), records.MaxRepetitions);
                JsonElement expectedRepRecords = expectedExercise.GetProperty("repRecords");
                foreach (RepetitionRecord record in records.RepetitionRecords)
                {
                    AssertRounded(
                        $"{label} repRecords {record.Repetitions}",
                        expectedRepRecords.GetProperty(record.Repetitions.ToString(CultureInfo.InvariantCulture)),
                        record.MaxWeightKg);
                }
            }
        }

        if (expected.TryGetProperty("summary", out JsonElement expectedSummary))
        {
            AssertSummary(caseName, expectedSummary, ids, workouts, checkIns, factors, timeZone, includeWarmups);
        }
    }

    private static void AssertBlock(string label, JsonElement expected, BlockStatistics block)
    {
        Assert.AreEqual(expected.GetProperty("setCount").GetInt32(), block.SetCount, $"{label} setCount");
        Assert.AreEqual(expected.GetProperty("totalRepetitions").GetInt32(), block.TotalRepetitions, $"{label} totalRepetitions");
        Assert.AreEqual(expected.GetProperty("maxRepetitions").GetInt32(), block.MaxRepetitions, $"{label} maxRepetitions");
        AssertRounded($"{label} volumeKg", expected.GetProperty("volumeKg"), block.VolumeKg);
        AssertRounded($"{label} maxWeightKg", expected.GetProperty("maxWeightKg"), block.MaxWeightKg);
        AssertRounded($"{label} averageWeightKg", expected.GetProperty("averageWeightKg"), block.AverageWeightKg);
        AssertRounded($"{label} estimatedOneRepMaxKg", expected.GetProperty("estimatedOneRepMaxKg"), block.EstimatedOneRepMaxKg);
        AssertRounded($"{label} bodyweightKg", expected.GetProperty("bodyweightKg"), block.BodyweightKg);
        Assert.AreEqual(expected.GetProperty("bodyweightMissing").GetBoolean(), block.BodyweightMissing, $"{label} bodyweightMissing");
    }

    private static void AssertEvents(string label, FixtureIds ids, JsonElement expected, IReadOnlyList<RecordEvent> actual)
    {
        JsonElement[] items = expected.EnumerateArray().ToArray();
        Assert.HasCount(items.Length, actual, $"{label} count");
        for (int i = 0; i < items.Length; i++)
        {
            Assert.AreEqual(items[i].GetProperty("workoutId").GetString(), ids.NameOf(actual[i].WorkoutId), $"{label}[{i}] workout");
            AssertRounded($"{label}[{i}] value", items[i].GetProperty("value"), actual[i].Value);
        }
    }

    private static void AssertSummary(
        string caseName,
        JsonElement expected,
        FixtureIds ids,
        IReadOnlyList<TrainingWorkoutInput> workouts,
        IReadOnlyCollection<CheckInWeight> checkIns,
        IReadOnlyDictionary<Guid, ExerciseFactorInput> factors,
        TimeZoneInfo timeZone,
        bool includeWarmups)
    {
        string label = $"{caseName} summary";
        TrainingWorkoutInput workout = workouts.Single(item => item.WorkoutId == ids.Of(expected.GetProperty("workoutId").GetString()!));
        TrainingSummary summary = TrainingStatistics.Summarize(workout, workouts, checkIns, factors, timeZone, includeWarmups);
        Assert.AreEqual(expected.GetProperty("durationSeconds").GetInt64(), (long)summary.Duration.TotalSeconds, $"{label} duration");
        Assert.AreEqual(expected.GetProperty("setCount").GetInt32(), summary.SetCount, $"{label} setCount");
        Assert.AreEqual(expected.GetProperty("totalRepetitions").GetInt32(), summary.TotalRepetitions, $"{label} totalRepetitions");
        AssertRounded($"{label} volumeKg", expected.GetProperty("volumeKg"), summary.VolumeKg);

        JsonElement[] expectedBestSets = expected.GetProperty("bestSets").EnumerateArray().ToArray();
        Assert.HasCount(expectedBestSets.Length, summary.BestSets, $"{label} bestSets count");
        for (int i = 0; i < expectedBestSets.Length; i++)
        {
            JsonElement item = expectedBestSets[i];
            BestSet best = summary.BestSets[i];
            Assert.AreEqual(item.GetProperty("exerciseId").GetString(), ids.NameOf(best.ExerciseId), $"{label} bestSet[{i}] exercise");
            AssertRounded($"{label} bestSet[{i}] weightKg", item.GetProperty("weightKg"), best.EffectiveWeightKg);
            Assert.AreEqual(item.GetProperty("repetitions").GetInt32(), best.Repetitions, $"{label} bestSet[{i}] repetitions");
            AssertRounded($"{label} bestSet[{i}] estimatedOneRepMaxKg", item.GetProperty("estimatedOneRepMaxKg"), best.EstimatedOneRepMaxKg);
        }

        JsonElement[] expectedRecords = expected.GetProperty("newRecords").EnumerateArray().ToArray();
        Assert.HasCount(expectedRecords.Length, summary.NewRecords, $"{label} newRecords count");
        for (int i = 0; i < expectedRecords.Length; i++)
        {
            JsonElement item = expectedRecords[i];
            NewRecord record = summary.NewRecords[i];
            Assert.AreEqual(item.GetProperty("exerciseId").GetString(), ids.NameOf(record.ExerciseId), $"{label} newRecord[{i}] exercise");
            Assert.AreEqual(ParseKind(item.GetProperty("kind").GetString()!), record.Kind, $"{label} newRecord[{i}] kind");
            AssertRounded($"{label} newRecord[{i}] value", item.GetProperty("value"), record.Value);
        }
    }

    private static void AssertRounded(string label, JsonElement expected, decimal? actual)
    {
        if (expected.ValueKind == JsonValueKind.Null)
        {
            Assert.IsNull(actual, label);
            return;
        }

        Assert.IsNotNull(actual, label);
        Assert.AreEqual(expected.GetDecimal(), TrainingStatistics.RoundForOutput(actual.Value), label);
    }

    private static RecordKind ParseKind(string value) => value switch
    {
        "maxWeight" => RecordKind.MaxWeight,
        "estimatedOneRepMax" => RecordKind.EstimatedOneRepMax,
        "volume" => RecordKind.Volume,
        "maxRepetitions" => RecordKind.MaxRepetitions,
        _ => throw new ArgumentOutOfRangeException(nameof(value), value, "Unknown record kind."),
    };

    private static TrainingWorkoutInput ToWorkout(JsonElement item, FixtureIds ids) => new(
        ids.Of(item.GetProperty("workoutId").GetString()!),
        DateTimeOffset.Parse(item.GetProperty("startedAtUtc").GetString()!, CultureInfo.InvariantCulture).UtcDateTime,
        OptionalUtc(item, "endedAtUtc"),
        OptionalUtc(item, "deletedAtUtc"),
        item.GetProperty("exercises").EnumerateArray().Select(block => ToBlock(block, ids)).ToArray());

    private static TrainingBlockInput ToBlock(JsonElement block, FixtureIds ids) => new(
        ids.Of(block.GetProperty("workoutExerciseId").GetString()!),
        ids.Of(block.GetProperty("sourceExerciseId").GetString()!),
        ExerciseTypes.Parse(block.GetProperty("exerciseTypeSnapshot").GetString()),
        block.GetProperty("sets").EnumerateArray().Select(ToSet).ToArray());

    private static TrainingSetInput ToSet(JsonElement set) => new(
        WorkoutSetTypes.ParseOrNormal(set.GetProperty("setType").GetString()),
        OptionalDecimal(set, "weightKg"),
        OptionalInt(set, "repetitions"));

    private static DateTime? OptionalUtc(JsonElement item, string name) =>
        item.TryGetProperty(name, out JsonElement value) && value.ValueKind == JsonValueKind.String
            ? DateTimeOffset.Parse(value.GetString()!, CultureInfo.InvariantCulture).UtcDateTime
            : null;

    private static decimal? OptionalDecimal(JsonElement item, string name) =>
        item.TryGetProperty(name, out JsonElement value) && value.ValueKind == JsonValueKind.Number ? value.GetDecimal() : null;

    private static int? OptionalInt(JsonElement item, string name) =>
        item.TryGetProperty(name, out JsonElement value) && value.ValueKind == JsonValueKind.Number ? value.GetInt32() : null;

    private static JsonElement LoadFixture()
    {
        string path = Path.Combine(AppContext.BaseDirectory, "Fixtures", "training-statistics.json");
        using JsonDocument document = JsonDocument.Parse(File.ReadAllText(path));
        return document.RootElement.Clone();
    }

    /// <summary>Ordnet die lesbaren Fixture-IDs stabile Guids zu und zurück.</summary>
    private sealed class FixtureIds
    {
        private readonly Dictionary<string, Guid> byName = new(StringComparer.Ordinal);
        private readonly Dictionary<Guid, string> byId = [];

        public Guid Of(string name)
        {
            if (!byName.TryGetValue(name, out Guid id))
            {
                id = Guid.NewGuid();
                byName[name] = id;
                byId[id] = name;
            }
            return id;
        }

        public string NameOf(Guid id) => byId[id];
    }
}
