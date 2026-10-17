using System.Text.Json;
using Gainer.Core.Mutations;
using Gainer.Core.Security;
using Gainer.Core.Sync;
using Gainer.Core.Training;
using Gainer.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Gainer.IntegrationTests;

/// <summary>Two-user isolation matrix for the training sync operations: foreign and unknown identifiers must look identical.</summary>
[TestClass]
[DoNotParallelize]
public sealed class TrainingSyncIsolationTests
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private static PostgreSqlTestFixture? fixture;
    private static PostgreSqlTestFixture Fixture => fixture
        ?? throw new InvalidOperationException("The PostgreSQL fixture has not started.");

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
    public async Task ForeignWorkoutAndPlanOperationsAreRejectedLikeUnknownResources()
    {
        (string connectionString, Guid owner, Guid intruder, Guid ownerClient, Guid intruderClient) = await SetupAsync();
        Guid[] baseExercises = await BaseExerciseIdsAsync(connectionString, owner, 1);
        Guid planId = Guid.NewGuid();
        Guid workoutId = Guid.NewGuid();
        Guid entryId = Guid.NewGuid();
        Guid workoutExerciseId = Guid.NewGuid();
        Guid setId = Guid.NewGuid();
        DateTime started = new(2026, 8, 18, 17, 0, 0, DateTimeKind.Utc);

        await Run(connectionString, owner, ownerClient, Command(Guid.NewGuid(), ownerClient, 1, "createTrainingPlan", "TrainingPlan", planId, 0,
            new { plan = Plan(planId, entryId, baseExercises[0]) }));
        await Run(connectionString, owner, ownerClient, Command(Guid.NewGuid(), ownerClient, 2, "createWorkout", "Workout", workoutId, 0,
            new { workout = Workout(workoutId, started, null, baseExercises[0], workoutExerciseId, setId) }));

        // Foreign workout: save and delete look like an unknown workout.
        Guid unknownWorkout = Guid.NewGuid();
        SyncMutationConflictException foreignSave = await Expect<SyncMutationConflictException>(() => Run(connectionString, intruder, intruderClient,
            Command(Guid.NewGuid(), intruderClient, 1, "saveWorkout", "Workout", workoutId, 1,
                new { baseVersion = 1, workout = Workout(workoutId, started, started.AddHours(1), baseExercises[0], workoutExerciseId, setId) })));
        SyncMutationConflictException unknownSave = await Expect<SyncMutationConflictException>(() => Run(connectionString, intruder, intruderClient,
            Command(Guid.NewGuid(), intruderClient, 2, "saveWorkout", "Workout", unknownWorkout, 1,
                new { baseVersion = 1, workout = Workout(unknownWorkout, started, started.AddHours(1), baseExercises[0], workoutExerciseId, setId) })));
        Assert.AreEqual("resource_not_found", foreignSave.Code);
        Assert.AreEqual(unknownSave.Code, foreignSave.Code);
        Assert.AreEqual(unknownSave.Message, foreignSave.Message);

        SyncMutationConflictException foreignDelete = await Expect<SyncMutationConflictException>(() => Run(connectionString, intruder, intruderClient,
            Command(Guid.NewGuid(), intruderClient, 3, "deleteWorkout", "Workout", workoutId, 1, new { workoutId, baseVersion = 1 })));
        Assert.AreEqual("resource_not_found", foreignDelete.Code);

        // Foreign source plan and source workout: validation fields, same message as unknown identifiers.
        Guid newWorkout4 = Guid.NewGuid();
        Guid newWorkout5 = Guid.NewGuid();
        WorkoutValidationException foreignPlan = await Expect<WorkoutValidationException>(() => Run(connectionString, intruder, intruderClient,
            Command(Guid.NewGuid(), intruderClient, 4, "createWorkout", "Workout", newWorkout4, 0,
                new { workout = WithSource(Workout(newWorkout4, started, null, baseExercises[0], Guid.NewGuid(), Guid.NewGuid()), planId: planId) })));
        WorkoutValidationException unknownPlan = await Expect<WorkoutValidationException>(() => Run(connectionString, intruder, intruderClient,
            Command(Guid.NewGuid(), intruderClient, 5, "createWorkout", "Workout", newWorkout5, 0,
                new { workout = WithSource(Workout(newWorkout5, started, null, baseExercises[0], Guid.NewGuid(), Guid.NewGuid()), planId: Guid.NewGuid()) })));
        Assert.AreEqual(unknownPlan.Errors["SourcePlanId"], foreignPlan.Errors["SourcePlanId"]);

        Guid newWorkout6 = Guid.NewGuid();
        WorkoutValidationException foreignSource = await Expect<WorkoutValidationException>(() => Run(connectionString, intruder, intruderClient,
            Command(Guid.NewGuid(), intruderClient, 6, "createWorkout", "Workout", newWorkout6, 0,
                new { workout = WithSource(Workout(newWorkout6, started, null, baseExercises[0], Guid.NewGuid(), Guid.NewGuid()), sourceWorkoutId: workoutId) })));
        Assert.IsTrue(foreignSource.Errors.ContainsKey("SourceWorkoutId"));

        // Own exercise of another user: same message as an unknown exercise.
        Guid ownerCustom = await CreateCustomExerciseAsync(connectionString, owner, "Owner only");
        Guid newWorkout7 = Guid.NewGuid();
        Guid newWorkout8 = Guid.NewGuid();
        WorkoutValidationException foreignExercise = await Expect<WorkoutValidationException>(() => Run(connectionString, intruder, intruderClient,
            Command(Guid.NewGuid(), intruderClient, 7, "createWorkout", "Workout", newWorkout7, 0,
                new { workout = Workout(newWorkout7, started, null, ownerCustom, Guid.NewGuid(), Guid.NewGuid()) })));
        WorkoutValidationException unknownExercise = await Expect<WorkoutValidationException>(() => Run(connectionString, intruder, intruderClient,
            Command(Guid.NewGuid(), intruderClient, 8, "createWorkout", "Workout", newWorkout8, 0,
                new { workout = Workout(newWorkout8, started, null, Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid()) })));
        Assert.AreEqual(unknownExercise.Errors["Exercises.SourceExerciseId"], foreignExercise.Errors["Exercises.SourceExerciseId"]);

        // The owner's data stays untouched.
        await using AppDbContext check = Fixture.CreateContext(connectionString, owner);
        Assert.IsNull((await check.Workouts.SingleAsync()).EndedAtUtc);
        Assert.AreEqual(0, await check.Workouts.CountAsync(item => item.Title == "Stolen"));
    }

    [TestMethod]
    public async Task ForeignPlanRotationAndReorderOperationsAreRejected()
    {
        (string connectionString, Guid owner, Guid intruder, Guid ownerClient, Guid intruderClient) = await SetupAsync();
        Guid[] baseExercises = await BaseExerciseIdsAsync(connectionString, owner, 1);
        Guid planId = Guid.NewGuid();
        Guid rotationId = Guid.NewGuid();
        Guid foreignRotationId = Guid.NewGuid();
        await Run(connectionString, owner, ownerClient, Command(Guid.NewGuid(), ownerClient, 1, "createTrainingPlan", "TrainingPlan", planId, 0,
            new { plan = Plan(planId, Guid.NewGuid(), baseExercises[0]) }));
        await Run(connectionString, owner, ownerClient, Command(Guid.NewGuid(), ownerClient, 2, "saveWorkoutRotation", "WorkoutRotation", rotationId, 0,
            new { rotationId, baseVersion = 0, planIds = new[] { planId } }));

        SyncMutationConflictException foreignUpdate = await Expect<SyncMutationConflictException>(() => Run(connectionString, intruder, intruderClient,
            Command(Guid.NewGuid(), intruderClient, 1, "updateTrainingPlan", "TrainingPlan", planId, 1,
                new { baseVersion = 1, plan = Plan(planId, Guid.NewGuid(), baseExercises[0]) })));
        Guid unknownPlanId = Guid.NewGuid();
        SyncMutationConflictException unknownUpdate = await Expect<SyncMutationConflictException>(() => Run(connectionString, intruder, intruderClient,
            Command(Guid.NewGuid(), intruderClient, 2, "updateTrainingPlan", "TrainingPlan", unknownPlanId, 1,
                new { baseVersion = 1, plan = Plan(unknownPlanId, Guid.NewGuid(), baseExercises[0]) })));
        Assert.AreEqual("resource_not_found", foreignUpdate.Code);
        Assert.AreEqual(unknownUpdate.Code, foreignUpdate.Code);

        SyncMutationConflictException foreignArchive = await Expect<SyncMutationConflictException>(() => Run(connectionString, intruder, intruderClient,
            Command(Guid.NewGuid(), intruderClient, 3, "archiveTrainingPlan", "TrainingPlan", planId, 1, new { planId, baseVersion = 1 })));
        Assert.AreEqual("resource_not_found", foreignArchive.Code);

        SyncMutationConflictException foreignReorder = await Expect<SyncMutationConflictException>(() => Run(connectionString, intruder, intruderClient,
            Command(Guid.NewGuid(), intruderClient, 4, "reorderTrainingPlans", "TrainingPlan", planId, 1,
                new { plans = new[] { new { planId, baseVersion = 1 } } })));
        Assert.AreEqual("resource_not_found", foreignReorder.Code);

        SyncMutationConflictException foreignRotation = await Expect<SyncMutationConflictException>(() => Run(connectionString, intruder, intruderClient,
            Command(Guid.NewGuid(), intruderClient, 5, "saveWorkoutRotation", "WorkoutRotation", rotationId, 1,
                new { rotationId, baseVersion = 1, planIds = Array.Empty<Guid>() })));
        Assert.AreEqual("resource_not_found", foreignRotation.Code);

        WorkoutRotationValidationException intruderRotation = await Expect<WorkoutRotationValidationException>(() => Run(connectionString, intruder, intruderClient,
            Command(Guid.NewGuid(), intruderClient, 6, "saveWorkoutRotation", "WorkoutRotation", foreignRotationId, 0,
                new { rotationId = foreignRotationId, baseVersion = 0, planIds = new[] { planId } })));
        Assert.IsTrue(intruderRotation.Errors.ContainsKey("PlanIds"));

        await using AppDbContext check = Fixture.CreateContext(connectionString, owner);
        Assert.AreEqual("Push", (await check.TrainingPlans.SingleAsync()).Name);
    }

    [TestMethod]
    public async Task SecondActiveWorkoutThroughSyncReturnsActiveWorkoutExistsConflict()
    {
        (string connectionString, Guid owner, _, Guid ownerClient, _) = await SetupAsync();
        Guid[] baseExercises = await BaseExerciseIdsAsync(connectionString, owner, 1);
        DateTime started = new(2026, 8, 18, 17, 0, 0, DateTimeKind.Utc);
        Guid first = Guid.NewGuid();
        Guid second = Guid.NewGuid();
        await Run(connectionString, owner, ownerClient, Command(Guid.NewGuid(), ownerClient, 1, "createWorkout", "Workout", first, 0,
            new { workout = Workout(first, started, null, baseExercises[0], Guid.NewGuid(), Guid.NewGuid()) }));

        SyncMutationConflictException conflict = await Expect<SyncMutationConflictException>(() => Run(connectionString, owner, ownerClient,
            Command(Guid.NewGuid(), ownerClient, 2, "createWorkout", "Workout", second, 0,
                new { workout = Workout(second, started.AddHours(20), null, baseExercises[0], Guid.NewGuid(), Guid.NewGuid()) })));
        Assert.AreEqual("active_workout_exists", conflict.Code);
    }

    private static async Task Run(string connectionString, Guid userId, Guid clientId, ProcessSyncMutationCommand command)
    {
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        var user = new CurrentUser(userId);
        var processor = new SyncMutationProcessor(context, user, new SyncMutationExecutor(context, user, TimeProvider.System), TimeProvider.System);
        await processor.ProcessAsync(command);
    }

    private static async Task<T> Expect<T>(Func<Task> operation) where T : Exception
    {
        return await Assert.ThrowsAsync<T>(operation);
    }

    private static ProcessSyncMutationCommand Command(
        Guid mutationId,
        Guid clientId,
        long sequence,
        string operation,
        string resourceType,
        Guid resourceId,
        long baseVersion,
        object payload) =>
        new(
            mutationId,
            new CanonicalMutationContent(
                2,
                clientId,
                sequence,
                operation,
                [new CanonicalResourceVersion(resourceType, resourceId, baseVersion)],
                null,
                JsonSerializer.SerializeToElement(payload, JsonOptions)));

    private static object Plan(Guid planId, Guid entryId, Guid exerciseId) => new
    {
        planId,
        name = "Push",
        notes = (string?)null,
        previousValueSource = "exercise",
        entries = new[]
        {
            new { entryId, exerciseId, warmupSets = 0, workingSets = 3, notes = (string?)null, supersetId = (Guid?)null },
        },
    };

    private static object Workout(Guid workoutId, DateTime started, DateTime? ended, Guid exerciseId, Guid workoutExerciseId, Guid setId) => new
    {
        workoutId,
        title = "Push",
        notes = (string?)null,
        startedAtUtc = started,
        endedAtUtc = ended,
        previousValueSource = "exercise",
        sourcePlanId = (Guid?)null,
        sourceWorkoutId = (Guid?)null,
        exercises = new[]
        {
            new
            {
                workoutExerciseId,
                sourceExerciseId = exerciseId,
                exerciseNameSnapshot = "Bench",
                exerciseTypeSnapshot = "strength",
                notes = (string?)null,
                supersetId = (Guid?)null,
                sets = new[]
                {
                    new { setId, setType = "normal", weightKg = (decimal?)100, repetitions = (int?)8, rir = (decimal?)null, notes = (string?)null },
                },
            },
        },
    };

    private static object WithSource(object workout, Guid? planId = null, Guid? sourceWorkoutId = null)
    {
        JsonElement element = JsonSerializer.SerializeToElement(workout, JsonOptions);
        var node = System.Text.Json.Nodes.JsonNode.Parse(element.GetRawText())!.AsObject();
        if (planId is { } plan) node["sourcePlanId"] = plan;
        if (sourceWorkoutId is { } source) node["sourceWorkoutId"] = source;
        return node;
    }

    private static async Task<(string ConnectionString, Guid Owner, Guid Intruder, Guid OwnerClient, Guid IntruderClient)> SetupAsync()
    {
        string connectionString = await Fixture.CreateIsolatedDatabaseAsync();
        Guid owner = Guid.NewGuid();
        Guid intruder = Guid.NewGuid();
        Guid ownerClient = Guid.NewGuid();
        Guid intruderClient = Guid.NewGuid();
        await using (AppDbContext context = Fixture.CreateContext(connectionString))
        {
            await context.Database.MigrateAsync();
            context.Users.AddRange(User(owner), User(intruder));
            await context.SaveChangesAsync();
        }
        await RegisterClientAsync(connectionString, owner, ownerClient);
        await RegisterClientAsync(connectionString, intruder, intruderClient);
        return (connectionString, owner, intruder, ownerClient, intruderClient);
    }

    private static async Task RegisterClientAsync(string connectionString, Guid userId, Guid clientId)
    {
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        context.SyncClients.Add(new SyncClient
        {
            Id = clientId,
            DisplayName = "Test device",
            ProtocolVersion = 2,
            RegisteredAtUtc = DateTime.UtcNow,
            LastSeenAtUtc = DateTime.UtcNow,
        });
        context.UserSyncStates.Add(new UserSyncState
        {
            CurrentRevision = 0,
            ActiveClientId = clientId,
            UpdatedAtUtc = DateTime.UtcNow,
            Version = 1,
        });
        await context.SaveChangesAsync();
    }

    private static async Task<Guid> CreateCustomExerciseAsync(string connectionString, Guid userId, string name)
    {
        Guid id = Guid.NewGuid();
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        context.Exercises.Add(new Exercise
        {
            Id = id,
            OwnerUserId = userId,
            Name = name,
            ExerciseType = ExerciseType.Strength,
            CreatedAtUtc = DateTime.UtcNow,
            UpdatedAtUtc = DateTime.UtcNow,
            Version = 1,
        });
        await context.SaveChangesAsync();
        return id;
    }

    private static async Task<Guid[]> BaseExerciseIdsAsync(string connectionString, Guid userId, int count)
    {
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        return await context.Exercises.Where(item => item.OwnerUserId == null)
            .OrderBy(item => item.Id).Select(item => item.Id).Take(count).ToArrayAsync();
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

    private sealed record CurrentUser(Guid Value) : IUserContext
    {
        Guid? IUserContext.UserId => Value;
    }
}
