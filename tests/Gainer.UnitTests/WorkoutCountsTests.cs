using Gainer.Core.Insights;
using Gainer.Core.Training;

namespace Gainer.UnitTests;

/// <summary>Port of the app's <c>workoutCounts</c>: week Monday to Sunday on local days (Europe/Berlin).</summary>
[TestClass]
public sealed class WorkoutCountsTests
{
    private static readonly TimeZoneInfo Berlin = LocalDays.Default;

    // Winter time, so local = UTC + 1. 2026-11-23 is a Monday.
    private static readonly TrainingWorkoutInput[] Workouts =
    [
        Finished(new DateTime(2026, 11, 22, 22, 30, 0, DateTimeKind.Utc)), // Sunday 23:30 local, previous week
        Finished(new DateTime(2026, 11, 22, 23, 30, 0, DateTimeKind.Utc)), // Monday 00:30 local
        Finished(new DateTime(2026, 11, 26, 17, 0, 0, DateTimeKind.Utc)), // Thursday
        Finished(new DateTime(2026, 11, 29, 22, 0, 0, DateTimeKind.Utc)), // Sunday 23:00 local
        Finished(new DateTime(2026, 11, 29, 23, 30, 0, DateTimeKind.Utc)), // Monday 00:30 local, next week
        new(Guid.NewGuid(), new DateTime(2026, 11, 25, 17, 0, 0, DateTimeKind.Utc), null, null, []),
        new(Guid.NewGuid(), new DateTime(2026, 11, 25, 9, 0, 0, DateTimeKind.Utc),
            new DateTime(2026, 11, 25, 10, 0, 0, DateTimeKind.Utc), new DateTime(2026, 11, 25, 11, 0, 0, DateTimeKind.Utc), []),
    ];

    [TestMethod]
    public void CountsCompletedWorkoutsAndThoseOfTheLocalWeek()
    {
        WorkoutCounts counts = TrainingStatistics.Counts(
            Workouts, new DateTime(2026, 11, 27, 12, 0, 0, DateTimeKind.Utc), Berlin);

        Assert.AreEqual(new WorkoutCounts(5, 3), counts);
    }

    [TestMethod]
    public void WeekFollowsTheLocalDayOfNow()
    {
        WorkoutCounts sundayNight = TrainingStatistics.Counts(
            Workouts, new DateTime(2026, 11, 29, 22, 30, 0, DateTimeKind.Utc), Berlin);
        WorkoutCounts mondayMorning = TrainingStatistics.Counts(
            Workouts, new DateTime(2026, 11, 29, 23, 30, 0, DateTimeKind.Utc), Berlin);

        Assert.AreEqual(3, sundayNight.ThisWeek);
        Assert.AreEqual(1, mondayMorning.ThisWeek);
        Assert.AreEqual(0, TrainingStatistics.Counts([], DateTime.UtcNow, Berlin).Total);
    }

    private static TrainingWorkoutInput Finished(DateTime startedAtUtc) =>
        new(Guid.NewGuid(), startedAtUtc, startedAtUtc.AddHours(1), null, []);
}
