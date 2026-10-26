using System.Text.Json;
using Gainer.Contracts.Sync;
using Gainer.Core.BodyTracking;
using Gainer.Core.Security;
using Gainer.Core.Sync;
using Gainer.Core.Training;
using Gainer.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Gainer.IntegrationTests;

/// <summary>Base versions and replays of workouts, training plans and body goals through the sync processor.</summary>
[TestClass]
[DoNotParallelize]
public sealed class SyncBaseVersionAndReplayTests
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private static readonly DateTimeOffset ServerNow = new(2026, 10, 25, 9, 0, 0, TimeSpan.Zero);
    private static readonly DateOnly Day = new(2026, 10, 25);
    private static readonly DateTime Started = new(2026, 10, 24, 17, 0, 0, DateTimeKind.Utc);
    private static PostgreSqlTestFixture? fixture;
    private static PostgreSqlTestFixture Fixture => fixture ?? throw new InvalidOperationException("PostgreSQL is not started.");

    public TestContext TestContext { get; set; } = null!;

    [ClassInitialize]
    public static async Task StartPostgreSqlAsync(TestContext context)
    {
        _ = context;
        fixture = new PostgreSqlTestFixture();
        await fixture.StartAsync();
    }

    [ClassCleanup]
    public static async Task StopPostgreSqlAsync()
    {
        if (fixture is not null) await fixture.DisposeAsync();
    }

    [TestMethod]
    public async Task WorkoutSavedFromAStaleBaseVersionIsStaleBaseVersion()
    {
        (string connectionString, Guid user, Guid client) = await SetupAsync();
        Guid workoutId = Guid.NewGuid();
        await Apply(connectionString, user, client, 1,
            Command("createWorkout", "Workout", workoutId, 0, new { workout = Workout(workoutId, "Push") }));
        await Apply(connectionString, user, client, 2,
            Command("saveWorkout", "Workout", workoutId, 1, new { baseVersion = 1, workout = Workout(workoutId, "Push 2") }));

        await ExpectStale(connectionString, user, client, 3,
            Command("saveWorkout", "Workout", workoutId, 1, new { baseVersion = 1, workout = Workout(workoutId, "Stale") }));
        await ExpectStale(connectionString, user, client, 3,
            Command("deleteWorkout", "Workout", workoutId, 1, new { workoutId, baseVersion = 1 }));

        await using AppDbContext context = Fixture.CreateContext(connectionString, user);
        Workout stored = await context.Workouts.SingleAsync(TestContext.CancellationToken);
        Assert.AreEqual("Push 2", stored.Title);
        Assert.AreEqual(2, stored.Version);
        Assert.IsNull(stored.DeletedAtUtc);
    }

    [TestMethod]
    public async Task TrainingPlanCreateAndUpdateReplayWithoutSideEffects()
    {
        (string connectionString, Guid user, Guid client) = await SetupAsync();
        Guid exerciseId = await BaseExerciseIdAsync(connectionString, user);
        Guid planId = Guid.NewGuid();
        ProcessSyncMutationCommand create = For(
            Command("createTrainingPlan", "TrainingPlan", planId, 0, new { plan = Plan(planId, "Push", exerciseId, Guid.NewGuid()) }), client, 1);
        ProcessSyncMutationCommand update = For(
            Command("updateTrainingPlan", "TrainingPlan", planId, 1, new { baseVersion = 1, plan = Plan(planId, "Push A", exerciseId, Guid.NewGuid()) }), client, 2);

        await using AppDbContext context = Fixture.CreateContext(connectionString, user);
        SyncMutationProcessor processor = Processor(context, user);
        Assert.IsFalse((await processor.ProcessAsync(create, TestContext.CancellationToken)).Replayed);
        Assert.IsTrue((await processor.ProcessAsync(create, TestContext.CancellationToken)).Replayed);
        Assert.IsFalse((await processor.ProcessAsync(update, TestContext.CancellationToken)).Replayed);
        Assert.IsTrue((await processor.ProcessAsync(update, TestContext.CancellationToken)).Replayed);

        context.ChangeTracker.Clear();
        TrainingPlan stored = await context.TrainingPlans.SingleAsync(TestContext.CancellationToken);
        Assert.AreEqual("Push A", stored.Name);
        Assert.AreEqual(2, stored.Version);
        Assert.AreEqual(1, await context.TrainingPlanEntries.CountAsync(TestContext.CancellationToken));
        Assert.AreEqual(2, await context.ProcessedMutations.CountAsync(TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task TrainingPlanUpdateWithWrongVersionOnActivePlanIsStaleBaseVersion()
    {
        (string connectionString, Guid user, Guid client) = await SetupAsync();
        Guid exerciseId = await BaseExerciseIdAsync(connectionString, user);
        Guid planId = Guid.NewGuid();
        await Apply(connectionString, user, client, 1,
            Command("createTrainingPlan", "TrainingPlan", planId, 0, new { plan = Plan(planId, "Push", exerciseId, Guid.NewGuid()) }));

        await ExpectStale(connectionString, user, client, 2,
            Command("updateTrainingPlan", "TrainingPlan", planId, 5, new { baseVersion = 5, plan = Plan(planId, "Wrong", exerciseId, Guid.NewGuid()) }));
        await ExpectStale(connectionString, user, client, 2,
            Command("createTrainingPlan", "TrainingPlan", planId, 0, new { plan = Plan(planId, "Again", exerciseId, Guid.NewGuid()) }));

        await using AppDbContext context = Fixture.CreateContext(connectionString, user);
        TrainingPlan stored = await context.TrainingPlans.SingleAsync(TestContext.CancellationToken);
        Assert.AreEqual("Push", stored.Name);
        Assert.AreEqual(1, stored.Version);
        Assert.IsFalse(stored.IsArchived);
    }

    [TestMethod]
    public async Task ActivateBodyGoalRunsThroughSyncReplaysAndDetectsStaleExpectations()
    {
        (string connectionString, Guid user, Guid client) = await SetupAsync();
        Guid firstGoal = Guid.NewGuid();
        Guid secondGoal = Guid.NewGuid();
        ProcessSyncMutationCommand activate = For(ActivateGoal(firstGoal, null, null), client, 1);

        await using (AppDbContext context = Fixture.CreateContext(connectionString, user))
        {
            SyncMutationProcessor processor = Processor(context, user);
            ProcessedSyncMutationResult applied = await processor.ProcessAsync(activate, TestContext.CancellationToken);
            Assert.IsFalse(applied.Replayed);
            Assert.HasCount(1, applied.Changes);
            Assert.IsTrue((await processor.ProcessAsync(activate, TestContext.CancellationToken)).Replayed);
            context.ChangeTracker.Clear();
            Assert.AreEqual(1, await context.BodyGoals.CountAsync(TestContext.CancellationToken));
        }

        // Expecting no active goal is stale now, and so is a wrong expected version.
        await ExpectStale(connectionString, user, client, 2, ActivateGoal(secondGoal, null, null));
        await ExpectStale(connectionString, user, client, 2, ActivateGoal(secondGoal, firstGoal, 7));
        await using (AppDbContext context = Fixture.CreateContext(connectionString, user))
        {
            Assert.IsNull((await context.BodyGoals.SingleAsync(TestContext.CancellationToken)).EndedAtUtc);
        }

        // The matching expectation ends the first goal and activates the second.
        await Apply(connectionString, user, client, 2, ActivateGoal(secondGoal, firstGoal, 1));
        await using (AppDbContext context = Fixture.CreateContext(connectionString, user))
        {
            List<BodyGoal> goals = await context.BodyGoals.AsNoTracking().OrderBy(item => item.CreatedAtUtc).ToListAsync(TestContext.CancellationToken);
            Assert.HasCount(2, goals);
            Assert.IsNotNull(goals.Single(item => item.Id == firstGoal).EndedAtUtc);
            Assert.AreEqual(2, goals.Single(item => item.Id == firstGoal).Version);
            Assert.IsNull(goals.Single(item => item.Id == secondGoal).EndedAtUtc);
        }
    }

    private static ProcessSyncMutationCommand ActivateGoal(Guid goalId, Guid? expectedId, long? expectedVersion)
    {
        var resources = new List<CanonicalResourceVersion> { new("BodyGoal", goalId, 0) };
        if (expectedId is { } id && expectedVersion is { } version) resources.Add(new CanonicalResourceVersion("BodyGoal", id, version));
        return new ProcessSyncMutationCommand(
            Guid.NewGuid(),
            new CanonicalMutationContent(
                SyncProtocol.CurrentVersion, Guid.Empty, 0, "activateBodyGoal", resources, null,
                JsonSerializer.SerializeToElement(new
                {
                    goalId,
                    kind = "Cut",
                    startWeightKg = 85m,
                    targetWeightKg = 80m,
                    startDate = Day,
                    targetDate = (DateOnly?)null,
                    expectedActiveGoalId = expectedId,
                    expectedActiveGoalVersion = expectedVersion,
                }, JsonOptions)));
    }

    private static object Workout(Guid workoutId, string title) => new
    {
        workoutId,
        title,
        notes = (string?)null,
        startedAtUtc = Started,
        endedAtUtc = Started.AddHours(1),
        previousValueSource = "exercise",
        sourcePlanId = (Guid?)null,
        sourceWorkoutId = (Guid?)null,
        exercises = Array.Empty<object>(),
    };

    private static object Plan(Guid planId, string name, Guid exerciseId, Guid entryId) => new
    {
        planId,
        name,
        notes = (string?)null,
        previousValueSource = "exercise",
        entries = new[]
        {
            new { entryId, exerciseId, warmupSets = 1, workingSets = 3, notes = (string?)null, supersetId = (Guid?)null },
        },
    };

    private static ProcessSyncMutationCommand Command(
        string operation, string resourceType, Guid resourceId, long baseVersion, object payload) => new(
            Guid.NewGuid(),
            new CanonicalMutationContent(
                SyncProtocol.CurrentVersion,
                Guid.Empty,
                0,
                operation,
                [new CanonicalResourceVersion(resourceType, resourceId, baseVersion)],
                null,
                JsonSerializer.SerializeToElement(payload, JsonOptions)));

    private static ProcessSyncMutationCommand For(ProcessSyncMutationCommand command, Guid client, long sequence) =>
        command with { Content = command.Content with { ClientId = client, ClientSequence = sequence } };

    private static async Task Apply(string connectionString, Guid user, Guid client, long sequence, ProcessSyncMutationCommand command)
    {
        await using AppDbContext context = Fixture.CreateContext(connectionString, user);
        _ = await Processor(context, user).ProcessAsync(For(command, client, sequence));
    }

    private static async Task ExpectStale(string connectionString, Guid user, Guid client, long sequence, ProcessSyncMutationCommand command)
    {
        await using AppDbContext context = Fixture.CreateContext(connectionString, user);
        SyncMutationConflictException conflict = await Assert.ThrowsExactlyAsync<SyncMutationConflictException>(() =>
            Processor(context, user).ProcessAsync(For(command, client, sequence)));
        Assert.AreEqual("stale_base_version", conflict.Code);
    }

    private static SyncMutationProcessor Processor(AppDbContext context, Guid userId)
    {
        var user = new UserContext(userId);
        var time = new FixedTimeProvider(ServerNow);
        return new SyncMutationProcessor(context, user, new SyncMutationExecutor(context, user, time), time);
    }

    private static async Task<Guid> BaseExerciseIdAsync(string connectionString, Guid userId)
    {
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        return await context.Exercises.Where(item => item.OwnerUserId == null)
            .OrderBy(item => item.Id).Select(item => item.Id).FirstAsync();
    }

    private static async Task<(string ConnectionString, Guid User, Guid Client)> SetupAsync()
    {
        string connectionString = await Fixture.CreateIsolatedDatabaseAsync();
        Guid user = Guid.NewGuid();
        Guid client = Guid.NewGuid();
        await using (AppDbContext context = Fixture.CreateContext(connectionString))
        {
            await context.Database.MigrateAsync();
            context.Users.Add(User(user));
            await context.SaveChangesAsync();
        }
        await using (AppDbContext context = Fixture.CreateContext(connectionString, user))
        {
            context.SyncClients.Add(new SyncClient
            {
                Id = client,
                DisplayName = "Base version test",
                ProtocolVersion = SyncProtocol.CurrentVersion,
                RegisteredAtUtc = DateTime.UtcNow,
                LastSeenAtUtc = DateTime.UtcNow,
            });
            context.UserSyncStates.Add(new UserSyncState
            {
                CurrentRevision = 0,
                ActiveClientId = client,
                UpdatedAtUtc = DateTime.UtcNow,
                Version = 1,
            });
            await context.SaveChangesAsync();
        }
        return (connectionString, user, client);
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

    private sealed record UserContext(Guid Value) : IUserContext
    {
        Guid? IUserContext.UserId => Value;
    }

    private sealed class FixedTimeProvider(DateTimeOffset utcNow) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => utcNow;
    }
}
