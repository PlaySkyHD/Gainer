using System.Text.Json;
using Gainer.Core.Mutations;
using Gainer.Core.Training;

namespace Gainer.UnitTests;

[TestClass]
public sealed class TrainingScheduleValidationTests
{
    private static readonly Guid Push = Guid.Parse("00000000-0000-0000-0000-000000000001");
    private static readonly Guid Pull = Guid.Parse("00000000-0000-0000-0000-000000000002");
    private static readonly DateOnly Anchor = new(2026, 10, 20);
    private static readonly JsonSerializerOptions WebJson = new(JsonSerializerDefaults.Web);

    [TestMethod]
    public void ValidCycleAndWeeklySchedulesPass()
    {
        TrainingScheduleValues cycle = Cycle(
            [new(Push), new(Pull), new(null)],
            shifts: [new(new DateOnly(2026, 10, 23), 1)],
            exceptions: [new(new DateOnly(2026, 10, 22), Pull, new DateOnly(2026, 10, 23))]);
        TrainingScheduleValues weekly = Weekly([new(Push), new(null), new(Pull), new(null), new(Push), new(null), new(null)]);

        TrainingScheduleValues normalized = TrainingScheduleValidation.Normalize(cycle);
        Assert.AreSequenceEqual(cycle.Slots.ToArray(), normalized.Slots.ToArray());
        Assert.AreSequenceEqual(cycle.Exceptions.ToArray(), normalized.Exceptions.ToArray());
        Assert.HasCount(7, TrainingScheduleValidation.Normalize(weekly).Slots);
    }

    [TestMethod]
    public void CycleNeedsOneToTwentyEightSlotsAndAnAnchor()
    {
        AssertInvalid(Cycle([]), nameof(TrainingScheduleValues.Slots));
        AssertInvalid(Cycle(Enumerable.Repeat(new TrainingScheduleSlotValues(Push), 29).ToArray()), nameof(TrainingScheduleValues.Slots));
        AssertInvalid(Cycle([new(Push)]) with { AnchorDate = null }, nameof(TrainingScheduleValues.AnchorDate));

        _ = TrainingScheduleValidation.Normalize(Cycle([new(Push)]));
        _ = TrainingScheduleValidation.Normalize(Cycle(Enumerable.Repeat(new TrainingScheduleSlotValues(Push), 28).ToArray()));
    }

    [TestMethod]
    public void WeeklyNeedsSevenSlotsNoAnchorAndNoShifts()
    {
        TrainingScheduleSlotValues[] week = [new(Push), new(null), new(null), new(null), new(null), new(null), new(null)];

        AssertInvalid(Weekly(week[..6]), nameof(TrainingScheduleValues.Slots));
        AssertInvalid(Weekly([.. week, new(null)]), nameof(TrainingScheduleValues.Slots));
        AssertInvalid(Weekly(week) with { AnchorDate = Anchor }, nameof(TrainingScheduleValues.AnchorDate));
        AssertInvalid(Weekly(week) with { Shifts = [new(Anchor, 1)] }, nameof(TrainingScheduleValues.Shifts));
    }

    [TestMethod]
    public void AtLeastOneSlotMustBeAPlan()
    {
        AssertInvalid(Cycle([new(null), new(null)]), nameof(TrainingScheduleValues.Slots));
        AssertInvalid(Weekly(Enumerable.Repeat(new TrainingScheduleSlotValues(null), 7).ToArray()), nameof(TrainingScheduleValues.Slots));
        AssertInvalid(Cycle([new(Guid.Empty)]), nameof(TrainingScheduleValues.Slots));
    }

    [TestMethod]
    public void ModeMustBeKnown()
    {
        AssertInvalid(Cycle([new(Push)]) with { Mode = "Cycle" }, nameof(TrainingScheduleValues.Mode));
        AssertInvalid(Cycle([new(Push)]) with { Mode = "" }, nameof(TrainingScheduleValues.Mode));
    }

    [TestMethod]
    public void ShiftDaysMustBeBetweenOneAndThirtyOne()
    {
        AssertInvalid(Cycle([new(Push)], shifts: [new(Anchor, 0)]), nameof(TrainingScheduleValues.Shifts));
        AssertInvalid(Cycle([new(Push)], shifts: [new(Anchor, 32)]), nameof(TrainingScheduleValues.Shifts));
        _ = TrainingScheduleValidation.Normalize(Cycle([new(Push)], shifts: [new(Anchor, 1), new(Anchor.AddDays(5), 31)]));
    }

    [TestMethod]
    public void ExceptionsAreUniquePerDayAndPlan()
    {
        DateOnly day = Anchor.AddDays(2);
        AssertInvalid(
            Cycle([new(Push), new(Pull)], exceptions: [new(day, Push, null), new(day, Push, day.AddDays(1))]),
            nameof(TrainingScheduleValues.Exceptions));
        AssertInvalid(Cycle([new(Push)], exceptions: [new(day, Guid.Empty, null)]), nameof(TrainingScheduleValues.Exceptions));

        _ = TrainingScheduleValidation.Normalize(
            Cycle([new(Push), new(Pull)], exceptions: [new(day, Push, null), new(day, Pull, null), new(day.AddDays(1), Push, null)]));
    }

    [TestMethod]
    public void ShiftsAndExceptionsTogetherAreLimitedToOneThousand()
    {
        TrainingScheduleShiftValues[] shifts = Enumerable.Range(0, 500).Select(index => new TrainingScheduleShiftValues(Anchor.AddDays(index), 1)).ToArray();
        TrainingScheduleExceptionValues[] exceptions = Enumerable.Range(0, 500)
            .Select(index => new TrainingScheduleExceptionValues(Anchor.AddDays(index), Push, null)).ToArray();

        _ = TrainingScheduleValidation.Normalize(Cycle([new(Push)], shifts, exceptions));
        AssertInvalid(
            Cycle([new(Push)], shifts, [.. exceptions, new(Anchor.AddDays(-1), Push, null)]),
            nameof(TrainingScheduleValues.Exceptions));
    }

    [TestMethod]
    public void MissingListsAreValidationErrors()
    {
        AssertInvalid(Cycle([new(Push)]) with { Slots = null! }, nameof(TrainingScheduleValues.Slots));
        AssertInvalid(Cycle([new(Push)]) with { Shifts = null! }, nameof(TrainingScheduleValues.Shifts));
        AssertInvalid(Cycle([new(Push)]) with { Exceptions = null! }, nameof(TrainingScheduleValues.Exceptions));
    }

    [TestMethod]
    public void ShiftsStartOnDistinctDays()
    {
        AssertInvalid(Cycle([new(Push)], shifts: [new(Anchor, 1), new(Anchor, 2)]), nameof(TrainingScheduleValues.Shifts));
        _ = TrainingScheduleValidation.Normalize(Cycle([new(Push)], shifts: [new(Anchor, 1), new(Anchor.AddDays(1), 2)]));
    }

    [TestMethod]
    public void MovedWorkoutsLandOnAnotherDayWithinThirtyOneDays()
    {
        DateOnly day = Anchor.AddDays(10);
        AssertInvalid(Cycle([new(Push)], exceptions: [new(day, Push, day)]), nameof(TrainingScheduleValues.Exceptions));
        AssertInvalid(Cycle([new(Push)], exceptions: [new(day, Push, day.AddDays(32))]), nameof(TrainingScheduleValues.Exceptions));
        AssertInvalid(Cycle([new(Push)], exceptions: [new(day, Push, day.AddDays(-32))]), nameof(TrainingScheduleValues.Exceptions));

        _ = TrainingScheduleValidation.Normalize(Cycle([new(Push)], exceptions:
        [
            new(day, Push, day.AddDays(1)),
            new(day.AddDays(1), Push, day.AddDays(32)),
            new(day.AddDays(2), Push, day.AddDays(-29)),
            new(day.AddDays(3), Push, null),
        ]));
    }

    [TestMethod]
    public void TrainingScheduleUsesANewResourceKindAndNeverReusesTheRotationValue()
    {
        Assert.AreEqual(12, (int)ResourceKind.TrainingSchedule);
        Assert.IsFalse(Enum.IsDefined(typeof(ResourceKind), 5));
    }

    [TestMethod]
    public void MutationsDeclareTheScheduleResource()
    {
        Guid id = Guid.NewGuid();
        MutationMetadata metadata = MutationMetadata.Create(Guid.NewGuid(), Guid.NewGuid(), 1);
        SaveTrainingScheduleMutation save = SaveTrainingScheduleMutation.Create(metadata, 0, Cycle([new(Push)]) with { ScheduleId = id });
        DeleteTrainingScheduleMutation delete = DeleteTrainingScheduleMutation.Create(metadata, id, 3);

        Assert.AreEqual(ResourceKey.Create(ResourceKind.TrainingSchedule, id), save.Scope.Resources[0].Resource);
        Assert.AreEqual(3, delete.Scope.Resources[0].BaseVersion);
        Assert.ThrowsExactly<ArgumentOutOfRangeException>(() => DeleteTrainingScheduleMutation.Create(metadata, id, 0));
    }

    [TestMethod]
    public void SnapshotSerializesToTheWireContract()
    {
        Guid id = Guid.Parse("11111111-1111-1111-1111-111111111111");
        var snapshot = new TrainingScheduleSnapshot(
            id,
            TrainingScheduleModes.Cycle,
            Anchor,
            new DateOnly(2026, 10, 21),
            [new(Push), new(null)],
            [new(new DateOnly(2026, 10, 23), 1)],
            [new(new DateOnly(2026, 10, 22), Push, new DateOnly(2026, 10, 23))],
            new DateTime(2026, 10, 21, 8, 0, 0, DateTimeKind.Utc),
            2);

        using JsonDocument json = JsonSerializer.SerializeToDocument(snapshot, WebJson);
        JsonElement root = json.RootElement;

        Assert.AreEqual(id.ToString(), root.GetProperty("scheduleId").GetString());
        Assert.AreEqual("cycle", root.GetProperty("mode").GetString());
        Assert.AreEqual("2026-10-20", root.GetProperty("anchorDate").GetString());
        Assert.AreEqual("2026-10-21", root.GetProperty("validFrom").GetString());
        Assert.AreEqual(Push.ToString(), root.GetProperty("slots")[0].GetProperty("planId").GetString());
        Assert.AreEqual(JsonValueKind.Null, root.GetProperty("slots")[1].GetProperty("planId").ValueKind);
        Assert.AreEqual("2026-10-23", root.GetProperty("shifts")[0].GetProperty("fromDate").GetString());
        Assert.AreEqual(1, root.GetProperty("shifts")[0].GetProperty("days").GetInt32());
        JsonElement exception = root.GetProperty("exceptions")[0];
        Assert.AreEqual("2026-10-22", exception.GetProperty("date").GetString());
        Assert.AreEqual(Push.ToString(), exception.GetProperty("planId").GetString());
        Assert.AreEqual("2026-10-23", exception.GetProperty("movedToDate").GetString());
        Assert.AreEqual(2, root.GetProperty("version").GetInt64());
        Assert.IsTrue(root.TryGetProperty("updatedAtUtc", out _));
        Assert.IsFalse(root.TryGetProperty("baseVersion", out _));
    }

    private static TrainingScheduleValues Cycle(
        TrainingScheduleSlotValues[] slots,
        TrainingScheduleShiftValues[]? shifts = null,
        TrainingScheduleExceptionValues[]? exceptions = null) =>
        new(Guid.NewGuid(), TrainingScheduleModes.Cycle, Anchor, Anchor, slots, shifts ?? [], exceptions ?? []);

    private static TrainingScheduleValues Weekly(TrainingScheduleSlotValues[] slots) =>
        new(Guid.NewGuid(), TrainingScheduleModes.Weekly, null, Anchor, slots, [], []);

    private static void AssertInvalid(TrainingScheduleValues schedule, string key)
    {
        TrainingScheduleValidationException exception = Assert.ThrowsExactly<TrainingScheduleValidationException>(
            () => TrainingScheduleValidation.Normalize(schedule));
        Assert.IsTrue(exception.Errors.ContainsKey(key), $"Expected error for {key}, got {string.Join(", ", exception.Errors.Keys)}.");
    }
}
