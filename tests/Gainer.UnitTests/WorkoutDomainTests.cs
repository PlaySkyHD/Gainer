using Gainer.Core.Training;

namespace Gainer.UnitTests;

[TestClass]
public sealed class WorkoutDomainTests
{
    [TestMethod]
    public void UnknownSetTypeFallsBackToNormal()
    {
        Assert.AreEqual(WorkoutSetType.Normal, WorkoutSetTypes.ParseOrNormal("unknown"));
        Assert.AreEqual(WorkoutSetType.Normal, WorkoutSetTypes.ParseOrNormal(null));
        Assert.AreEqual(WorkoutSetType.Dropset, WorkoutSetTypes.ParseOrNormal("dropset"));
    }

    [TestMethod]
    public void WorkoutValidationReportsFieldKeysForBoundsAndEndTime()
    {
        WorkoutValues workout = Workout(
            endedAt: new DateTime(2026, 8, 18, 16, 30, 0, DateTimeKind.Utc),
            title: " ",
            exercises: [Exercise(sets: [Set(weight: 10_001m, repetitions: 8, rir: 11m)])]);

        WorkoutValidationException exception = Assert.ThrowsExactly<WorkoutValidationException>(
            () => WorkoutValidation.Normalize(workout));

        Assert.IsTrue(exception.Errors.ContainsKey("Title"));
        Assert.IsTrue(exception.Errors.ContainsKey("EndedAtUtc"));
        Assert.IsTrue(exception.Errors.ContainsKey("Exercises[0].Sets[0].WeightKg"));
        Assert.IsTrue(exception.Errors.ContainsKey("Exercises[0].Sets[0].Rir"));
    }

    [TestMethod]
    public void WorkoutValidationNormalizesUnknownSetTypeAndTrimsNotes()
    {
        WorkoutValues workout = Workout(
            endedAt: null,
            notes: "   ",
            exercises: [Exercise(sets: [Set(setType: "mystery", notes: " clean ")])]);

        WorkoutValues normalized = WorkoutValidation.Normalize(workout);

        Assert.IsNull(normalized.Notes);
        Assert.AreEqual("normal", normalized.Exercises[0].Sets[0].SetType);
        Assert.AreEqual("clean", normalized.Exercises[0].Sets[0].Notes);
    }

    [TestMethod]
    public void WorkoutValidationRejectsTooManyExercises()
    {
        WorkoutValues workout = Workout(
            endedAt: null,
            exercises: Enumerable.Range(0, WorkoutValidation.MaximumExercises + 1)
                .Select(_ => Exercise(sets: []))
                .ToArray());

        WorkoutValidationException exception = Assert.ThrowsExactly<WorkoutValidationException>(
            () => WorkoutValidation.Normalize(workout));

        Assert.IsTrue(exception.Errors.ContainsKey("Exercises"));
    }

    [TestMethod]
    public void PlanEntryNeedsAtLeastOneSetAndPlanNeedsAName()
    {
        var plan = new TrainingPlanValues(
            Guid.NewGuid(),
            " ",
            null,
            "exercise",
            [new TrainingPlanEntryValues(Guid.NewGuid(), Guid.NewGuid(), 0, 0, null, null)]);

        TrainingPlanValidationException exception = Assert.ThrowsExactly<TrainingPlanValidationException>(
            () => TrainingPlanValidation.Normalize(plan));

        Assert.IsTrue(exception.Errors.ContainsKey("Name"));
        Assert.IsTrue(exception.Errors.ContainsKey("Entries[0].WorkingSets"));
    }

    [TestMethod]
    public void PlanEntryTotalAboveFiftySetsIsRejectedAtTheEntry()
    {
        var plan = new TrainingPlanValues(
            Guid.NewGuid(),
            "Push",
            null,
            "exercise",
            [new TrainingPlanEntryValues(Guid.NewGuid(), Guid.NewGuid(), 20, 50, null, null)]);

        TrainingPlanValidationException exception = Assert.ThrowsExactly<TrainingPlanValidationException>(
            () => TrainingPlanValidation.Normalize(plan));

        Assert.IsTrue(exception.Errors.ContainsKey("Entries[0].WorkingSets"));
        Assert.IsFalse(exception.Errors.ContainsKey("Entries[0].WarmupSets"));
    }

    [TestMethod]
    public void PlanRejectsUnknownPreviousValueSource()
    {
        var plan = new TrainingPlanValues(Guid.NewGuid(), "Push", null, "yesterday", []);

        TrainingPlanValidationException exception = Assert.ThrowsExactly<TrainingPlanValidationException>(
            () => TrainingPlanValidation.Normalize(plan));

        Assert.IsTrue(exception.Errors.ContainsKey("PreviousValueSource"));
    }

    private static WorkoutValues Workout(
        DateTime? endedAt,
        string title = "Push",
        string? notes = null,
        IReadOnlyList<WorkoutExerciseValues>? exercises = null) => new(
        Guid.NewGuid(),
        title,
        notes,
        new DateTime(2026, 8, 18, 17, 0, 0, DateTimeKind.Utc),
        endedAt,
        "exercise",
        null,
        null,
        exercises ?? []);

    private static WorkoutExerciseValues Exercise(IReadOnlyList<WorkoutSetValues> sets) => new(
        Guid.NewGuid(),
        Guid.NewGuid(),
        "Bench press",
        "strength",
        null,
        null,
        sets);

    private static WorkoutSetValues Set(
        string setType = "normal",
        decimal? weight = 100m,
        int? repetitions = 8,
        decimal? rir = null,
        string? notes = null) => new(Guid.NewGuid(), setType, weight, repetitions, rir, notes);
}
