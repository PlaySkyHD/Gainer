using Gainer.Core.Training;
using Gainer.Core.Mutations;
using Gainer.Core.Security;
using Gainer.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Gainer.IntegrationTests;

[TestClass]
[DoNotParallelize]
public sealed class WorkoutSnapshotPersistenceTests
{
    public TestContext TestContext { get; set; } = null!;

    private static PostgreSqlTestFixture? fixture;
    private static PostgreSqlTestFixture Fixture => fixture
        ?? throw new InvalidOperationException("The PostgreSQL fixture has not started.");

    private static readonly string[] ExpectedSetTypes = ["warmup", "warmup", "normal", "normal", "normal"];

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
    public async Task CreatesEmptyWorkoutWithTitleAndNoBlocks()
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        Guid workoutId = Guid.NewGuid();
        var collector = new ChangeCollector();
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
        WorkoutSnapshot snapshot = await Handler(context, userId, collector).CreateAsync(
            CreateWorkoutMutation.Create(Metadata(), Values(workoutId, "Leeres Training", Started, null, [])), TestContext.CancellationToken);

        Assert.AreEqual(1, snapshot.Version);
        Assert.IsEmpty(snapshot.Exercises);
        Assert.IsNull(snapshot.EndedAtUtc);
        Assert.HasCount(1, collector.Changes);
        Assert.AreEqual("Leeres Training", (await context.Workouts.SingleAsync(TestContext.CancellationToken)).Title);
    }

    [TestMethod]
    public async Task CreatesWorkoutFromPlanSnapshotWithWarmupAndWorkingSetsAndNormalizesUnknownSetTypes()
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        Guid[] exerciseIds = await BaseExerciseIdsAsync(connectionString, userId, 2);
        Guid workoutId = Guid.NewGuid();
        var sets = new[]
        {
            Set("warmup", null, null), Set("warmup", null, null),
            Set("normal", null, null), Set("normal", null, null), Set("mystery", null, null),
        };
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
        WorkoutSnapshot snapshot = await Handler(context, userId).CreateAsync(CreateWorkoutMutation.Create(
            Metadata(),
            Values(workoutId, "Push", Started, null, [Block(exerciseIds[0], "Bench", sets)], sourcePlanId: await PlanAsync(connectionString, userId, exerciseIds[0]))), TestContext.CancellationToken);

        WorkoutExerciseValues block = snapshot.Exercises.Single();
        Assert.AreSequenceEqual(
            ExpectedSetTypes, block.Sets.Select(item => item.SetType).ToArray());
        Assert.IsNotNull(snapshot.SourcePlanId);
        Assert.AreEqual("exercise", snapshot.PreviousValueSource);
        Assert.AreEqual(5, await context.WorkoutSets.CountAsync(item => item.WorkoutId == workoutId, TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task RepeatedWorkoutCopiesStructureAndStartsWithoutValues()
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        Guid[] exerciseIds = await BaseExerciseIdsAsync(connectionString, userId, 1);
        Guid sourceId = Guid.NewGuid();
        Guid repeatId = Guid.NewGuid();
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
        var handler = Handler(context, userId);
        await handler.CreateAsync(CreateWorkoutMutation.Create(Metadata(), Values(sourceId, "Push", Started, Started.AddHours(1),
            [Block(exerciseIds[0], "Bench", [Set("warmup", 60m, 10), Set("normal", 100m, 8)])])), TestContext.CancellationToken);

        WorkoutSnapshot repeated = await handler.CreateAsync(CreateWorkoutMutation.Create(Metadata(), Values(
            repeatId, "Push", Started.AddDays(1), null,
            [Block(exerciseIds[0], "Bench", [Set("warmup", null, null), Set("normal", null, null)])],
            sourceWorkoutId: sourceId)), TestContext.CancellationToken);

        Assert.AreEqual(sourceId, repeated.SourceWorkoutId);
        Assert.HasCount(2, repeated.Exercises[0].Sets);
        Assert.IsTrue(repeated.Exercises[0].Sets.All(item => item.WeightKg is null && item.Repetitions is null));
    }

    [TestMethod]
    public async Task EditsHistoricalWorkoutAndAdvancesVersion()
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        Guid[] exerciseIds = await BaseExerciseIdsAsync(connectionString, userId, 1);
        Guid workoutId = Guid.NewGuid();
        Guid exerciseEntryId = Guid.NewGuid();
        Guid setId = Guid.NewGuid();
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
        var handler = Handler(context, userId);
        await handler.CreateAsync(CreateWorkoutMutation.Create(Metadata(), Values(workoutId, "Push", Started, Started.AddHours(1),
            [new WorkoutExerciseValues(exerciseEntryId, exerciseIds[0], "Bench", "strength", null, null,
                [new WorkoutSetValues(setId, "normal", 100m, 8, null, null)])])), TestContext.CancellationToken);

        WorkoutSnapshot edited = await handler.SaveAsync(SaveWorkoutMutation.Create(Metadata(), 1, Values(
            workoutId, "Push", Started, Started.AddHours(1),
            [new WorkoutExerciseValues(exerciseEntryId, exerciseIds[0], "Bench", "strength", null, null,
                [new WorkoutSetValues(setId, "normal", 100m, 10, null, null)])])), TestContext.CancellationToken);

        Assert.AreEqual(2, edited.Version);
        Assert.AreEqual(10, edited.Exercises[0].Sets[0].Repetitions);
        Assert.AreEqual(10, (await context.WorkoutSets.SingleAsync(TestContext.CancellationToken)).Repetitions);
    }

    [TestMethod]
    public async Task ReplacingBlocksAndSetsWithStableIdsIsNotAConflict()
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        Guid[] exerciseIds = await BaseExerciseIdsAsync(connectionString, userId, 1);
        Guid workoutId = Guid.NewGuid();
        Guid blockA = Guid.NewGuid(), blockB = Guid.NewGuid(), blockC = Guid.NewGuid(), blockNew = Guid.NewGuid();
        Guid a1 = Guid.NewGuid(), c1 = Guid.NewGuid(), n1 = Guid.NewGuid();
        Guid b1 = Guid.NewGuid(), b2 = Guid.NewGuid(), b3 = Guid.NewGuid(), bNew = Guid.NewGuid();

        WorkoutExerciseValues B(Guid id, params Guid[] setIds) => new(
            id, exerciseIds[0], "Bench", "strength", null, null,
            setIds.Select(setId => new WorkoutSetValues(setId, "normal", 100m, 8, null, null)).ToArray());

        WorkoutExerciseValues[][] rounds =
        [
            [B(blockA, a1), B(blockB, b1, b2, b3), B(blockC, c1)],
            // Delete the first block; the others move up.
            [B(blockB, b1, b2, b3), B(blockC, c1)],
            // Insert a new first block; the others move down.
            [B(blockNew, n1), B(blockB, b1, b2, b3), B(blockC, c1)],
            // Swap the first and last block.
            [B(blockC, c1), B(blockB, b1, b2, b3), B(blockNew, n1)],
            // Within the remaining block B: delete the first set; the others move up.
            [B(blockC, c1), B(blockB, b2, b3), B(blockNew, n1)],
            // Insert a new first set; the others move down.
            [B(blockC, c1), B(blockB, bNew, b2, b3), B(blockNew, n1)],
            // Swap two sets.
            [B(blockC, c1), B(blockB, bNew, b3, b2), B(blockNew, n1)],
        ];

        long version = 0;
        for (int index = 0; index < rounds.Length; index++)
        {
            await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
            var handler = Handler(context, userId);
            WorkoutValues values = Values(workoutId, "Push", Started, Started.AddHours(1), rounds[index]);
            WorkoutSnapshot saved = index == 0
                ? await handler.CreateAsync(CreateWorkoutMutation.Create(Metadata(), values), TestContext.CancellationToken)
                : await handler.SaveAsync(SaveWorkoutMutation.Create(Metadata(), version, values), TestContext.CancellationToken);
            version = saved.Version;
            Assert.AreEqual(index + 1, saved.Version);
        }

        await using AppDbContext read = PostgreSqlTestFixture.CreateContext(connectionString, userId);
        List<WorkoutExercise> stored = await read.WorkoutExercises.AsNoTracking().OrderBy(item => item.Position).ToListAsync(TestContext.CancellationToken);
        Assert.AreSequenceEqual(new[] { blockC, blockB, blockNew }, stored.Select(item => item.Id).ToArray());
        List<WorkoutSet> storedSets = await read.WorkoutSets.AsNoTracking()
            .Where(item => item.WorkoutExerciseId == blockB).OrderBy(item => item.Position).ToListAsync(TestContext.CancellationToken);
        Assert.AreSequenceEqual(new[] { bNew, b3, b2 }, storedSets.Select(item => item.Id).ToArray());
    }

    [TestMethod]
    public async Task StaleBaseVersionRaisesWorkoutConflictAndKeepsStoredState()
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        Guid workoutId = Guid.NewGuid();
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
        var handler = Handler(context, userId);
        await handler.CreateAsync(CreateWorkoutMutation.Create(Metadata(), Values(workoutId, "Push", Started, null, [])), TestContext.CancellationToken);
        await handler.SaveAsync(SaveWorkoutMutation.Create(Metadata(), 1, Values(workoutId, "Push 2", Started, null, [])), TestContext.CancellationToken);

        await Assert.ThrowsAsync<WorkoutConflictException>(() => handler.SaveAsync(
            SaveWorkoutMutation.Create(Metadata(), 1, Values(workoutId, "Stale", Started, null, [])), TestContext.CancellationToken));
        await Assert.ThrowsAsync<WorkoutConflictException>(() => handler.DeleteAsync(
            DeleteWorkoutMutation.Create(Metadata(), workoutId, 1), TestContext.CancellationToken));

        context.ChangeTracker.Clear();
        Workout stored = await context.Workouts.SingleAsync(TestContext.CancellationToken);
        Assert.AreEqual("Push 2", stored.Title);
        Assert.AreEqual(2, stored.Version);
        Assert.IsNull(stored.DeletedAtUtc);
    }

    [TestMethod]
    public async Task EndsAndResumesWorkoutThroughEndedAt()
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        Guid workoutId = Guid.NewGuid();
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
        var handler = Handler(context, userId);
        await handler.CreateAsync(CreateWorkoutMutation.Create(Metadata(), Values(workoutId, "Push", Started, null, [])), TestContext.CancellationToken);

        WorkoutSnapshot ended = await handler.SaveAsync(SaveWorkoutMutation.Create(Metadata(), 1,
            Values(workoutId, "Push", Started, Started.AddMinutes(50), [])), TestContext.CancellationToken);
        Assert.AreEqual(Started.AddMinutes(50), ended.EndedAtUtc);

        WorkoutSnapshot resumed = await handler.SaveAsync(SaveWorkoutMutation.Create(Metadata(), 2,
            Values(workoutId, "Push", Started, null, [])), TestContext.CancellationToken);
        Assert.IsNull(resumed.EndedAtUtc);
        Assert.AreEqual(3, resumed.Version);
    }

    [TestMethod]
    public async Task SecondActiveWorkoutIsRejectedWithActiveWorkoutExists()
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        Guid firstId = Guid.NewGuid();
        Guid secondId = Guid.NewGuid();
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
        var handler = Handler(context, userId);
        await handler.CreateAsync(CreateWorkoutMutation.Create(Metadata(), Values(firstId, "Push", Started, null, [])), TestContext.CancellationToken);

        await Assert.ThrowsAsync<ActiveWorkoutExistsException>(() => handler.CreateAsync(
            CreateWorkoutMutation.Create(Metadata(), Values(secondId, "Pull", Started.AddHours(20), null, [])), TestContext.CancellationToken));
        context.ChangeTracker.Clear();
        Assert.AreEqual(1, await context.Workouts.CountAsync(item => item.EndedAtUtc == null, TestContext.CancellationToken));

        // A finished workout does not block a new active one.
        await handler.SaveAsync(SaveWorkoutMutation.Create(Metadata(), 1, Values(firstId, "Push", Started, Started.AddHours(1), [])), TestContext.CancellationToken);
        await handler.CreateAsync(CreateWorkoutMutation.Create(Metadata(), Values(secondId, "Pull", Started.AddDays(1), null, [])), TestContext.CancellationToken);
        Assert.AreEqual(2, await context.Workouts.CountAsync(TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task EndBeforeStartIsRejectedWithFieldErrorAndKeepsPreviousState()
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        Guid workoutId = Guid.NewGuid();
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
        var handler = Handler(context, userId);
        await handler.CreateAsync(CreateWorkoutMutation.Create(Metadata(), Values(workoutId, "Push", Started, Started.AddHours(1), [])), TestContext.CancellationToken);

        WorkoutValidationException error = await Assert.ThrowsAsync<WorkoutValidationException>(() => handler.SaveAsync(
            SaveWorkoutMutation.Create(Metadata(), 1, Values(workoutId, "Push", Started, Started.AddMinutes(-30), [])), TestContext.CancellationToken));
        Assert.IsTrue(error.Errors.ContainsKey("EndedAtUtc"));
        context.ChangeTracker.Clear();
        Workout stored = await context.Workouts.SingleAsync(TestContext.CancellationToken);
        Assert.AreEqual(1, stored.Version);
        Assert.AreEqual(Started.AddHours(1), stored.EndedAtUtc);
    }

    [TestMethod]
    public async Task DeleteCreatesTombstoneAndRemovesWorkoutFromHistory()
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        Guid[] exerciseIds = await BaseExerciseIdsAsync(connectionString, userId, 1);
        Guid workoutId = Guid.NewGuid();
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
        await Handler(context, userId).CreateAsync(CreateWorkoutMutation.Create(Metadata(), Values(
            workoutId, "Push", Started, Started.AddHours(1), [Block(exerciseIds[0], "Bench", [Set("normal", 100m, 8)])])), TestContext.CancellationToken);
        var collector = new ChangeCollector();
        var handler = Handler(context, userId, collector);

        DeleteWorkoutResult deleted = await handler.DeleteAsync(DeleteWorkoutMutation.Create(Metadata(), workoutId, 1), TestContext.CancellationToken);

        Assert.AreEqual(2, deleted.Version);
        Assert.HasCount(1, collector.Changes);
        Assert.IsInstanceOfType<DeletedResourceChange>(collector.Changes[0]);
        Assert.IsFalse(await context.Workouts.AnyAsync(item => item.Id == workoutId && item.DeletedAtUtc == null, TestContext.CancellationToken));
        Assert.IsEmpty(await context.WorkoutSets.Where(item => item.WorkoutId == workoutId).ToListAsync(TestContext.CancellationToken));
        Assert.DoesNotContain(item => item.WorkoutId == workoutId, await new WorkoutHistoryQueries(context).ListAsync(0, 100, TestContext.CancellationToken));
        Assert.IsNull(await new WorkoutHistoryQueries(context).GetAsync(workoutId, TestContext.CancellationToken));
        await Assert.ThrowsAsync<WorkoutNotFoundException>(() => handler.DeleteAsync(DeleteWorkoutMutation.Create(Metadata(), workoutId, 2), TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task ForeignAndUnknownReferencesAreRejectedWithoutDisclosure()
    {
        (string connectionString, Guid firstUser, Guid secondUser) = await CreateDatabaseAsync();
        Guid workoutId = Guid.NewGuid();
        Guid ownCustomExercise = Guid.NewGuid();
        await using (AppDbContext owner3 = PostgreSqlTestFixture.CreateContext(connectionString, firstUser))
        {
            owner3.Exercises.Add(new Exercise
            {
                Id = ownCustomExercise,
                OwnerUserId = firstUser,
                Name = "Owner only",
                ExerciseType = ExerciseType.Strength,
                CreatedAtUtc = Started,
                UpdatedAtUtc = Started,
                Version = 1,
            });
            await owner3.SaveChangesAsync(TestContext.CancellationToken);
        }
        Guid planId = await PlanAsync(connectionString, firstUser, ownCustomExercise);
        Guid sourceWorkoutId = Guid.NewGuid();
        await using (AppDbContext owner = PostgreSqlTestFixture.CreateContext(connectionString, firstUser))
        {
            await Handler(owner, firstUser).CreateAsync(CreateWorkoutMutation.Create(Metadata(), Values(
                sourceWorkoutId, "Old", Started.AddDays(-2), Started.AddDays(-2).AddHours(1), [])), TestContext.CancellationToken);
            await Handler(owner, firstUser).CreateAsync(CreateWorkoutMutation.Create(Metadata(), Values(
                workoutId, "Push", Started, null, [])), TestContext.CancellationToken);
        }

        await using AppDbContext foreign = PostgreSqlTestFixture.CreateContext(connectionString, secondUser);
        var intruder = Handler(foreign, secondUser);
        await Assert.ThrowsAsync<WorkoutNotFoundException>(() => intruder.SaveAsync(SaveWorkoutMutation.Create(
            Metadata(), 1, Values(workoutId, "Stolen", Started, null, [])), TestContext.CancellationToken));
        await Assert.ThrowsAsync<WorkoutNotFoundException>(() => intruder.DeleteAsync(DeleteWorkoutMutation.Create(Metadata(), workoutId, 1), TestContext.CancellationToken));

        WorkoutValidationException foreignPlan = await Assert.ThrowsAsync<WorkoutValidationException>(() => intruder.CreateAsync(
            CreateWorkoutMutation.Create(Metadata(), Values(Guid.NewGuid(), "Push", Started, null, [], sourcePlanId: planId)), TestContext.CancellationToken));
        WorkoutValidationException unknownPlan = await Assert.ThrowsAsync<WorkoutValidationException>(() => intruder.CreateAsync(
            CreateWorkoutMutation.Create(Metadata(), Values(Guid.NewGuid(), "Push", Started, null, [], sourcePlanId: Guid.NewGuid())), TestContext.CancellationToken));
        Assert.AreEqual(foreignPlan.Errors["SourcePlanId"], unknownPlan.Errors["SourcePlanId"]);

        WorkoutValidationException foreignSource = await Assert.ThrowsAsync<WorkoutValidationException>(() => intruder.CreateAsync(
            CreateWorkoutMutation.Create(Metadata(), Values(Guid.NewGuid(), "Push", Started, null, [], sourceWorkoutId: sourceWorkoutId)), TestContext.CancellationToken));
        Assert.IsTrue(foreignSource.Errors.ContainsKey("SourceWorkoutId"));

        WorkoutValidationException foreignExercise = await Assert.ThrowsAsync<WorkoutValidationException>(() => intruder.CreateAsync(
            CreateWorkoutMutation.Create(Metadata(), Values(Guid.NewGuid(), "Push", Started, null,
                [Block(ownCustomExercise, "Bench", [Set("normal", 100m, 8)])])), TestContext.CancellationToken));
        WorkoutValidationException unknownExercise = await Assert.ThrowsAsync<WorkoutValidationException>(() => intruder.CreateAsync(
            CreateWorkoutMutation.Create(Metadata(), Values(Guid.NewGuid(), "Push", Started, null,
                [Block(Guid.NewGuid(), "Bench", [Set("normal", 100m, 8)])])), TestContext.CancellationToken));
        Assert.AreEqual(foreignExercise.Errors["Exercises.SourceExerciseId"], unknownExercise.Errors["Exercises.SourceExerciseId"]);

        await using AppDbContext owner2 = PostgreSqlTestFixture.CreateContext(connectionString, firstUser);
        Assert.AreEqual("Push", (await owner2.Workouts.SingleAsync(item => item.Id == workoutId, TestContext.CancellationToken)).Title);
    }

    [TestMethod]
    public async Task PostgreSqlRejectsSecondActiveWorkoutInvalidRangesAndDuplicatePositions()
    {
        (string connectionString, Guid userId, Guid otherUser) = await CreateDatabaseAsync();
        Guid[] exerciseIds = await BaseExerciseIdsAsync(connectionString, userId, 1);
        Guid workoutId = Guid.NewGuid();
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId))
        {
            context.Workouts.Add(Workout(workoutId, "Push", Started, null));
            await context.SaveChangesAsync(TestContext.CancellationToken);
        }
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId))
        {
            context.Workouts.Add(Workout(Guid.NewGuid(), "Second active", Started, null));
            await Assert.ThrowsAsync<DbUpdateException>(() => context.SaveChangesAsync(TestContext.CancellationToken));
        }
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, otherUser))
        {
            context.Workouts.Add(Workout(Guid.NewGuid(), "Ends before start", Started, Started.AddMinutes(-1)));
            await Assert.ThrowsAsync<DbUpdateException>(() => context.SaveChangesAsync(TestContext.CancellationToken));
        }
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId))
        {
            Guid workoutExerciseId = Guid.NewGuid();
            context.WorkoutExercises.Add(new WorkoutExercise
            {
                Id = workoutExerciseId,
                WorkoutId = workoutId,
                SourceExerciseId = exerciseIds[0],
                ExerciseNameSnapshot = "Bench",
                ExerciseTypeSnapshot = ExerciseType.Strength,
                Position = 0,
            });
            context.WorkoutSets.Add(new WorkoutSet
            {
                Id = Guid.NewGuid(),
                WorkoutId = workoutId,
                WorkoutExerciseId = workoutExerciseId,
                Position = 0,
                SetType = WorkoutSetType.Normal,
                WeightKg = 100,
                Repetitions = 10_001,
            });
            await Assert.ThrowsAsync<DbUpdateException>(() => context.SaveChangesAsync(TestContext.CancellationToken));
        }
    }

    [TestMethod]
    public async Task HistoryCountsOnlyWorkingSetsWithWeightAndRepetitions()
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        Guid[] exerciseIds = await BaseExerciseIdsAsync(connectionString, userId, 1);
        Guid workoutId = Guid.NewGuid();
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
        await Handler(context, userId).CreateAsync(CreateWorkoutMutation.Create(Metadata(), Values(
            workoutId, "Push", Started, Started.AddHours(1),
            [Block(exerciseIds[0], "Bench", [Set("warmup", 40m, 10), Set("normal", 100m, 8), Set("normal", null, 5), Set("dropset", 80m, 6)])])), TestContext.CancellationToken);

        WorkoutHistorySummary summary = (await new WorkoutHistoryQueries(context).ListAsync(0, 10, TestContext.CancellationToken)).Single();
        Assert.AreEqual(2, summary.CompletedSetCount);
        Assert.AreEqual(Started.AddHours(1), summary.EndedAtUtc);
    }

    private static readonly DateTime Started = new(2026, 8, 18, 17, 0, 0, DateTimeKind.Utc);

    private static WorkoutMutationHandler Handler(AppDbContext context, Guid userId, ChangeCollector? collector = null) =>
        new(context, new CurrentUser(userId), TimeProvider.System, collector);

    private static WorkoutValues Values(
        Guid workoutId,
        string title,
        DateTime startedAtUtc,
        DateTime? endedAtUtc,
        IReadOnlyList<WorkoutExerciseValues> exercises,
        Guid? sourcePlanId = null,
        Guid? sourceWorkoutId = null) => new(
        workoutId, title, null, startedAtUtc, endedAtUtc, "exercise", sourcePlanId, sourceWorkoutId, exercises);

    private static WorkoutExerciseValues Block(Guid sourceExerciseId, string name, IReadOnlyList<WorkoutSetValues> sets) => new(
        Guid.NewGuid(), sourceExerciseId, name, "strength", null, null, sets);

    private static WorkoutSetValues Set(string setType, decimal? weight, int? repetitions) => new(
        Guid.NewGuid(), setType, weight, repetitions, null, null);

    private static Workout Workout(Guid id, string title, DateTime started, DateTime? ended) => new()
    {
        Id = id,
        Title = title,
        StartedAtUtc = started,
        EndedAtUtc = ended,
        PreviousValueSource = PreviousValueSource.Exercise,
        CreatedAtUtc = started,
        UpdatedAtUtc = started,
        Version = 1,
    };

    private static async Task<Guid> PlanAsync(string connectionString, Guid userId, Guid exerciseId)
    {
        Guid planId = Guid.NewGuid();
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
        await new TrainingPlanMutationHandler(context, new CurrentUser(userId), TimeProvider.System).CreateAsync(
            CreateTrainingPlanMutation.Create(Metadata(), new TrainingPlanValues(
                planId, "Push", null, "exercise",
                [new TrainingPlanEntryValues(Guid.NewGuid(), exerciseId, 2, 3, null, null)])));
        return planId;
    }

    private static async Task AddWorkoutAsync(
        string connectionString,
        Guid userId,
        Guid sourceExerciseId,
        DateTime startedAtUtc,
        DateTime? endedAtUtc,
        decimal weight,
        int repetitions,
        WorkoutSetType setType)
    {
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
        Guid workoutId = Guid.NewGuid();
        Guid exerciseEntryId = Guid.NewGuid();
        context.Workouts.Add(Workout(workoutId, "Historical", startedAtUtc, endedAtUtc));
        context.WorkoutExercises.Add(new WorkoutExercise
        {
            Id = exerciseEntryId,
            WorkoutId = workoutId,
            SourceExerciseId = sourceExerciseId,
            ExerciseNameSnapshot = "Snapshot",
            ExerciseTypeSnapshot = ExerciseType.Strength,
            Position = 0,
        });
        context.WorkoutSets.Add(new WorkoutSet
        {
            Id = Guid.NewGuid(),
            WorkoutId = workoutId,
            WorkoutExerciseId = exerciseEntryId,
            Position = 0,
            SetType = setType,
            WeightKg = weight,
            Repetitions = repetitions,
        });
        await context.SaveChangesAsync();
    }

    private static MutationMetadata Metadata() => MutationMetadata.Create(Guid.NewGuid(), Guid.NewGuid(), 1);

    private static async Task<Guid[]> BaseExerciseIdsAsync(string connectionString, Guid userId, int count)
    {
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
        return await context.Exercises.Where(item => item.OwnerUserId == null)
            .OrderBy(item => item.Id).Select(item => item.Id).Take(count).ToArrayAsync();
    }

    private static async Task<(string ConnectionString, Guid FirstUser, Guid SecondUser)> CreateDatabaseAsync()
    {
        string connectionString = await Fixture.CreateIsolatedDatabaseAsync();
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString))
        {
            await context.Database.MigrateAsync();
            Guid first = Guid.NewGuid();
            Guid second = Guid.NewGuid();
            context.Users.AddRange(User(first), User(second));
            await context.SaveChangesAsync();
            return (connectionString, first, second);
        }
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
