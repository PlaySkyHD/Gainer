using System.Text.Json;
using Gainer.Core.Training;
using static Gainer.UnitTests.ContractFixture;

namespace Gainer.UnitTests;

/// <summary>The muscle map computes as in the app (contracts/fixtures/muscle-volume.json).</summary>
[TestClass]
public sealed class MuscleVolumeFixtureTests
{
    private const string FileName = "muscle-volume.json";

    public static IEnumerable<object[]> Names => CaseNames(FileName);

    [TestMethod]
    [DynamicData(nameof(Names))]
    public void FixtureCaseMatchesCalculation(string caseName)
    {
        JsonElement fixtureCase = Case(FileName, caseName);
        var ids = new FixtureNames();
        Dictionary<Guid, MuscleExerciseInput> exercises = fixtureCase.GetProperty("exercises").EnumerateArray()
            .Select(item => new MuscleExerciseInput(
                ids.Of(item.GetProperty("id")),
                item.GetProperty("name").GetString()!,
                Strings(item.GetProperty("primaryMuscles")),
                Strings(item.GetProperty("secondaryMuscles"))))
            .ToDictionary(item => item.ExerciseId);
        MuscleVolumeSnapshot volume = fixtureCase.GetProperty("source").GetString() == "planned"
            ? MuscleVolume.FromPlans(fixtureCase.GetProperty("plans").EnumerateArray().Select(item => ToPlan(item, ids)), exercises)
            : MuscleVolume.FromWorkouts(
                fixtureCase.GetProperty("workouts").EnumerateArray().Select(item => ToWorkout(item, ids)),
                exercises,
                Utc(fixtureCase.GetProperty("fromUtc")),
                Utc(fixtureCase.GetProperty("toUtc")),
                fixtureCase.GetProperty("weeks").GetInt32());

        JsonElement expected = fixtureCase.GetProperty("expected");
        Assert.AreSequenceEqual(Strings(expected.GetProperty("ranked")), volume.Muscles.Select(item => item.Muscle).ToArray());
        JsonElement[] muscles = expected.GetProperty("muscles").EnumerateArray().ToArray();
        MuscleSets[] trained = volume.Muscles.Where(item => item.Sets > 0).ToArray();
        Assert.HasCount(muscles.Length, trained);
        for (int i = 0; i < muscles.Length; i++)
        {
            AssertMuscle(muscles[i], trained[i], ids);
        }

        Assert.AreSequenceEqual(
            expected.GetProperty("exercisesWithoutMuscles").EnumerateArray()
                .Select(item => $"{item.GetProperty("id").GetString()}/{item.GetProperty("name").GetString()}")
                .ToArray(),
            volume.ExercisesWithoutMuscles.Select(item => $"{ids.NameOf(item.ExerciseId)}/{item.Name}").ToArray());
    }

    [TestMethod]
    public void UntrainedMusclesHaveNoLevel()
    {
        MuscleVolumeSnapshot volume = MuscleVolume.FromPlans([], new Dictionary<Guid, MuscleExerciseInput>());
        Assert.HasCount(MuscleKeys.Known.Count, volume.Muscles);
        Assert.AreSequenceEqual(MuscleKeys.Known.ToArray(), volume.Muscles.Select(item => item.Muscle).ToArray());
        foreach (MuscleSets muscle in volume.Muscles)
        {
            Assert.AreEqual(MuscleLevel.None, muscle.Level, muscle.Muscle);
            Assert.IsEmpty(muscle.Contributions, muscle.Muscle);
        }
    }

    private static void AssertMuscle(JsonElement expected, MuscleSets actual, FixtureNames ids)
    {
        string label = actual.Muscle;
        Assert.AreEqual(expected.GetProperty("muscle").GetString(), label);
        AssertRounded($"{label} sets", expected.GetProperty("sets"), actual.Sets);
        Assert.AreEqual(expected.GetProperty("level").GetString(), JsonNamingPolicy.CamelCase.ConvertName(actual.Level.ToString()), label);
        JsonElement[] contributions = expected.GetProperty("contributions").EnumerateArray().ToArray();
        Assert.HasCount(contributions.Length, actual.Contributions, label);
        for (int i = 0; i < contributions.Length; i++)
        {
            JsonElement want = contributions[i];
            MuscleContribution contribution = actual.Contributions[i];
            Assert.AreEqual(want.GetProperty("exerciseId").GetString(), ids.NameOf(contribution.ExerciseId), label);
            Assert.AreEqual(want.GetProperty("exerciseName").GetString(), contribution.ExerciseName, label);
            Assert.AreEqual(want.GetProperty("role").GetString(), JsonNamingPolicy.CamelCase.ConvertName(contribution.Role.ToString()), label);
            AssertRounded($"{label} workingSets", want.GetProperty("workingSets"), contribution.WorkingSets);
            AssertRounded($"{label} contribution sets", want.GetProperty("sets"), contribution.Sets);
        }
    }

    private static string[] Strings(JsonElement array) => array.EnumerateArray().Select(item => item.GetString()!).ToArray();

    private static PlannedSetsInput ToPlan(JsonElement item, FixtureNames ids) => new(
        ids.Of(item.GetProperty("planId")),
        item.GetProperty("archived").GetBoolean(),
        item.GetProperty("entries").EnumerateArray()
            .Select(entry => new PlannedExerciseSets(ids.Of(entry.GetProperty("exerciseId")), entry.GetProperty("workingSets").GetInt32()))
            .ToArray());

    private static MuscleWorkoutInput ToWorkout(JsonElement item, FixtureNames ids) => new(
        Utc(item.GetProperty("startedAtUtc")),
        OptionalUtc(item, "endedAtUtc"),
        OptionalUtc(item, "deletedAtUtc"),
        item.GetProperty("exercises").EnumerateArray()
            .Select(block => new MuscleBlockInput(
                ids.Of(block.GetProperty("sourceExerciseId")),
                block.GetProperty("exerciseNameSnapshot").GetString()!,
                ExerciseTypes.Parse(block.GetProperty("exerciseTypeSnapshot").GetString()),
                block.GetProperty("sets").EnumerateArray().Select(TrainingTrendsFixtureTests.ToSet).ToArray()))
            .ToArray());
}
