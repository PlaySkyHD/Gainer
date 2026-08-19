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
    public async Task RelationalSnapshotStoresCopiedNamesTargetsSetsAndTimes()
    {
        (string connectionString, Guid firstUser, _) = await CreateDatabaseAsync();
        Guid workoutId = Guid.NewGuid();
        Guid workoutExerciseId = Guid.NewGuid();
        DateTime started = new(2026, 8, 18, 17, 0, 0, DateTimeKind.Utc);
        await using (AppDbContext context = Fixture.CreateContext(connectionString, firstUser))
        {
            context.Workouts.Add(Workout(workoutId, "Upper A", started));
            context.WorkoutExercises.Add(Exercise(workoutExerciseId, workoutId, "Bench at start", 0));
            context.WorkoutSets.Add(new WorkoutSet
            {
                Id = Guid.NewGuid(),
                WorkoutId = workoutId,
                WorkoutExerciseId = workoutExerciseId,
                Position = 0,
                WeightKg = 102.5m,
                Repetitions = 8,
                Rir = 2,
                Notes = "clean rep",
                IsCompleted = true,
                CompletedAtUtc = started.AddMinutes(5),
            });
            await context.SaveChangesAsync();
        }

        await using AppDbContext read = Fixture.CreateContext(connectionString, firstUser);
        Workout workout = await read.Workouts.SingleAsync();
        WorkoutExercise exercise = await read.WorkoutExercises.SingleAsync();
        WorkoutSet set = await read.WorkoutSets.SingleAsync();
        Assert.AreEqual("Upper A", workout.TemplateNameSnapshot);
        Assert.AreEqual("Bench at start", exercise.ExerciseNameSnapshot);
        Assert.AreEqual(3, exercise.PlannedSets);
        Assert.AreEqual(6, exercise.MinimumRepetitions);
        Assert.AreEqual(8, exercise.MaximumRepetitions);
        Assert.AreEqual(102.5m, set.WeightKg);
        Assert.AreEqual(8, set.Repetitions);
    }

    [TestMethod]
    public async Task PostgreSqlRejectsInvalidCompletionAndDuplicatePositions()
    {
        (string connectionString, Guid firstUser, _) = await CreateDatabaseAsync();
        Guid workoutId = Guid.NewGuid();
        Guid workoutExerciseId = Guid.NewGuid();
        await using AppDbContext context = Fixture.CreateContext(connectionString, firstUser);
        context.Workouts.Add(Workout(workoutId, "Plan", DateTime.UtcNow));
        context.WorkoutExercises.Add(Exercise(workoutExerciseId, workoutId, "Squat", 0));
        context.WorkoutSets.Add(new WorkoutSet
        {
            Id = Guid.NewGuid(),
            WorkoutId = workoutId,
            WorkoutExerciseId = workoutExerciseId,
            Position = 0,
            IsCompleted = true,
            CompletedAtUtc = DateTime.UtcNow,
        });
        await Assert.ThrowsAsync<DbUpdateException>(() => context.SaveChangesAsync());
    }

    [TestMethod]
    public async Task CompositeOwnershipConstraintRejectsCrossUserWorkoutChildren()
    {
        (string connectionString, Guid firstUser, Guid secondUser) = await CreateDatabaseAsync();
        Guid workoutId = Guid.NewGuid();
        await using (AppDbContext first = Fixture.CreateContext(connectionString, firstUser))
        {
            first.Workouts.Add(Workout(workoutId, "Private plan", DateTime.UtcNow));
            await first.SaveChangesAsync();
        }
        await using (AppDbContext second = Fixture.CreateContext(connectionString, secondUser))
        {
            second.WorkoutExercises.Add(Exercise(Guid.NewGuid(), workoutId, "Probe", 0));
            await Assert.ThrowsAsync<DbUpdateException>(() => second.SaveChangesAsync());
            Assert.AreEqual(0, await second.Workouts.CountAsync());
        }
    }

    [TestMethod]
    public async Task ServerStartAndEditAreOwnerBoundValidatedAndDoNotChangeTemplate()
    {
        (string connectionString, Guid firstUser, Guid secondUser) = await CreateDatabaseAsync();
        Guid[] baseIds;
        await using (AppDbContext catalog = Fixture.CreateContext(connectionString, firstUser))
        {
            baseIds = await catalog.Exercises.Where(item => item.OwnerUserId == null)
                .OrderBy(item => item.Id).Select(item => item.Id).Take(2).ToArrayAsync();
        }
        Guid templateId = Guid.NewGuid();
        await using (AppDbContext templateContext = Fixture.CreateContext(connectionString, firstUser))
        {
            var templates = new WorkoutTemplateMutationHandler(templateContext, new UserContext(firstUser), TimeProvider.System);
            await templates.SaveAsync(SaveWorkoutTemplateMutation.Create(
                Metadata(), templateId, 0, "Upper A",
                [new WorkoutTemplateItemValues(Guid.NewGuid(), baseIds[0], 3, 6, 8, 2, 180, "template note")]));
        }

        Guid workoutId = Guid.NewGuid();
        WorkoutSnapshot started;
        await using (AppDbContext startContext = Fixture.CreateContext(connectionString, firstUser))
        {
            var handler = new WorkoutMutationHandler(startContext, new UserContext(firstUser), TimeProvider.System);
            started = await handler.StartAsync(StartWorkoutMutation.Create(Metadata(), workoutId, templateId));
            Assert.AreEqual("Upper A", started.TemplateNameSnapshot);
            Assert.HasCount(3, started.Exercises[0].Sets);
            Assert.AreEqual(180, started.Exercises[0].RestSeconds);
        }
        await using (AppDbContext foreignContext = Fixture.CreateContext(connectionString, secondUser))
        {
            var foreign = new WorkoutMutationHandler(foreignContext, new UserContext(secondUser), TimeProvider.System);
            await Assert.ThrowsAsync<WorkoutTemplateNotFoundException>(() => foreign.StartAsync(
                StartWorkoutMutation.Create(Metadata(), Guid.NewGuid(), templateId)));
            await Assert.ThrowsAsync<WorkoutNotFoundException>(() => foreign.EditAsync(
                EditWorkoutMutation.Create(Metadata(), workoutId, 1, [])));
        }

        await using (AppDbContext editContext = Fixture.CreateContext(connectionString, firstUser))
        {
            var handler = new WorkoutMutationHandler(editContext, new UserContext(firstUser), TimeProvider.System);
            WorkoutExerciseSnapshotValues original = started.Exercises[0];
            WorkoutSetSnapshotValues completed = original.Sets[0] with
            {
                WeightKg = 100,
                Repetitions = 8,
                Rir = 2,
                IsCompleted = true,
            };
            var added = new WorkoutExerciseSnapshotValues(
                Guid.NewGuid(), baseIds[1], "client supplied name is ignored", 1, 8, 12,
                null, 120, null,
                [new WorkoutSetSnapshotValues(Guid.NewGuid(), null, null, null, null, false)]);
            WorkoutSnapshot edited = await handler.EditAsync(EditWorkoutMutation.Create(
                Metadata(), workoutId, 1,
                [added, original with { Sets = [completed, .. original.Sets.Skip(1)] }]));
            Assert.AreEqual(2, edited.Version);
            Assert.AreNotEqual("client supplied name is ignored", edited.Exercises[0].ExerciseNameSnapshot);
            Assert.IsNotNull(edited.Exercises[1].Sets[0].CompletedAtUtc);
            Assert.AreEqual(1, await editContext.WorkoutTemplateItems.CountAsync(item => item.TemplateId == templateId));

            await Assert.ThrowsAsync<WorkoutValidationException>(() => handler.EditAsync(EditWorkoutMutation.Create(
                Metadata(), workoutId, 2,
                [edited.Exercises[0] with
                {
                    Sets = [new WorkoutSetSnapshotValues(Guid.NewGuid(), -1, 0, 11, null, true)],
                }])));
            editContext.ChangeTracker.Clear();
            Assert.AreEqual(2, (await editContext.Workouts.SingleAsync(item => item.Id == workoutId)).Version);
            Assert.AreEqual(2, await editContext.WorkoutExercises.CountAsync(item => item.WorkoutId == workoutId));
        }
    }

    [TestMethod]
    public async Task PreviousPerformanceUsesLatestCompletedOwnWorkoutOnly()
    {
        (string connectionString, Guid firstUser, Guid secondUser) = await CreateDatabaseAsync();
        Guid sourceExerciseId;
        await using (AppDbContext catalog = Fixture.CreateContext(connectionString, firstUser))
        {
            sourceExerciseId = await catalog.Exercises.Where(item => item.OwnerUserId == null)
                .Select(item => item.Id).FirstAsync();
        }
        await AddHistoricalWorkoutAsync(connectionString, firstUser, sourceExerciseId, new DateTime(2026, 8, 1, 12, 0, 0, DateTimeKind.Utc), 100, WorkoutStatus.Completed);
        await AddHistoricalWorkoutAsync(connectionString, firstUser, sourceExerciseId, new DateTime(2026, 8, 2, 12, 0, 0, DateTimeKind.Utc), 110, WorkoutStatus.Running);
        await AddHistoricalWorkoutAsync(connectionString, firstUser, sourceExerciseId, new DateTime(2026, 8, 3, 12, 0, 0, DateTimeKind.Utc), 120, WorkoutStatus.Discarded);
        await AddHistoricalWorkoutAsync(connectionString, secondUser, sourceExerciseId, new DateTime(2026, 8, 4, 12, 0, 0, DateTimeKind.Utc), 200, WorkoutStatus.Completed);

        await using (AppDbContext firstContext = Fixture.CreateContext(connectionString, firstUser))
        {
            var queries = new PreviousPerformanceQueries(firstContext);
            PreviousExercisePerformance? previous = await queries.GetAsync(
                sourceExerciseId,
                new DateTime(2026, 8, 10, 0, 0, 0, DateTimeKind.Utc));
            Assert.IsNotNull(previous);
            Assert.AreEqual(100, previous.Sets[0].WeightKg);
        }
        await using (AppDbContext secondContext = Fixture.CreateContext(connectionString, secondUser))
        {
            PreviousExercisePerformance? previous = await new PreviousPerformanceQueries(secondContext).GetAsync(
                sourceExerciseId,
                new DateTime(2026, 8, 10, 0, 0, 0, DateTimeKind.Utc));
            Assert.AreEqual(200, previous?.Sets[0].WeightKg);
        }
    }

    [TestMethod]
    public async Task CompletionAndRotationCommitAtomicallyAsOneCapturedChangeBatch()
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        Guid sourceExerciseId;
        await using (AppDbContext catalog = Fixture.CreateContext(connectionString, userId))
        {
            sourceExerciseId = await catalog.Exercises.Where(item => item.OwnerUserId == null)
                .Select(item => item.Id).FirstAsync();
        }
        Guid templateId = Guid.NewGuid();
        Guid rotationId = Guid.NewGuid();
        await using (AppDbContext planning = Fixture.CreateContext(connectionString, userId))
        {
            await new WorkoutTemplateMutationHandler(planning, new UserContext(userId), TimeProvider.System)
                .SaveAsync(SaveWorkoutTemplateMutation.Create(
                    Metadata(), templateId, 0, "Plan",
                    [new WorkoutTemplateItemValues(Guid.NewGuid(), sourceExerciseId, 1, 8, 8)]));
            await new WorkoutRotationHandler(planning, new UserContext(userId), TimeProvider.System)
                .SaveAsync(SaveWorkoutRotationMutation.Create(
                    Metadata(), rotationId, 0,
                    [new WorkoutRotationEntry(Guid.NewGuid(), templateId)]));
        }

        Guid workoutId = Guid.NewGuid();
        await using (AppDbContext execution = Fixture.CreateContext(connectionString, userId))
        {
            var handler = new WorkoutMutationHandler(execution, new UserContext(userId), TimeProvider.System);
            WorkoutSnapshot started = await handler.StartAsync(StartWorkoutMutation.Create(Metadata(), workoutId, templateId));
            WorkoutExerciseSnapshotValues exercise = started.Exercises[0];
            WorkoutSetSnapshotValues completedSet = exercise.Sets[0] with { WeightKg = 100, Repetitions = 8, IsCompleted = true };
            await handler.EditAsync(EditWorkoutMutation.Create(
                Metadata(), workoutId, 1, [exercise with { Sets = [completedSet] }]));
        }

        var collector = new ChangeCollector();
        await using (AppDbContext completion = Fixture.CreateContext(connectionString, userId))
        {
            var handler = new WorkoutMutationHandler(completion, new UserContext(userId), TimeProvider.System, collector);
            CompleteWorkoutResult result = await handler.CompleteAsync(
                CompleteWorkoutMutation.Create(Metadata(), workoutId, 2, rotationId, 1));
            Assert.AreEqual(WorkoutStatus.Completed, result.Workout.Status);
            Assert.AreEqual(2, result.Rotation?.Version);
            Assert.AreEqual(templateId, result.Rotation?.LastCompletedTemplateId);
            Assert.HasCount(2, collector.Changes);
            Assert.IsTrue(collector.Changes.All(change => change is UpsertedResourceChange));
        }
        await using (AppDbContext rename = Fixture.CreateContext(connectionString, userId))
        {
            WorkoutTemplate template = await rename.WorkoutTemplates.SingleAsync(item => item.Id == templateId);
            template.Name = "Renamed after completion";
            template.Version++;
            await rename.SaveChangesAsync();
        }
        await using (AppDbContext historyContext = Fixture.CreateContext(connectionString, userId))
        {
            var history = new WorkoutHistoryQueries(historyContext);
            IReadOnlyList<WorkoutHistorySummary> list = await history.ListAsync(0, 20);
            WorkoutSnapshot? detail = await history.GetAsync(workoutId);
            Assert.IsTrue(list.Any(item => item.WorkoutId == workoutId && item.CompletedSetCount == 1));
            Assert.AreEqual("Plan", detail?.TemplateNameSnapshot);
            WorkoutSet historicalSet = await historyContext.WorkoutSets.FirstAsync(item => item.WorkoutId == workoutId);
            historicalSet.WeightKg = 999;
            await Assert.ThrowsAsync<HistoricalWorkoutImmutableException>(() => historyContext.SaveChangesAsync());
        }
        await using (AppDbContext foreignHistory = Fixture.CreateContext(connectionString, Guid.NewGuid()))
        {
            Assert.IsNull(await new WorkoutHistoryQueries(foreignHistory).GetAsync(workoutId));
        }

        Guid rollbackWorkoutId = Guid.NewGuid();
        await using (AppDbContext prepareRollback = Fixture.CreateContext(connectionString, userId))
        {
            var handler = new WorkoutMutationHandler(prepareRollback, new UserContext(userId), TimeProvider.System);
            WorkoutSnapshot started = await handler.StartAsync(StartWorkoutMutation.Create(Metadata(), rollbackWorkoutId, templateId));
            WorkoutExerciseSnapshotValues exercise = started.Exercises[0];
            await handler.EditAsync(EditWorkoutMutation.Create(
                Metadata(), rollbackWorkoutId, 1,
                [exercise with { Sets = [exercise.Sets[0] with { WeightKg = 90, Repetitions = 8, IsCompleted = true }] }]));
        }
        await using (AppDbContext stale = Fixture.CreateContext(connectionString, userId))
        {
            var handler = new WorkoutMutationHandler(stale, new UserContext(userId), TimeProvider.System);
            await Assert.ThrowsAsync<WorkoutRotationConflictException>(() => handler.CompleteAsync(
                CompleteWorkoutMutation.Create(Metadata(), rollbackWorkoutId, 2, rotationId, 1)));
            stale.ChangeTracker.Clear();
            Workout unchanged = await stale.Workouts.SingleAsync(item => item.Id == rollbackWorkoutId);
            Assert.AreEqual(WorkoutStatus.Running, unchanged.Status);
            Assert.AreEqual(2, unchanged.Version);
            Assert.AreEqual(2, (await stale.WorkoutRotations.SingleAsync()).Version);
        }

        Guid emptyWorkoutId = Guid.NewGuid();
        await using (AppDbContext empty = Fixture.CreateContext(connectionString, userId))
        {
            var handler = new WorkoutMutationHandler(empty, new UserContext(userId), TimeProvider.System);
            await handler.StartAsync(StartWorkoutMutation.Create(Metadata(), emptyWorkoutId, templateId));
            await Assert.ThrowsAsync<WorkoutValidationException>(() => handler.CompleteAsync(
                CompleteWorkoutMutation.Create(Metadata(), emptyWorkoutId, 1, rotationId, 2)));
            empty.ChangeTracker.Clear();
            Assert.AreEqual(WorkoutStatus.Running, (await empty.Workouts.SingleAsync(item => item.Id == emptyWorkoutId)).Status);
            Assert.AreEqual(2, (await empty.WorkoutRotations.SingleAsync()).Version);
        }
        Guid discardedWorkoutId = Guid.NewGuid();
        await using (AppDbContext discard = Fixture.CreateContext(connectionString, userId))
        {
            var handler = new WorkoutMutationHandler(discard, new UserContext(userId), TimeProvider.System);
            await handler.StartAsync(StartWorkoutMutation.Create(Metadata(), discardedWorkoutId, templateId));
            WorkoutSnapshot discarded = await handler.DiscardAsync(
                DiscardWorkoutMutation.Create(Metadata(), discardedWorkoutId, 1));
            Assert.AreEqual(WorkoutStatus.Discarded, discarded.Status);
            Assert.AreEqual(2, (await discard.WorkoutRotations.SingleAsync()).Version);
            Assert.IsFalse((await new WorkoutHistoryQueries(discard).ListAsync(0, 100))
                .Any(item => item.WorkoutId == discardedWorkoutId));
        }
    }

    private static Workout Workout(Guid id, string name, DateTime started) => new()
    {
        Id = id,
        TemplateNameSnapshot = name,
        Status = WorkoutStatus.Running,
        StartedAtUtc = started,
        UpdatedAtUtc = started,
        Version = 1,
    };

    private static WorkoutExercise Exercise(Guid id, Guid workoutId, string name, int position) => new()
    {
        Id = id,
        WorkoutId = workoutId,
        ExerciseNameSnapshot = name,
        Position = position,
        PlannedSets = 3,
        MinimumRepetitions = 6,
        MaximumRepetitions = 8,
        TargetRir = 2,
        RestSeconds = 180,
        Notes = "snapshot note",
    };

    private static async Task<(string ConnectionString, Guid FirstUser, Guid SecondUser)> CreateDatabaseAsync()
    {
        string connectionString = await Fixture.CreateIsolatedDatabaseAsync();
        await using (AppDbContext context = Fixture.CreateContext(connectionString))
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

    private static async Task AddHistoricalWorkoutAsync(
        string connectionString,
        Guid userId,
        Guid sourceExerciseId,
        DateTime eventAt,
        decimal weight,
        WorkoutStatus status)
    {
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        Guid workoutId = Guid.NewGuid();
        Guid exerciseId = Guid.NewGuid();
        context.Workouts.Add(new Workout
        {
            Id = workoutId,
            TemplateNameSnapshot = "Historical",
            Status = status,
            StartedAtUtc = eventAt.AddHours(-1),
            CompletedAtUtc = status == WorkoutStatus.Completed ? eventAt : null,
            DiscardedAtUtc = status == WorkoutStatus.Discarded ? eventAt : null,
            UpdatedAtUtc = eventAt,
            Version = 1,
        });
        context.WorkoutExercises.Add(new WorkoutExercise
        {
            Id = exerciseId,
            WorkoutId = workoutId,
            SourceExerciseId = sourceExerciseId,
            ExerciseNameSnapshot = "Snapshot",
            Position = 0,
            PlannedSets = 1,
            MinimumRepetitions = 8,
            MaximumRepetitions = 8,
            WorkoutCompletedAtUtc = status == WorkoutStatus.Completed ? eventAt : null,
        });
        context.WorkoutSets.Add(new WorkoutSet
        {
            Id = Guid.NewGuid(),
            WorkoutId = workoutId,
            WorkoutExerciseId = exerciseId,
            Position = 0,
            WeightKg = weight,
            Repetitions = 8,
            IsCompleted = true,
            CompletedAtUtc = eventAt,
        });
        await context.SaveChangesAsync();
    }

    private static MutationMetadata Metadata() => MutationMetadata.Create(Guid.NewGuid(), Guid.NewGuid(), 1);

    private sealed record UserContext(Guid Value) : IUserContext
    {
        Guid? IUserContext.UserId => Value;
    }
}
