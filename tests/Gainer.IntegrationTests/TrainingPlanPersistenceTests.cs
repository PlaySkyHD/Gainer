using Gainer.Core.Mutations;
using Gainer.Core.Security;
using Gainer.Core.Training;
using Gainer.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Gainer.IntegrationTests;

[TestClass]
[DoNotParallelize]
public sealed class TrainingPlanPersistenceTests
{
    public TestContext TestContext { get; set; } = null!;

    private static PostgreSqlTestFixture? fixture;
    private static PostgreSqlTestFixture Fixture => fixture
        ?? throw new InvalidOperationException("The PostgreSQL fixture has not started.");

    private static readonly int[] ReorderedSortOrder = [0, 1, 2];
    private static readonly int[] SortOrderAfterRejectedReorder = [0, 2, 1];

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
    public async Task SavesOrderedEntriesAndReplacesThemAtomicallyOnUpdate()
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        Guid[] exerciseIds = await BaseExerciseIdsAsync(connectionString, userId, 2);
        Guid planId = Guid.NewGuid();
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        var handler = Handler(context, userId);
        await handler.CreateAsync(CreateTrainingPlanMutation.Create(Metadata(), Plan(planId, "Push", [
            Entry(exerciseIds[0], 2, 3), Entry(exerciseIds[1], 0, 3),
        ])), TestContext.CancellationToken);

        TrainingPlanSnapshot updated = await handler.UpdateAsync(UpdateTrainingPlanMutation.Create(Metadata(), 1, Plan(planId, "Push A", [
            Entry(exerciseIds[1], 0, 4),
        ])), TestContext.CancellationToken);

        Assert.AreEqual(2, updated.Version);
        Assert.AreEqual("Push A", updated.Name);
        Assert.HasCount(1, updated.Entries);
        Assert.AreEqual(4, updated.Entries[0].WorkingSets);
        Assert.AreEqual(1, await context.TrainingPlanEntries.CountAsync(item => item.PlanId == planId, TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task InvalidPlanIsRejectedWithFieldErrorAndKeepsPreviousState()
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        Guid[] exerciseIds = await BaseExerciseIdsAsync(connectionString, userId, 1);
        Guid planId = Guid.NewGuid();
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        var handler = Handler(context, userId);
        await handler.CreateAsync(CreateTrainingPlanMutation.Create(Metadata(), Plan(planId, "Push", [Entry(exerciseIds[0], 0, 3)])), TestContext.CancellationToken);

        TrainingPlanValidationException error = await Assert.ThrowsAsync<TrainingPlanValidationException>(() =>
            handler.UpdateAsync(UpdateTrainingPlanMutation.Create(Metadata(), 1, Plan(planId, "Broken", [Entry(exerciseIds[0], 0, 0)])), TestContext.CancellationToken));

        Assert.IsTrue(error.Errors.ContainsKey("Entries[0].WorkingSets"));
        context.ChangeTracker.Clear();
        Assert.AreEqual("Push", (await context.TrainingPlans.SingleAsync(TestContext.CancellationToken)).Name);
        Assert.AreEqual(1, await context.TrainingPlanEntries.CountAsync(TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task PostgreSqlRejectsEntryWithoutSetsAndDuplicatePlanPosition()
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        Guid[] exerciseIds = await BaseExerciseIdsAsync(connectionString, userId, 1);
        Guid planId = Guid.NewGuid();
        await using (AppDbContext context = Fixture.CreateContext(connectionString, userId))
        {
            context.TrainingPlans.Add(PlanRow(planId, "Push", 0));
            context.TrainingPlanEntries.Add(EntryRow(planId, 0, exerciseIds[0], 0, 0));
            await Assert.ThrowsAsync<DbUpdateException>(() => context.SaveChangesAsync(TestContext.CancellationToken));
        }
        await using (AppDbContext context = Fixture.CreateContext(connectionString, userId))
        {
            context.TrainingPlanEntries.Add(EntryRow(planId, 0, exerciseIds[0], 2, 3));
            context.TrainingPlanEntries.Add(EntryRow(planId, 0, exerciseIds[0], 2, 3));
            await Assert.ThrowsAsync<DbUpdateException>(() => context.SaveChangesAsync(TestContext.CancellationToken));
        }
    }

    [TestMethod]
    public async Task ArchivedPlanCannotChangeAndForeignPlanIsNotFound()
    {
        (string connectionString, Guid firstUser, Guid secondUser) = await CreateDatabaseAsync();
        Guid[] exerciseIds = await BaseExerciseIdsAsync(connectionString, firstUser, 1);
        Guid planId = Guid.NewGuid();
        await using AppDbContext context = Fixture.CreateContext(connectionString, firstUser);
        var handler = Handler(context, firstUser);
        await handler.CreateAsync(CreateTrainingPlanMutation.Create(Metadata(), Plan(planId, "Push", [Entry(exerciseIds[0], 1, 2)])), TestContext.CancellationToken);
        TrainingPlanSnapshot archived = await handler.ArchiveAsync(ArchiveTrainingPlanMutation.Create(Metadata(), planId, 1), TestContext.CancellationToken);
        Assert.IsTrue(archived.IsArchived);

        await Assert.ThrowsAsync<TrainingPlanConflictException>(() => handler.UpdateAsync(
            UpdateTrainingPlanMutation.Create(Metadata(), 2, Plan(planId, "Again", [Entry(exerciseIds[0], 1, 2)])), TestContext.CancellationToken));

        await using AppDbContext foreign = Fixture.CreateContext(connectionString, secondUser);
        var intruder = Handler(foreign, secondUser);
        await Assert.ThrowsAsync<TrainingPlanNotFoundException>(() => intruder.UpdateAsync(
            UpdateTrainingPlanMutation.Create(Metadata(), 2, Plan(planId, "Stolen", [Entry(exerciseIds[0], 1, 2)])), TestContext.CancellationToken));
        await Assert.ThrowsAsync<TrainingPlanNotFoundException>(() => intruder.ArchiveAsync(
            ArchiveTrainingPlanMutation.Create(Metadata(), planId, 1), TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task NewPlansAppendAndReorderIsAtomicWithPerPlanVersionExpectation()
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        Guid[] exerciseIds = await BaseExerciseIdsAsync(connectionString, userId, 1);
        Guid push = Guid.NewGuid();
        Guid pull = Guid.NewGuid();
        Guid legs = Guid.NewGuid();
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        var handler = Handler(context, userId);
        await handler.CreateAsync(CreateTrainingPlanMutation.Create(Metadata(), Plan(push, "Push", [Entry(exerciseIds[0], 0, 3)])), TestContext.CancellationToken);
        await handler.CreateAsync(CreateTrainingPlanMutation.Create(Metadata(), Plan(pull, "Pull", [Entry(exerciseIds[0], 0, 3)])), TestContext.CancellationToken);
        TrainingPlanSnapshot third = await handler.CreateAsync(CreateTrainingPlanMutation.Create(Metadata(), Plan(legs, "Legs", [Entry(exerciseIds[0], 0, 3)])), TestContext.CancellationToken);
        Assert.AreEqual(2, third.SortOrder);

        IReadOnlyList<TrainingPlanSnapshot> reordered = await handler.ReorderAsync(ReorderTrainingPlansMutation.Create(Metadata(),
            [new TrainingPlanVersion(legs, 1), new TrainingPlanVersion(push, 1), new TrainingPlanVersion(pull, 1)]), TestContext.CancellationToken);
        CollectionAssert.AreEqual(new[] { legs, push, pull }, reordered.Select(item => item.PlanId).ToArray());
        CollectionAssert.AreEqual(ReorderedSortOrder, reordered.Select(item => item.SortOrder).ToArray());
        Assert.IsTrue(reordered.All(item => item.Version == 2));

        await Assert.ThrowsAsync<TrainingPlanConflictException>(() => handler.ReorderAsync(ReorderTrainingPlansMutation.Create(Metadata(),
            [new TrainingPlanVersion(push, 1), new TrainingPlanVersion(legs, 2)]), TestContext.CancellationToken));
        context.ChangeTracker.Clear();
        CollectionAssert.AreEqual(SortOrderAfterRejectedReorder, (await context.TrainingPlans.OrderBy(item => item.Name)
            .Select(item => item.SortOrder).ToListAsync(TestContext.CancellationToken)).ToArray());
    }

    [TestMethod]
    public async Task RotationRejectsForeignArchivedAndDuplicatePlansAndAllowsOneRotationPerUser()
    {
        (string connectionString, Guid firstUser, Guid secondUser) = await CreateDatabaseAsync();
        Guid[] exerciseIds = await BaseExerciseIdsAsync(connectionString, firstUser, 1);
        Guid push = Guid.NewGuid();
        Guid archivedPlan = Guid.NewGuid();
        Guid foreignPlan = await CreatePlanAsync(connectionString, secondUser, exerciseIds[0], "Foreign");
        await using AppDbContext context = Fixture.CreateContext(connectionString, firstUser);
        var handler = new WorkoutRotationHandler(context, new CurrentUser(firstUser), TimeProvider.System);
        await Handler(context, firstUser).CreateAsync(CreateTrainingPlanMutation.Create(Metadata(), Plan(push, "Push", [Entry(exerciseIds[0], 0, 3)])), TestContext.CancellationToken);
        await Handler(context, firstUser).CreateAsync(CreateTrainingPlanMutation.Create(Metadata(), Plan(archivedPlan, "Old", [Entry(exerciseIds[0], 0, 3)])), TestContext.CancellationToken);
        await Handler(context, firstUser).ArchiveAsync(ArchiveTrainingPlanMutation.Create(Metadata(), archivedPlan, 1), TestContext.CancellationToken);

        Guid rotationId = Guid.NewGuid();
        WorkoutRotationValidationException foreign = await Assert.ThrowsAsync<WorkoutRotationValidationException>(() =>
            handler.SaveAsync(SaveWorkoutRotationMutation.Create(Metadata(), rotationId, 0, [push, foreignPlan]), TestContext.CancellationToken));
        Assert.IsTrue(foreign.Errors.ContainsKey("PlanIds"));
        await Assert.ThrowsAsync<WorkoutRotationValidationException>(() =>
            handler.SaveAsync(SaveWorkoutRotationMutation.Create(Metadata(), rotationId, 0, [push, archivedPlan]), TestContext.CancellationToken));
        await Assert.ThrowsAsync<WorkoutRotationValidationException>(() =>
            handler.SaveAsync(SaveWorkoutRotationMutation.Create(Metadata(), rotationId, 0, [push, push]), TestContext.CancellationToken));

        WorkoutRotationSnapshot saved = await handler.SaveAsync(SaveWorkoutRotationMutation.Create(Metadata(), rotationId, 0, [push]), TestContext.CancellationToken);
        Assert.AreEqual(1, saved.Version);
        Assert.HasCount(1, saved.PlanIds);
        await Assert.ThrowsAsync<WorkoutRotationConflictException>(() =>
            handler.SaveAsync(SaveWorkoutRotationMutation.Create(Metadata(), Guid.NewGuid(), 0, [push]), TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task NextPlanFollowsLastFinishedRotationWorkoutAndWrapsAround()
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        Guid[] exerciseIds = await BaseExerciseIdsAsync(connectionString, userId, 1);
        Guid push = await CreatePlanAsync(connectionString, userId, exerciseIds[0], "Push");
        Guid pull = await CreatePlanAsync(connectionString, userId, exerciseIds[0], "Pull");
        Guid legs = await CreatePlanAsync(connectionString, userId, exerciseIds[0], "Legs");
        await SaveRotationAsync(connectionString, userId, [push, pull, legs]);
        DateTime day = new(2026, 8, 18, 17, 0, 0, DateTimeKind.Utc);
        await FinishWorkoutAsync(connectionString, userId, push, day, Guid.NewGuid());

        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        Assert.AreEqual(pull, await new WorkoutRotationQueries(context).NextPlanIdAsync(TestContext.CancellationToken));
        await FinishWorkoutAsync(connectionString, userId, legs, day.AddDays(1), Guid.NewGuid());
        Assert.AreEqual(push, await new WorkoutRotationQueries(context).NextPlanIdAsync(TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task NextPlanReturnsPreviousPlanAgainWhenLastFinishedRotationWorkoutWasDeleted()
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        Guid[] exerciseIds = await BaseExerciseIdsAsync(connectionString, userId, 1);
        Guid push = await CreatePlanAsync(connectionString, userId, exerciseIds[0], "Push");
        Guid pull = await CreatePlanAsync(connectionString, userId, exerciseIds[0], "Pull");
        await SaveRotationAsync(connectionString, userId, [push, pull]);
        DateTime day = new(2026, 8, 18, 17, 0, 0, DateTimeKind.Utc);
        await FinishWorkoutAsync(connectionString, userId, push, day, Guid.NewGuid());
        Guid pullWorkoutId = Guid.NewGuid();
        await FinishWorkoutAsync(connectionString, userId, pull, day.AddDays(1), pullWorkoutId);

        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        Assert.AreEqual(push, await new WorkoutRotationQueries(context).NextPlanIdAsync(TestContext.CancellationToken));
        await new WorkoutMutationHandler(context, new CurrentUser(userId), TimeProvider.System)
            .DeleteAsync(DeleteWorkoutMutation.Create(Metadata(), pullWorkoutId, 1), TestContext.CancellationToken);
        Assert.AreEqual(pull, await new WorkoutRotationQueries(context).NextPlanIdAsync(TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task EmptyOrMissingRotationSuggestsNothing()
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        await using (AppDbContext context = Fixture.CreateContext(connectionString, userId))
        {
            Assert.IsNull(await new WorkoutRotationQueries(context).NextPlanIdAsync(TestContext.CancellationToken));
        }
        await SaveRotationAsync(connectionString, userId, []);
        await using AppDbContext emptyContext = Fixture.CreateContext(connectionString, userId);
        Assert.IsNull(await new WorkoutRotationQueries(emptyContext).NextPlanIdAsync(TestContext.CancellationToken));
    }

    private static async Task FinishWorkoutAsync(string connectionString, Guid userId, Guid planId, DateTime started, Guid workoutId)
    {
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        await new WorkoutMutationHandler(context, new CurrentUser(userId), TimeProvider.System).CreateAsync(
            CreateWorkoutMutation.Create(Metadata(), new WorkoutValues(
                workoutId, "Training", null, started, started.AddHours(1), "plan", planId, null, [])));
    }

    private static async Task SaveRotationAsync(string connectionString, Guid userId, Guid[] planIds)
    {
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        await new WorkoutRotationHandler(context, new CurrentUser(userId), TimeProvider.System).SaveAsync(
            SaveWorkoutRotationMutation.Create(Metadata(), Guid.NewGuid(), 0, planIds));
    }

    private static async Task<Guid> CreatePlanAsync(string connectionString, Guid userId, Guid exerciseId, string name)
    {
        Guid planId = Guid.NewGuid();
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        await Handler(context, userId).CreateAsync(CreateTrainingPlanMutation.Create(Metadata(), Plan(planId, name, [Entry(exerciseId, 0, 3)])));
        return planId;
    }

    private static TrainingPlanMutationHandler Handler(AppDbContext context, Guid userId) =>
        new(context, new CurrentUser(userId), TimeProvider.System);

    private static TrainingPlanValues Plan(Guid planId, string name, IReadOnlyList<TrainingPlanEntryValues> entries) =>
        new(planId, name, null, "exercise", entries);

    private static TrainingPlanEntryValues Entry(Guid exerciseId, int warmupSets, int workingSets) =>
        new(Guid.NewGuid(), exerciseId, warmupSets, workingSets, null, null);

    private static TrainingPlan PlanRow(Guid id, string name, int sortOrder) => new()
    {
        Id = id,
        Name = name,
        PreviousValueSource = PreviousValueSource.Exercise,
        SortOrder = sortOrder,
        CreatedAtUtc = DateTime.UtcNow,
        UpdatedAtUtc = DateTime.UtcNow,
        Version = 1,
    };

    private static TrainingPlanEntry EntryRow(Guid planId, int position, Guid exerciseId, int warmup, int working) => new()
    {
        Id = Guid.NewGuid(),
        PlanId = planId,
        Position = position,
        ExerciseId = exerciseId,
        WarmupSets = warmup,
        WorkingSets = working,
    };

    private static MutationMetadata Metadata() => MutationMetadata.Create(Guid.NewGuid(), Guid.NewGuid(), 1);

    private static async Task<Guid[]> BaseExerciseIdsAsync(string connectionString, Guid userId, int count)
    {
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        return await context.Exercises.Where(item => item.OwnerUserId == null)
            .OrderBy(item => item.Id).Select(item => item.Id).Take(count).ToArrayAsync();
    }

    private static async Task<(string ConnectionString, Guid FirstUser, Guid SecondUser)> CreateDatabaseAsync()
    {
        string connectionString = await Fixture.CreateIsolatedDatabaseAsync();
        await using AppDbContext context = Fixture.CreateContext(connectionString);
        await context.Database.MigrateAsync();
        Guid first = Guid.NewGuid();
        Guid second = Guid.NewGuid();
        context.Users.AddRange(User(first), User(second));
        await context.SaveChangesAsync();
        return (connectionString, first, second);
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
