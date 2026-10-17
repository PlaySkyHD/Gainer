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
    public TestContext TestContext { get; set; } = null!;

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
        Assert.IsNull((await check.Workouts.SingleAsync(TestContext.CancellationToken)).EndedAtUtc);
        Assert.AreEqual(0, await check.Workouts.CountAsync(item => item.Title == "Stolen", TestContext.CancellationToken));
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
        Assert.AreEqual("Push", (await check.TrainingPlans.SingleAsync(TestContext.CancellationToken)).Name);
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

    [TestMethod]
    public async Task MergingDuplicateExerciseRepointsOwnWorkoutsAndPlanAndArchivesSource()
    {
        (string connectionString, Guid owner, _, Guid ownerClient, _) = await SetupAsync();
        Guid targetId = (await BaseExerciseIdsAsync(connectionString, owner, 1))[0];
        Guid sourceId = Guid.NewGuid();
        Guid planId = Guid.NewGuid();
        DateTime started = new(2026, 8, 18, 17, 0, 0, DateTimeKind.Utc);
        await Run(connectionString, owner, ownerClient, CreateExerciseCommand(ownerClient, 1, sourceId, "Bankdrücken LH"));
        Guid firstWorkout = Guid.NewGuid();
        Guid secondWorkout = Guid.NewGuid();
        await Run(connectionString, owner, ownerClient, Command(Guid.NewGuid(), ownerClient, 2, "createWorkout", "Workout", firstWorkout, 0,
            new { workout = Workout(firstWorkout, started, started.AddHours(1), sourceId, Guid.NewGuid(), Guid.NewGuid()) }));
        await Run(connectionString, owner, ownerClient, Command(Guid.NewGuid(), ownerClient, 3, "createWorkout", "Workout", secondWorkout, 0,
            new { workout = Workout(secondWorkout, started.AddDays(1), started.AddDays(1).AddHours(1), sourceId, Guid.NewGuid(), Guid.NewGuid()) }));
        await Run(connectionString, owner, ownerClient, Command(Guid.NewGuid(), ownerClient, 4, "createTrainingPlan", "TrainingPlan", planId, 0,
            new { plan = Plan(planId, Guid.NewGuid(), sourceId) }));

        ProcessedSyncMutationResult merged = await Process(connectionString, owner, ownerClient,
            MergeCommand(Guid.NewGuid(), ownerClient, 5, sourceId, 1, targetId, targetVersion: null));

        await using AppDbContext check = Fixture.CreateContext(connectionString, owner);
        Assert.AreEqual(2, await check.WorkoutExercises.CountAsync(item => item.SourceExerciseId == targetId, TestContext.CancellationToken));
        Assert.AreEqual(0, await check.WorkoutExercises.CountAsync(item => item.SourceExerciseId == sourceId, TestContext.CancellationToken));
        Assert.IsTrue(await check.WorkoutExercises.AllAsync(item => item.ExerciseNameSnapshot == "Bench", TestContext.CancellationToken));
        Assert.AreEqual(2, await check.Workouts.CountAsync(item => item.Version == 2, TestContext.CancellationToken));
        TrainingPlan plan = await check.TrainingPlans.SingleAsync(TestContext.CancellationToken);
        Assert.AreEqual(2, plan.Version);
        Assert.AreEqual(targetId, (await check.TrainingPlanEntries.SingleAsync(TestContext.CancellationToken)).ExerciseId);
        Exercise source = await check.Exercises.SingleAsync(item => item.Id == sourceId, TestContext.CancellationToken);
        Assert.IsTrue(source.IsArchived);
        Assert.AreEqual(2, source.Version);
        Assert.AreEqual("Bankdrücken LH", source.Name);

        Assert.HasCount(4, merged.Changes);
        Assert.AreEqual(2, merged.Changes.Count(change => change.Resource.Kind == ResourceKind.Workout && change.Version == 2 && change.Snapshot is not null));
        Assert.AreEqual(1, merged.Changes.Count(change => change.Resource.Kind == ResourceKind.TrainingPlan && change.Version == 2 && change.Snapshot is not null));
        Assert.AreEqual(1, merged.Changes.Count(change => change.Resource.Kind == ResourceKind.CustomExercise && change.Version == 2 && change.Snapshot is not null));
    }

    [TestMethod]
    public async Task RepeatedMergeMutationAppliesExactlyOnce()
    {
        (string connectionString, Guid owner, _, Guid ownerClient, _) = await SetupAsync();
        Guid targetId = (await BaseExerciseIdsAsync(connectionString, owner, 1))[0];
        Guid sourceId = Guid.NewGuid();
        Guid workoutId = Guid.NewGuid();
        DateTime started = new(2026, 8, 18, 17, 0, 0, DateTimeKind.Utc);
        await Run(connectionString, owner, ownerClient, CreateExerciseCommand(ownerClient, 1, sourceId, "Bankdrücken LH"));
        await Run(connectionString, owner, ownerClient, Command(Guid.NewGuid(), ownerClient, 2, "createWorkout", "Workout", workoutId, 0,
            new { workout = Workout(workoutId, started, started.AddHours(1), sourceId, Guid.NewGuid(), Guid.NewGuid()) }));

        Guid mutationId = Guid.NewGuid();
        ProcessSyncMutationCommand command = MergeCommand(mutationId, ownerClient, 3, sourceId, 1, targetId, targetVersion: null);
        ProcessedSyncMutationResult first = await Process(connectionString, owner, ownerClient, command);
        ProcessedSyncMutationResult replay = await Process(connectionString, owner, ownerClient, command);

        Assert.IsFalse(first.Replayed);
        Assert.IsTrue(replay.Replayed);
        Assert.AreEqual(first.Revision, replay.Revision);
        await using AppDbContext check = Fixture.CreateContext(connectionString, owner);
        Assert.AreEqual(2, (await check.Workouts.SingleAsync(TestContext.CancellationToken)).Version);
        Assert.AreEqual(2, (await check.Exercises.SingleAsync(item => item.Id == sourceId, TestContext.CancellationToken)).Version);
        Assert.AreEqual(1, await check.ChangeBatches.CountAsync(item => item.MutationId == mutationId, TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task MergeRejectsForeignUnknownBaseAndIdenticalExercisesWithoutChanges()
    {
        (string connectionString, Guid owner, Guid intruder, Guid ownerClient, Guid intruderClient) = await SetupAsync();
        Guid targetId = (await BaseExerciseIdsAsync(connectionString, owner, 1))[0];
        Guid ownerSource = Guid.NewGuid();
        Guid intruderSource = Guid.NewGuid();
        await Run(connectionString, owner, ownerClient, CreateExerciseCommand(ownerClient, 1, ownerSource, "Owner only"));
        await Run(connectionString, intruder, intruderClient, CreateExerciseCommand(intruderClient, 1, intruderSource, "Intruder only"));

        SyncMutationConflictException foreignTarget = await Expect<SyncMutationConflictException>(() => Process(connectionString, intruder, intruderClient,
            MergeCommand(Guid.NewGuid(), intruderClient, 2, intruderSource, 1, ownerSource, targetVersion: 1)));
        SyncMutationConflictException unknownTarget = await Expect<SyncMutationConflictException>(() => Process(connectionString, intruder, intruderClient,
            MergeCommand(Guid.NewGuid(), intruderClient, 3, intruderSource, 1, Guid.NewGuid(), targetVersion: null)));
        Assert.AreEqual("resource_not_found", foreignTarget.Code);
        Assert.AreEqual(unknownTarget.Code, foreignTarget.Code);
        Assert.AreEqual(unknownTarget.Message, foreignTarget.Message);

        SyncMutationConflictException foreignSource = await Expect<SyncMutationConflictException>(() => Process(connectionString, intruder, intruderClient,
            MergeCommand(Guid.NewGuid(), intruderClient, 4, ownerSource, 1, intruderSource, targetVersion: 1)));
        Assert.AreEqual("resource_not_found", foreignSource.Code);

        SyncMutationConflictException baseSource = await Expect<SyncMutationConflictException>(() => Process(connectionString, owner, ownerClient,
            MergeCommand(Guid.NewGuid(), ownerClient, 2, targetId, 1, ownerSource, targetVersion: 1)));
        Assert.AreEqual("resource_not_found", baseSource.Code);

        SyncMutationValidationException identical = await Expect<SyncMutationValidationException>(() => Process(connectionString, owner, ownerClient,
            MergeCommand(Guid.NewGuid(), ownerClient, 3, ownerSource, 1, ownerSource, targetVersion: 1)));
        Assert.AreEqual("invalid_merge", identical.Code);

        await using AppDbContext check = Fixture.CreateContext(connectionString, owner);
        Exercise unchanged = await check.Exercises.SingleAsync(item => item.Id == ownerSource, TestContext.CancellationToken);
        Assert.IsFalse(unchanged.IsArchived);
        Assert.AreEqual(1, unchanged.Version);
    }

    [TestMethod]
    public async Task MergeIntoOwnTargetRequiresCurrentTargetVersion()
    {
        (string connectionString, Guid owner, _, Guid ownerClient, _) = await SetupAsync();
        Guid sourceId = Guid.NewGuid();
        Guid targetId = Guid.NewGuid();
        await Run(connectionString, owner, ownerClient, CreateExerciseCommand(ownerClient, 1, sourceId, "Bankdrücken LH"));
        await Run(connectionString, owner, ownerClient, CreateExerciseCommand(ownerClient, 2, targetId, "Bankdrücken"));

        SyncMutationConflictException staleTarget = await Expect<SyncMutationConflictException>(() => Process(connectionString, owner, ownerClient,
            MergeCommand(Guid.NewGuid(), ownerClient, 3, sourceId, 1, targetId, targetVersion: 5)));
        SyncMutationConflictException missingTarget = await Expect<SyncMutationConflictException>(() => Process(connectionString, owner, ownerClient,
            MergeCommand(Guid.NewGuid(), ownerClient, 4, sourceId, 1, targetId, targetVersion: null)));
        Assert.AreEqual("stale_base_version", staleTarget.Code);
        Assert.AreEqual("stale_base_version", missingTarget.Code);

        ProcessedSyncMutationResult merged = await Process(connectionString, owner, ownerClient,
            MergeCommand(Guid.NewGuid(), ownerClient, 5, sourceId, 1, targetId, targetVersion: 1));
        Assert.IsTrue(merged.Changes.All(change => change.Resource.ResourceId != targetId));
        await using AppDbContext check = Fixture.CreateContext(connectionString, owner);
        Assert.IsTrue((await check.Exercises.SingleAsync(item => item.Id == sourceId, TestContext.CancellationToken)).IsArchived);
        Assert.AreEqual(1, (await check.Exercises.SingleAsync(item => item.Id == targetId, TestContext.CancellationToken)).Version);
    }

    [TestMethod]
    public async Task MergeLeavesOtherUsersDataWithTheSameBaseExerciseUnchanged()
    {
        (string connectionString, Guid owner, Guid intruder, Guid ownerClient, Guid intruderClient) = await SetupAsync();
        Guid targetId = (await BaseExerciseIdsAsync(connectionString, owner, 1))[0];
        Guid sourceId = Guid.NewGuid();
        Guid intruderWorkout = Guid.NewGuid();
        Guid intruderPlan = Guid.NewGuid();
        DateTime started = new(2026, 8, 18, 17, 0, 0, DateTimeKind.Utc);
        await Run(connectionString, owner, ownerClient, CreateExerciseCommand(ownerClient, 1, sourceId, "Bankdrücken LH"));
        Guid ownerWorkout = Guid.NewGuid();
        await Run(connectionString, owner, ownerClient, Command(Guid.NewGuid(), ownerClient, 2, "createWorkout", "Workout", ownerWorkout, 0,
            new { workout = Workout(ownerWorkout, started, started.AddHours(1), sourceId, Guid.NewGuid(), Guid.NewGuid()) }));
        await Run(connectionString, intruder, intruderClient, Command(Guid.NewGuid(), intruderClient, 1, "createWorkout", "Workout", intruderWorkout, 0,
            new { workout = Workout(intruderWorkout, started, started.AddHours(1), targetId, Guid.NewGuid(), Guid.NewGuid()) }));
        await Run(connectionString, intruder, intruderClient, Command(Guid.NewGuid(), intruderClient, 2, "createTrainingPlan", "TrainingPlan", intruderPlan, 0,
            new { plan = Plan(intruderPlan, Guid.NewGuid(), targetId) }));

        await Process(connectionString, owner, ownerClient,
            MergeCommand(Guid.NewGuid(), ownerClient, 3, sourceId, 1, targetId, targetVersion: null));

        await using AppDbContext check = Fixture.CreateContext(connectionString, intruder);
        Assert.AreEqual(1, (await check.Workouts.SingleAsync(TestContext.CancellationToken)).Version);
        Assert.AreEqual(targetId, (await check.WorkoutExercises.SingleAsync(TestContext.CancellationToken)).SourceExerciseId);
        Assert.AreEqual(1, (await check.TrainingPlans.SingleAsync(TestContext.CancellationToken)).Version);
        Assert.AreEqual(targetId, (await check.TrainingPlanEntries.SingleAsync(TestContext.CancellationToken)).ExerciseId);
    }

    [TestMethod]
    public async Task ChangeFeedDeliversTrainingResourcesOnlyToTheirOwner()
    {
        (string connectionString, Guid owner, Guid intruder, Guid ownerClient, Guid intruderClient) = await SetupAsync();
        Guid[] baseExercises = await BaseExerciseIdsAsync(connectionString, owner, 2);
        Guid ownCustom = Guid.NewGuid();
        Guid categoryId = Guid.NewGuid();
        Guid workoutId = Guid.NewGuid();
        Guid deletedWorkoutId = Guid.NewGuid();
        Guid planId = Guid.NewGuid();
        Guid rotationId = Guid.NewGuid();
        Guid superset = Guid.NewGuid();
        DateTime started = new(2026, 8, 18, 17, 0, 0, DateTimeKind.Utc);
        await Run(connectionString, intruder, intruderClient, CreateExerciseCommand(intruderClient, 1, Guid.NewGuid(), "Intruder only"));

        await Run(connectionString, owner, ownerClient, CreateExerciseCommand(ownerClient, 1, ownCustom, "Eigene Übung"));
        await Run(connectionString, owner, ownerClient, Command(Guid.NewGuid(), ownerClient, 2, "createExerciseCategory", "ExerciseCategory", categoryId, 0,
            new { categoryId, name = "Reha" }));
        await Run(connectionString, owner, ownerClient, Command(Guid.NewGuid(), ownerClient, 3, "createWorkout", "Workout", workoutId, 0,
            new { workout = SupersetWorkout(workoutId, started, baseExercises[0], ownCustom, superset) }));
        await Run(connectionString, owner, ownerClient, Command(Guid.NewGuid(), ownerClient, 4, "createWorkout", "Workout", deletedWorkoutId, 0,
            new { workout = Workout(deletedWorkoutId, started.AddDays(1), started.AddDays(1).AddHours(1), baseExercises[0], Guid.NewGuid(), Guid.NewGuid()) }));
        await Run(connectionString, owner, ownerClient, Command(Guid.NewGuid(), ownerClient, 5, "createTrainingPlan", "TrainingPlan", planId, 0,
            new { plan = Plan(planId, Guid.NewGuid(), baseExercises[1]) }));
        await Run(connectionString, owner, ownerClient, Command(Guid.NewGuid(), ownerClient, 6, "saveWorkoutRotation", "WorkoutRotation", rotationId, 0,
            new { rotationId, baseVersion = 0, planIds = new[] { planId } }));
        await Run(connectionString, owner, ownerClient, Command(Guid.NewGuid(), ownerClient, 7, "deleteWorkout", "Workout", deletedWorkoutId, 1,
            new { workoutId = deletedWorkoutId, baseVersion = 1 }));

        await using AppDbContext ownerContext = Fixture.CreateContext(connectionString, owner);
        List<SyncFeedChange> ownerChanges = (await new SyncChangeFeed(ownerContext).GetAsync(0, 200, TestContext.CancellationToken))
            .Batches.SelectMany(batch => batch.Changes).ToList();
        SyncFeedChange activeWorkout = ownerChanges.Single(change => change.ResourceType == "Workout" && change.ResourceId == workoutId);
        Assert.IsFalse(activeWorkout.IsTombstone);
        Assert.AreEqual(2, activeWorkout.Snapshot!.Value.GetProperty("exercises").GetArrayLength());
        Assert.AreEqual(superset, activeWorkout.Snapshot.Value.GetProperty("exercises")[0].GetProperty("supersetId").GetGuid());
        Assert.AreEqual(2, activeWorkout.Snapshot.Value.GetProperty("exercises")[0].GetProperty("sets").GetArrayLength());
        SyncFeedChange tombstone = ownerChanges.Single(change => change.ResourceType == "Workout"
            && change.ResourceId == deletedWorkoutId && change.IsTombstone);
        Assert.IsTrue(tombstone.IsTombstone);
        Assert.AreEqual(2, tombstone.Version);
        Assert.IsTrue(ownerChanges.Any(change => change.ResourceType == "TrainingPlan" && change.ResourceId == planId));
        Assert.IsTrue(ownerChanges.Any(change => change.ResourceType == "WorkoutRotation" && change.ResourceId == rotationId));
        Assert.IsTrue(ownerChanges.Any(change => change.ResourceType == "CustomExercise" && change.ResourceId == ownCustom));
        Assert.IsTrue(ownerChanges.Any(change => change.ResourceType == "ExerciseCategory" && change.ResourceId == categoryId));

        await using AppDbContext intruderContext = Fixture.CreateContext(connectionString, intruder);
        List<SyncFeedChange> intruderChanges = (await new SyncChangeFeed(intruderContext).GetAsync(0, 200, TestContext.CancellationToken))
            .Batches.SelectMany(batch => batch.Changes).ToList();
        Assert.HasCount(1, intruderChanges);
        Assert.AreEqual("CustomExercise", intruderChanges[0].ResourceType);
        Assert.IsFalse(intruderChanges.Any(change => change.ResourceId == workoutId || change.ResourceId == planId));

        var history = new WorkoutHistoryQueries(ownerContext);
        IReadOnlyList<WorkoutHistorySummary> entries = await history.ListAsync(0, 10, TestContext.CancellationToken);
        Assert.HasCount(1, entries);
        Assert.AreEqual(workoutId, entries[0].WorkoutId);
        Assert.IsNull(await history.GetAsync(deletedWorkoutId, TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task OlderProtocolIsRejectedForTrainingOperationsBeforeAnyWrite()
    {
        (string connectionString, Guid owner, _, Guid ownerClient, _) = await SetupAsync();
        Guid[] baseExercises = await BaseExerciseIdsAsync(connectionString, owner, 1);
        Guid workoutId = Guid.NewGuid();
        DateTime started = new(2026, 8, 18, 17, 0, 0, DateTimeKind.Utc);
        ProcessSyncMutationCommand training = Command(Guid.NewGuid(), ownerClient, 1, "createWorkout", "Workout", workoutId, 0,
            new { workout = Workout(workoutId, started, started.AddHours(1), baseExercises[0], Guid.NewGuid(), Guid.NewGuid()) });

        SyncUpgradeRequiredException previous = await Expect<SyncUpgradeRequiredException>(() =>
            Process(connectionString, owner, ownerClient, WithProtocol(training, 2)));
        SyncUpgradeRequiredException missing = await Expect<SyncUpgradeRequiredException>(() =>
            Process(connectionString, owner, ownerClient, WithProtocol(training, 0)));
        Assert.AreEqual("upgrade_required", previous.Code);
        Assert.AreEqual("upgrade_required", missing.Code);

        SyncMutationValidationException nonTraining = await Expect<SyncMutationValidationException>(() =>
            Process(connectionString, owner, ownerClient, WithProtocol(Command(Guid.NewGuid(), ownerClient, 2, "unknownOperation", "Workout", workoutId, 0,
                new { }), 2)));
        Assert.AreEqual("unsupported_operation", nonTraining.Code);

        await using (AppDbContext check = Fixture.CreateContext(connectionString, owner))
        {
            Assert.AreEqual(0, await check.Workouts.CountAsync(TestContext.CancellationToken));
            Assert.AreEqual(0, await check.ChangeBatches.CountAsync(TestContext.CancellationToken));
        }

        ProcessedSyncMutationResult accepted = await Process(connectionString, owner, ownerClient, WithProtocol(training, 3));
        Assert.HasCount(1, accepted.Changes);
    }

    private static ProcessSyncMutationCommand CreateExerciseCommand(Guid clientId, long sequence, Guid exerciseId, string name) =>
        Command(Guid.NewGuid(), clientId, sequence, "createCustomExercise", "CustomExercise", exerciseId, 0,
            new { exerciseId, values = new { name, exerciseType = "strength" } });

    private static ProcessSyncMutationCommand MergeCommand(
        Guid mutationId,
        Guid clientId,
        long sequence,
        Guid sourceId,
        long sourceVersion,
        Guid targetId,
        long? targetVersion)
    {
        var resources = new List<CanonicalResourceVersion> { new("CustomExercise", sourceId, sourceVersion) };
        if (targetVersion is { } version) resources.Add(new CanonicalResourceVersion("CustomExercise", targetId, version));
        return new ProcessSyncMutationCommand(
            mutationId,
            new CanonicalMutationContent(
                3,
                clientId,
                sequence,
                "mergeExercises",
                resources,
                null,
                JsonSerializer.SerializeToElement(new
                {
                    sourceExerciseId = sourceId,
                    sourceBaseVersion = sourceVersion,
                    targetExerciseId = targetId,
                }, JsonOptions)));
    }

    private static ProcessSyncMutationCommand WithProtocol(ProcessSyncMutationCommand command, int protocolVersion) =>
        command with { Content = command.Content with { ProtocolVersion = protocolVersion } };

    private static object SupersetWorkout(Guid workoutId, DateTime started, Guid firstExercise, Guid secondExercise, Guid superset) => new
    {
        workoutId,
        title = "Push",
        notes = (string?)null,
        startedAtUtc = started,
        endedAtUtc = started.AddHours(1),
        previousValueSource = "exercise",
        sourcePlanId = (Guid?)null,
        sourceWorkoutId = (Guid?)null,
        exercises = new object[]
        {
            new
            {
                workoutExerciseId = Guid.NewGuid(),
                sourceExerciseId = firstExercise,
                exerciseNameSnapshot = "Bench",
                exerciseTypeSnapshot = "strength",
                notes = (string?)null,
                supersetId = (Guid?)superset,
                sets = new object[]
                {
                    new { setId = Guid.NewGuid(), setType = "warmup", weightKg = (decimal?)40, repetitions = (int?)10, rir = (decimal?)null, notes = (string?)null },
                    new { setId = Guid.NewGuid(), setType = "normal", weightKg = (decimal?)100, repetitions = (int?)8, rir = (decimal?)null, notes = (string?)null },
                },
            },
            new
            {
                workoutExerciseId = Guid.NewGuid(),
                sourceExerciseId = secondExercise,
                exerciseNameSnapshot = "Eigene Übung",
                exerciseTypeSnapshot = "strength",
                notes = (string?)null,
                supersetId = (Guid?)superset,
                sets = new object[]
                {
                    new { setId = Guid.NewGuid(), setType = "normal", weightKg = (decimal?)20, repetitions = (int?)12, rir = (decimal?)2, notes = (string?)null },
                },
            },
        },
    };

    private static async Task<ProcessedSyncMutationResult> Process(
        string connectionString,
        Guid userId,
        Guid clientId,
        ProcessSyncMutationCommand command)
    {
        _ = clientId;
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        var user = new CurrentUser(userId);
        var processor = new SyncMutationProcessor(context, user, new SyncMutationExecutor(context, user, TimeProvider.System), TimeProvider.System);
        return await processor.ProcessAsync(command);
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
                3,
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

    private static System.Text.Json.Nodes.JsonObject WithSource(object workout, Guid? planId = null, Guid? sourceWorkoutId = null)
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
