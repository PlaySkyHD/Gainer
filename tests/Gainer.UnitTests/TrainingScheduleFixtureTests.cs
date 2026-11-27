using System.Globalization;
using System.Text.Json;
using Gainer.Core.Nutrition;
using Gainer.Core.Training;
using static Gainer.UnitTests.ContractFixture;

namespace Gainer.UnitTests;

/// <summary>The training schedule projection computes as in the app (contracts/fixtures/training-schedule.json).</summary>
[TestClass]
public sealed class TrainingScheduleFixtureTests
{
    private const string FileName = "training-schedule.json";
    private static readonly DateOnly Today = new(2026, 10, 21);
    private static readonly TimeZoneInfo Berlin = TimeZoneInfo.FindSystemTimeZoneById("Europe/Berlin");

    public static IEnumerable<object[]> Names => CaseNames(FileName);

    [TestMethod]
    [DynamicData(nameof(Names))]
    public void FixtureCaseMatchesProjection(string caseName)
    {
        JsonElement item = Case(FileName, caseName);
        var names = new FixtureNames();
        DateOnly today = Date(item.GetProperty("today"));
        var projection = new TrainingScheduleProjection(
            Schedule(item.GetProperty("schedule"), names),
            item.GetProperty("plans").EnumerateArray()
                .Select(plan => new SchedulePlanInput(
                    names.Of(plan.GetProperty("planId")), plan.GetProperty("name").GetString()!, plan.GetProperty("isArchived").GetBoolean()))
                .ToArray(),
            item.GetProperty("workouts").EnumerateArray()
                .Select(workout => new ScheduleWorkoutInput(
                    names.Of(workout.GetProperty("workoutId")),
                    Utc(workout.GetProperty("startedAtUtc")),
                    OptionalUtc(workout, "endedAtUtc"),
                    OptionalUtc(workout, "deletedAtUtc"),
                    OptionalName(workout.GetProperty("sourcePlanId"), names)))
                .ToArray(),
            today,
            TimeZoneInfo.FindSystemTimeZoneById(item.GetProperty("timeZone").GetString()!));

        JsonElement expected = item.GetProperty("expected");
        AssertOptionalInt("effectiveCycleIndex", expected.GetProperty("effectiveCycleIndex"), projection.EffectiveCycleIndex(today));
        ScheduledTraining? next = projection.NextPlannedAfter(today);
        JsonElement wantNext = expected.GetProperty("nextPlanned");
        Assert.AreEqual(
            wantNext.ValueKind == JsonValueKind.Null ? null : $"{wantNext.GetProperty("planId").GetString()}@{wantNext.GetProperty("date").GetString()}",
            next is null ? null : $"{names.NameOf(next.PlanId)}@{Iso(next.Date)}");

        JsonElement[] wantDays = expected.GetProperty("days").EnumerateArray().ToArray();
        IReadOnlyList<ScheduleDay> days = projection.Days(Date(item.GetProperty("from")), Date(item.GetProperty("through")));
        Assert.HasCount(wantDays.Length, days);
        for (int i = 0; i < wantDays.Length; i++)
        {
            Assert.AreEqual(Describe(wantDays[i]), Describe(days[i], projection, names), Iso(days[i].Date));
            Assert.AreEqual(days[i].IsFree, days[i].EffectiveTrainings().Length == 0, Iso(days[i].Date));
        }
    }

    [TestMethod]
    public void WithoutRhythmNothingIsPlanned()
    {
        var projection = new TrainingScheduleProjection(null, [], [], Today, Berlin);

        Assert.IsNull(projection.BasePlanOn(Today));
        Assert.IsNull(projection.CycleSlotIndexOn(Today));
        Assert.IsNull(projection.NextPlannedAfter(Today));
        Assert.IsFalse(projection.IsCycle);
        Assert.AreEqual(ScheduleBaseKind.None, projection.Day(Today).BaseKind);
        Assert.AreEqual(NutritionDayKind.Rest, projection.AutomaticDayKind(Today));
    }

    [TestMethod]
    public void CycleWithoutAnchorOrSlotsPlansNothing()
    {
        Guid plan = Guid.NewGuid();
        SchedulePlanInput[] plans = [new(plan, "Push", false)];
        var withoutAnchor = new TrainingScheduleProjection(
            new ScheduleProjectionInput(TrainingScheduleMode.Cycle, null, Today, [plan], [], []), plans, [], Today, Berlin);
        var withoutSlots = new TrainingScheduleProjection(
            new ScheduleProjectionInput(TrainingScheduleMode.Cycle, Today, Today, [], [], []), plans, [], Today, Berlin);

        Assert.AreEqual(ScheduleBaseKind.None, withoutAnchor.Day(Today).BaseKind);
        Assert.IsNull(withoutAnchor.EffectiveCycleIndex(Today));
        Assert.IsNull(withoutSlots.EffectiveCycleIndex(Today));
        Assert.AreEqual("Plan", withoutAnchor.PlanName(Guid.NewGuid()));
        Assert.IsNull(withoutAnchor.Plan(Guid.NewGuid()));
        Assert.AreEqual("Push", withoutAnchor.Plan(plan)?.Name);
        Assert.IsTrue(withoutAnchor.IsActivePlan(plan));
        Assert.IsFalse(withoutAnchor.IsActivePlan(null));
    }

    [TestMethod]
    public void ExceptionAppliesOnlyWhileItsPlanIsStillPlanned()
    {
        Guid push = Guid.NewGuid();
        Guid pull = Guid.NewGuid();
        var projection = new TrainingScheduleProjection(
            new ScheduleProjectionInput(TrainingScheduleMode.Cycle, Today, Today, [push, pull], [], []),
            [new SchedulePlanInput(push, "Push", false), new SchedulePlanInput(pull, "Pull", false)],
            [],
            Today,
            Berlin);

        Assert.IsTrue(projection.IsEffective(new ScheduleExceptionInput(Today, push, null)));
        Assert.IsFalse(projection.IsEffective(new ScheduleExceptionInput(Today, pull, null)));
        Assert.IsTrue(projection.IsCycle);
        Assert.AreEqual(1, projection.CycleSlotIndexOn(Today.AddDays(1)));
    }

    private static ScheduleProjectionInput? Schedule(JsonElement json, FixtureNames names)
    {
        if (json.ValueKind == JsonValueKind.Null) return null;
        TrainingScheduleMode mode = TrainingScheduleModes.Parse(json.GetProperty("mode").GetString()!);
        JsonElement anchor = json.GetProperty("anchorDate");
        return new ScheduleProjectionInput(
            mode,
            anchor.ValueKind == JsonValueKind.Null ? null : Date(anchor),
            Date(json.GetProperty("validFrom")),
            json.GetProperty("slots").EnumerateArray().Select(slot => OptionalName(slot, names)).ToArray(),
            json.GetProperty("shifts").EnumerateArray()
                .Select(shift => new ScheduleShiftInput(Date(shift.GetProperty("fromDate")), shift.GetProperty("days").GetInt32()))
                .ToArray(),
            json.GetProperty("exceptions").EnumerateArray()
                .Select(exception => new ScheduleExceptionInput(
                    Date(exception.GetProperty("date")),
                    names.Of(exception.GetProperty("planId")),
                    exception.GetProperty("movedToDate").ValueKind == JsonValueKind.Null ? null : Date(exception.GetProperty("movedToDate"))))
                .ToArray());
    }

    private static Guid? OptionalName(JsonElement value, FixtureNames names) =>
        value.ValueKind == JsonValueKind.Null ? null : names.Of(value);

    /// <summary>One comparable line per day, from the fixture.</summary>
    private static string Describe(JsonElement day) => string.Join(" | ",
        day.GetProperty("date").GetString(),
        day.GetProperty("baseKind").GetString(),
        Text(day.GetProperty("slotIndex")),
        Text(day.GetProperty("archivedPlanId")),
        day.GetProperty("isFree").GetBoolean(),
        day.GetProperty("hasFinished").GetBoolean(),
        day.GetProperty("automaticDayKind").GetString(),
        string.Join("; ", day.GetProperty("trainings").EnumerateArray().Select(training => string.Join(",",
            training.GetProperty("planId").GetString(),
            training.GetProperty("planName").GetString(),
            training.GetProperty("date").GetString(),
            training.GetProperty("originDate").GetString(),
            training.GetProperty("status").GetString(),
            Text(training.GetProperty("movedToDate")),
            string.Join("+", training.GetProperty("completedBy").EnumerateArray().Select(id => id.GetString())),
            string.Join("+", training.GetProperty("instead").EnumerateArray().Select(id => id.GetString()))))));

    /// <summary>The same line from the projection, in the fixture's names and casing.</summary>
    private static string Describe(ScheduleDay day, TrainingScheduleProjection projection, FixtureNames names) => string.Join(" | ",
        Iso(day.Date),
        Camel(day.BaseKind.ToString()),
        day.SlotIndex?.ToString(CultureInfo.InvariantCulture) ?? "-",
        day.ArchivedPlanId is { } archived ? names.NameOf(archived) : "-",
        day.IsFree,
        projection.HasFinishedOn(day.Date),
        Camel(projection.AutomaticDayKind(day).ToString()),
        string.Join("; ", day.Trainings.Select(training => string.Join(",",
            names.NameOf(training.PlanId),
            training.PlanName,
            Iso(training.Date),
            Iso(training.OriginDate),
            Camel(training.Status.ToString()),
            training.MovedToDate is { } moved ? Iso(moved) : "-",
            string.Join("+", training.CompletedBy.Select(names.NameOf)),
            string.Join("+", training.Instead.Select(names.NameOf))))));

    private static string Text(JsonElement value) => value.ValueKind switch
    {
        JsonValueKind.Null => "-",
        JsonValueKind.Number => value.GetInt32().ToString(CultureInfo.InvariantCulture),
        _ => value.GetString()!,
    };

    private static string Camel(string value) => char.ToLowerInvariant(value[0]) + value[1..];

    private static string Iso(DateOnly date) => date.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
}
