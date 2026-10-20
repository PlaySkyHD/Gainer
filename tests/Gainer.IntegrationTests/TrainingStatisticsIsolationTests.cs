using System.Text.Json;
using Gainer.Core.BodyTracking;
using Gainer.Core.Coach;
using Gainer.Core.Insights;
using Gainer.Core.Security;
using Gainer.Core.Training;
using Gainer.Infrastructure.Coach;
using Gainer.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Gainer.IntegrationTests;

[TestClass]
[DoNotParallelize]
public sealed class TrainingStatisticsIsolationTests
{
    public TestContext TestContext { get; set; } = null!;

    private static readonly TimeZoneInfo Berlin = TimeZoneInfo.FindSystemTimeZoneById("Europe/Berlin");
    private static readonly Guid BenchPress = Guid.Parse("0159d8e1-ec7a-527a-9887-5cb4f70b1c83");
    private static readonly Guid PullUp = Guid.Parse("42ce4803-05e3-5f07-92b6-326c9aa95658");
    private static readonly Guid PushUp = Guid.Parse("2b8f7aee-2d29-4d6e-8dc8-d5b39bff5f9d");
    private static readonly DateTime ThroughUtc = new(2026, 8, 19, 12, 0, 0, DateTimeKind.Utc);
    private static PostgreSqlTestFixture? fixture;
    private static PostgreSqlTestFixture Fixture => fixture!;

    [ClassInitialize]
    public static async Task StartAsync(TestContext context)
    {
        _ = context;
        fixture = new PostgreSqlTestFixture();
        await fixture.StartAsync();
    }

    [ClassCleanup]
    public static async Task StopAsync()
    {
        if (fixture is not null) await fixture.DisposeAsync();
    }

    [TestMethod]
    public async Task DeletedActiveAndForeignWorkoutsDoNotFlowIntoStatistics()
    {
        (string connectionString, Guid owner, Guid other) = await CreateDatabaseAsync();
        Guid exerciseId = BaseExercise(ExerciseType.Strength);
        await using (AppDbContext seed = Fixture.CreateContext(connectionString, owner))
        {
            AddFinishedWorkout(seed, exerciseId, ExerciseType.Strength, Utc(2026, 8, 18, 18), Utc(2026, 8, 18, 19), null, (100m, 5));
            AddFinishedWorkout(seed, exerciseId, ExerciseType.Strength, Utc(2026, 8, 17, 18), Utc(2026, 8, 17, 19), Utc(2026, 8, 19, 8), (300m, 5));
            AddFinishedWorkout(seed, exerciseId, ExerciseType.Strength, Utc(2026, 8, 18, 20), null, null, (400m, 5));
            await seed.SaveChangesAsync(TestContext.CancellationToken);
        }
        await using (AppDbContext seed = Fixture.CreateContext(connectionString, other))
        {
            AddFinishedWorkout(seed, exerciseId, ExerciseType.Strength, Utc(2026, 8, 18, 18), Utc(2026, 8, 18, 19), null, (500m, 5));
            await seed.SaveChangesAsync(TestContext.CancellationToken);
        }

        await using AppDbContext ownerContext = Fixture.CreateContext(connectionString, owner);
        var ownerQueries = new InsightQueries(ownerContext, new TestUserContext(owner));
        ExerciseProgressSnapshot progress = await ownerQueries.ExerciseProgressAsync(exerciseId, null, ThroughUtc, Berlin, TestContext.CancellationToken);
        Assert.HasCount(1, progress.Points);
        Assert.AreEqual(100m, progress.Points[0].MaxWeightKg);
        Assert.AreEqual(100m, progress.Records.Current(RecordKind.MaxWeight)!.Value);
        Assert.AreEqual(116.67m, TrainingStatistics.RoundForOutput(progress.Records.Current(RecordKind.EstimatedOneRepMax)!.Value));
        Assert.AreEqual(5m, progress.Records.Current(RecordKind.MaxRepetitions)!.Value);

        DashboardInsightSnapshot dashboard = await ownerQueries.DashboardAsync(new DateOnly(2026, 8, 18), 7, Berlin, TestContext.CancellationToken);
        Assert.AreEqual(1, dashboard.Training.WorkoutCount);
        Assert.AreEqual(500m, dashboard.Training.VolumeKgRepetitions);
        Assert.IsFalse(dashboard.Training.BodyweightMissing);
    }

    [TestMethod]
    public async Task BodyweightComesFromTheOwnCheckInOnly()
    {
        (string connectionString, Guid owner, Guid other) = await CreateDatabaseAsync();
        Guid exerciseId = BaseExercise(ExerciseType.BodyweightLoaded);
        await using (AppDbContext seed = Fixture.CreateContext(connectionString, owner))
        {
            seed.DailyCheckIns.Add(CheckIn(new DateOnly(2026, 8, 17), 80m));
            AddFinishedWorkout(seed, exerciseId, ExerciseType.BodyweightLoaded, Utc(2026, 8, 18, 18), Utc(2026, 8, 18, 19), null, (10m, 5));
            await seed.SaveChangesAsync(TestContext.CancellationToken);
        }
        await using (AppDbContext seed = Fixture.CreateContext(connectionString, other))
        {
            seed.DailyCheckIns.Add(CheckIn(new DateOnly(2026, 8, 17), 100m));
            AddFinishedWorkout(seed, exerciseId, ExerciseType.BodyweightLoaded, Utc(2026, 8, 18, 18), Utc(2026, 8, 18, 19), null, (10m, 5));
            await seed.SaveChangesAsync(TestContext.CancellationToken);
        }

        await using AppDbContext ownerContext = Fixture.CreateContext(connectionString, owner);
        ExerciseProgressSnapshot ownerProgress = await new InsightQueries(ownerContext, new TestUserContext(owner))
            .ExerciseProgressAsync(exerciseId, null, ThroughUtc, Berlin, TestContext.CancellationToken);
        Assert.HasCount(1, ownerProgress.Points);
        Assert.AreEqual(105m, TrainingStatistics.RoundForOutput(ownerProgress.Points[0].EstimatedOneRepMaxKg!.Value));
        Assert.IsFalse(ownerProgress.Points[0].BodyweightMissing);

        await using AppDbContext otherContext = Fixture.CreateContext(connectionString, other);
        ExerciseProgressSnapshot otherProgress = await new InsightQueries(otherContext, new TestUserContext(other))
            .ExerciseProgressAsync(exerciseId, null, ThroughUtc, Berlin, TestContext.CancellationToken);
        Assert.AreEqual(128.33m, TrainingStatistics.RoundForOutput(otherProgress.Points[0].EstimatedOneRepMaxKg!.Value));
    }

    [TestMethod]
    public async Task MissingOwnCheckInFlagsBodyweightWithoutUsingForeignCheckIn()
    {
        (string connectionString, Guid owner, Guid other) = await CreateDatabaseAsync();
        Guid exerciseId = BaseExercise(ExerciseType.BodyweightOnly);
        await using (AppDbContext seed = Fixture.CreateContext(connectionString, other))
        {
            seed.DailyCheckIns.Add(CheckIn(new DateOnly(2026, 8, 17), 100m));
            await seed.SaveChangesAsync(TestContext.CancellationToken);
        }
        await using (AppDbContext seed = Fixture.CreateContext(connectionString, owner))
        {
            AddFinishedWorkout(seed, exerciseId, ExerciseType.BodyweightOnly, Utc(2026, 8, 18, 18), Utc(2026, 8, 18, 19), null, (null, 10));
            await seed.SaveChangesAsync(TestContext.CancellationToken);
        }

        await using AppDbContext ownerContext = Fixture.CreateContext(connectionString, owner);
        DashboardInsightSnapshot dashboard = await new InsightQueries(ownerContext, new TestUserContext(owner))
            .DashboardAsync(new DateOnly(2026, 8, 18), 7, Berlin, TestContext.CancellationToken);
        Assert.IsTrue(dashboard.Training.BodyweightMissing);
        Assert.AreEqual(0m, dashboard.Training.VolumeKgRepetitions);
    }

    [TestMethod]
    public async Task CoachReportsTheSameExerciseFiguresAsTheQuery()
    {
        (string connectionString, Guid owner, Guid other) = await CreateDatabaseAsync();
        Guid exerciseId = BaseExercise(ExerciseType.Strength);
        await using (AppDbContext seed = Fixture.CreateContext(connectionString, owner))
        {
            AddFinishedWorkout(seed, exerciseId, ExerciseType.Strength, Utc(2026, 8, 18, 18), Utc(2026, 8, 18, 19), null, (100m, 5), (90m, 8));
            await seed.SaveChangesAsync(TestContext.CancellationToken);
        }
        await using (AppDbContext seed = Fixture.CreateContext(connectionString, other))
        {
            AddFinishedWorkout(seed, exerciseId, ExerciseType.Strength, Utc(2026, 8, 18, 18), Utc(2026, 8, 18, 19), null, (500m, 5));
            await seed.SaveChangesAsync(TestContext.CancellationToken);
        }

        await using AppDbContext context = Fixture.CreateContext(connectionString, owner);
        var provider = new FakeProvider(
            Response(FunctionCall("call_1", "get_exercise_progress", $"{{\"exerciseId\":\"{exerciseId}\",\"days\":30}}")),
            Response(Message("""
                {"summary":"Die Übung entwickelt sich.","observations":[],"dataGaps":[],"suggestions":[]}
                """)));
        var coach = new CoachService(
            provider,
            new InsightQueries(context, new TestUserContext(owner)),
            new EmptyHistory(),
            new SingleExercise(exerciseId),
            new FixedTimeProvider(ThroughUtc));
        CoachAnswer answer = await coach.AnswerAsync("Wie entwickelt sich meine Übung?", TestContext.CancellationToken);

        ExerciseProgressSnapshot query = await new InsightQueries(context, new TestUserContext(owner))
            .ExerciseProgressAsync(exerciseId, 30, ThroughUtc, Berlin, TestContext.CancellationToken);
        decimal? coachBest = answer.Facts.Single(item => item.FactId == $"exercise:{exerciseId:N}:e1rm:30").NumericValue;
        decimal? coachRecord = answer.Facts.Single(item => item.FactId == $"exercise:{exerciseId:N}:record.e1rm").NumericValue;
        Assert.AreEqual(TrainingStatistics.RoundForOutput(query.BestSet!.EstimatedOneRepMaxKg), coachBest);
        Assert.AreEqual(
            TrainingStatistics.RoundForOutput(query.Records.Current(RecordKind.EstimatedOneRepMax)!.Value),
            coachRecord);
        Assert.AreEqual(116.67m, coachBest);
    }

    private static DateTime Utc(int year, int month, int day, int hour) => new(year, month, day, hour, 0, 0, DateTimeKind.Utc);

    private static void AddFinishedWorkout(
        AppDbContext context,
        Guid exerciseId,
        ExerciseType type,
        DateTime startedAtUtc,
        DateTime? endedAtUtc,
        DateTime? deletedAtUtc,
        params (decimal? Weight, int Repetitions)[] sets)
    {
        Guid workoutId = Guid.NewGuid();
        Guid workoutExerciseId = Guid.NewGuid();
        context.Workouts.Add(new Workout
        {
            Id = workoutId,
            Title = "Statistik",
            StartedAtUtc = startedAtUtc,
            EndedAtUtc = endedAtUtc,
            DeletedAtUtc = deletedAtUtc,
            PreviousValueSource = PreviousValueSource.Exercise,
            CreatedAtUtc = startedAtUtc,
            UpdatedAtUtc = startedAtUtc,
            Version = 1,
        });
        context.WorkoutExercises.Add(new WorkoutExercise
        {
            Id = workoutExerciseId,
            WorkoutId = workoutId,
            SourceExerciseId = exerciseId,
            ExerciseNameSnapshot = "Übung",
            ExerciseTypeSnapshot = type,
            Position = 0,
        });
        for (int i = 0; i < sets.Length; i++)
        {
            context.WorkoutSets.Add(new WorkoutSet
            {
                Id = Guid.NewGuid(),
                WorkoutId = workoutId,
                WorkoutExerciseId = workoutExerciseId,
                Position = i,
                SetType = WorkoutSetType.Normal,
                WeightKg = sets[i].Weight,
                Repetitions = sets[i].Repetitions,
            });
        }
    }

    /// <summary>Basiskatalog-Einträge aus der Migration (unveränderlich, ohne Schreibzugriff in den Tests).</summary>
    private static Guid BaseExercise(ExerciseType type) => type switch
    {
        ExerciseType.BodyweightLoaded => PullUp,
        ExerciseType.BodyweightOnly => PushUp,
        _ => BenchPress,
    };

    private static DailyCheckIn CheckIn(DateOnly date, decimal weight) => new()
    {
        Id = Guid.NewGuid(),
        LocalDate = date,
        WeightKg = weight,
        CreatedAtUtc = DateTime.UtcNow,
        UpdatedAtUtc = DateTime.UtcNow,
        Version = 1,
    };

    private static async Task<(string ConnectionString, Guid Owner, Guid Other)> CreateDatabaseAsync()
    {
        string connectionString = await Fixture.CreateIsolatedDatabaseAsync();
        Guid owner = Guid.NewGuid();
        Guid other = Guid.NewGuid();
        await using AppDbContext context = Fixture.CreateContext(connectionString);
        await context.Database.MigrateAsync();
        context.Users.AddRange(User(owner), User(other));
        await context.SaveChangesAsync();
        return (connectionString, owner, other);
    }

    private static AppUser User(Guid id) => new()
    {
        Id = id,
        UserName = $"{id:N}@example.test",
        NormalizedUserName = $"{id:N}@EXAMPLE.TEST",
        Email = $"{id:N}@example.test",
        NormalizedEmail = $"{id:N}@EXAMPLE.TEST",
        IsActive = true,
        SecurityStamp = Guid.NewGuid().ToString("N"),
        ConcurrencyStamp = Guid.NewGuid().ToString("N"),
    };

    private static JsonElement Response(params object[] output) => JsonSerializer.SerializeToElement(new { output });

    private static object FunctionCall(string callId, string name, string arguments) => new
    {
        type = "function_call",
        call_id = callId,
        name,
        arguments,
    };

    private static object Message(string text) => new
    {
        type = "message",
        content = new[] { new { type = "output_text", text } },
    };

    private sealed record TestUserContext(Guid? UserId) : IUserContext;

    private sealed class FakeProvider(params JsonElement[] responses) : IOpenAiResponsesProvider
    {
        private readonly Queue<JsonElement> responses = new(responses);

        public Task<JsonElement> CreateResponseAsync(JsonElement request, CancellationToken cancellationToken = default)
        {
            _ = request;
            _ = cancellationToken;
            return Task.FromResult(responses.Dequeue());
        }
    }

    private sealed class EmptyHistory : IWorkoutHistoryQueries
    {
        public Task<IReadOnlyList<WorkoutHistorySummary>> ListAsync(int offset, int limit, CancellationToken cancellationToken = default) =>
            Task.FromResult<IReadOnlyList<WorkoutHistorySummary>>([]);

        public Task<WorkoutSnapshot?> GetAsync(Guid workoutId, CancellationToken cancellationToken = default) =>
            Task.FromResult<WorkoutSnapshot?>(null);
    }

    private sealed class SingleExercise(Guid exerciseId) : IExerciseCatalogQueries
    {
        public Task<ExerciseCatalogPage> SearchAsync(ExerciseCatalogFilter filter, CancellationToken cancellationToken = default) =>
            Task.FromResult(new ExerciseCatalogPage(
                [new ExerciseCatalogItem(exerciseId, "Basisübung", null, null, null, null, false, "test-catalog", 1,
                    ExerciseType.Strength, null, null, null, [], [], [])],
                0, filter.Limit, 1, []));
    }

    private sealed class FixedTimeProvider(DateTime utcNow) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => new(DateTime.SpecifyKind(utcNow, DateTimeKind.Utc));
    }
}
