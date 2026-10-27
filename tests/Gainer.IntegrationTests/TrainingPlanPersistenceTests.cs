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
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
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
    public async Task ReplacingEntriesWithStableIdsIsNotAConflict()
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        Guid[] exerciseIds = await BaseExerciseIdsAsync(connectionString, userId, 1);
        Guid planId = Guid.NewGuid();
        Guid a = Guid.NewGuid(), b = Guid.NewGuid(), c = Guid.NewGuid(), added = Guid.NewGuid();
        TrainingPlanEntryValues E(Guid id) => new(id, exerciseIds[0], 1, 2, null, null);
        TrainingPlanEntryValues[][] saves =
        [
            [E(a), E(b), E(c)],
            // Deleting the first entry moves the others up.
            [E(b), E(c)],
            // A new first entry moves the others down.
            [E(added), E(b), E(c)],
            // Swapping two entries.
            [E(added), E(c), E(b)],
        ];

        for (int index = 0; index < saves.Length; index++)
        {
            await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
            var handler = Handler(context, userId);
            TrainingPlanSnapshot saved = index == 0
                ? await handler.CreateAsync(CreateTrainingPlanMutation.Create(Metadata(), Plan(planId, "Push", saves[index])), TestContext.CancellationToken)
                : await handler.UpdateAsync(UpdateTrainingPlanMutation.Create(Metadata(), index, Plan(planId, "Push", saves[index])), TestContext.CancellationToken);
            Assert.AreEqual(index + 1, saved.Version);
        }

        await using AppDbContext read = PostgreSqlTestFixture.CreateContext(connectionString, userId);
        List<TrainingPlanEntry> stored = await read.TrainingPlanEntries.AsNoTracking()
            .Where(item => item.PlanId == planId).OrderBy(item => item.Position).ToListAsync(TestContext.CancellationToken);
        Assert.AreSequenceEqual(new[] { added, c, b }, stored.Select(item => item.Id).ToArray());
    }

    [TestMethod]
    public async Task UpdateWithWrongVersionOnActivePlanIsAConflictAndKeepsEntries()
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        Guid[] exerciseIds = await BaseExerciseIdsAsync(connectionString, userId, 1);
        Guid planId = Guid.NewGuid();
        Guid entryId = Guid.NewGuid();
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
        var handler = Handler(context, userId);
        await handler.CreateAsync(CreateTrainingPlanMutation.Create(
            Metadata(), Plan(planId, "Push", [new TrainingPlanEntryValues(entryId, exerciseIds[0], 1, 2, null, null)])), TestContext.CancellationToken);

        foreach (long wrongVersion in new long[] { 2, 7 })
        {
            await Assert.ThrowsAsync<TrainingPlanConflictException>(() => handler.UpdateAsync(
                UpdateTrainingPlanMutation.Create(Metadata(), wrongVersion, Plan(planId, "Changed", [Entry(exerciseIds[0], 0, 5)])), TestContext.CancellationToken));
        }

        context.ChangeTracker.Clear();
        TrainingPlan stored = await context.TrainingPlans.SingleAsync(TestContext.CancellationToken);
        Assert.AreEqual("Push", stored.Name);
        Assert.AreEqual(1, stored.Version);
        Assert.IsFalse(stored.IsArchived);
        Assert.AreEqual(entryId, (await context.TrainingPlanEntries.SingleAsync(TestContext.CancellationToken)).Id);
    }

    [TestMethod]
    public async Task InvalidPlanIsRejectedWithFieldErrorAndKeepsPreviousState()
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        Guid[] exerciseIds = await BaseExerciseIdsAsync(connectionString, userId, 1);
        Guid planId = Guid.NewGuid();
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
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
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId))
        {
            context.TrainingPlans.Add(PlanRow(planId, "Push", 0));
            context.TrainingPlanEntries.Add(EntryRow(planId, 0, exerciseIds[0], 0, 0));
            await Assert.ThrowsAsync<DbUpdateException>(() => context.SaveChangesAsync(TestContext.CancellationToken));
        }
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId))
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
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, firstUser);
        var handler = Handler(context, firstUser);
        await handler.CreateAsync(CreateTrainingPlanMutation.Create(Metadata(), Plan(planId, "Push", [Entry(exerciseIds[0], 1, 2)])), TestContext.CancellationToken);
        TrainingPlanSnapshot archived = await handler.ArchiveAsync(ArchiveTrainingPlanMutation.Create(Metadata(), planId, 1), TestContext.CancellationToken);
        Assert.IsTrue(archived.IsArchived);

        await Assert.ThrowsAsync<TrainingPlanConflictException>(() => handler.UpdateAsync(
            UpdateTrainingPlanMutation.Create(Metadata(), 2, Plan(planId, "Again", [Entry(exerciseIds[0], 1, 2)])), TestContext.CancellationToken));

        await using AppDbContext foreign = PostgreSqlTestFixture.CreateContext(connectionString, secondUser);
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
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
        var handler = Handler(context, userId);
        await handler.CreateAsync(CreateTrainingPlanMutation.Create(Metadata(), Plan(push, "Push", [Entry(exerciseIds[0], 0, 3)])), TestContext.CancellationToken);
        await handler.CreateAsync(CreateTrainingPlanMutation.Create(Metadata(), Plan(pull, "Pull", [Entry(exerciseIds[0], 0, 3)])), TestContext.CancellationToken);
        TrainingPlanSnapshot third = await handler.CreateAsync(CreateTrainingPlanMutation.Create(Metadata(), Plan(legs, "Legs", [Entry(exerciseIds[0], 0, 3)])), TestContext.CancellationToken);
        Assert.AreEqual(2, third.SortOrder);

        IReadOnlyList<TrainingPlanSnapshot> reordered = await handler.ReorderAsync(ReorderTrainingPlansMutation.Create(Metadata(),
            [new TrainingPlanVersion(legs, 1), new TrainingPlanVersion(push, 1), new TrainingPlanVersion(pull, 1)]), TestContext.CancellationToken);
        Assert.AreSequenceEqual(new[] { legs, push, pull }, reordered.Select(item => item.PlanId).ToArray());
        Assert.AreSequenceEqual(ReorderedSortOrder, reordered.Select(item => item.SortOrder).ToArray());
        Assert.IsTrue(reordered.All(item => item.Version == 2));

        await Assert.ThrowsAsync<TrainingPlanConflictException>(() => handler.ReorderAsync(ReorderTrainingPlansMutation.Create(Metadata(),
            [new TrainingPlanVersion(push, 1), new TrainingPlanVersion(legs, 2)]), TestContext.CancellationToken));
        context.ChangeTracker.Clear();
        Assert.AreSequenceEqual(SortOrderAfterRejectedReorder, (await context.TrainingPlans.OrderBy(item => item.Name)
            .Select(item => item.SortOrder).ToListAsync(TestContext.CancellationToken)).ToArray());
    }

    [TestMethod]
    public async Task ScheduleRejectsForeignAndUnknownPlansAllowsArchivedPlansAndAllowsOneSchedulePerUser()
    {
        (string connectionString, Guid firstUser, Guid secondUser) = await CreateDatabaseAsync();
        Guid[] exerciseIds = await BaseExerciseIdsAsync(connectionString, firstUser, 1);
        Guid push = Guid.NewGuid();
        Guid archivedPlan = Guid.NewGuid();
        Guid foreignPlan = await CreatePlanAsync(connectionString, secondUser, exerciseIds[0], "Foreign");
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, firstUser);
        var handler = new TrainingScheduleMutationHandler(context, new CurrentUser(firstUser), TimeProvider.System);
        await Handler(context, firstUser).CreateAsync(CreateTrainingPlanMutation.Create(Metadata(), Plan(push, "Push", [Entry(exerciseIds[0], 0, 3)])), TestContext.CancellationToken);
        await Handler(context, firstUser).CreateAsync(CreateTrainingPlanMutation.Create(Metadata(), Plan(archivedPlan, "Old", [Entry(exerciseIds[0], 0, 3)])), TestContext.CancellationToken);
        await Handler(context, firstUser).ArchiveAsync(ArchiveTrainingPlanMutation.Create(Metadata(), archivedPlan, 1), TestContext.CancellationToken);

        Guid scheduleId = Guid.NewGuid();
        TrainingScheduleValidationException foreign = await Assert.ThrowsAsync<TrainingScheduleValidationException>(() =>
            handler.SaveAsync(SaveTrainingScheduleMutation.Create(Metadata(), 0, Schedule(scheduleId, push, foreignPlan)), TestContext.CancellationToken));
        Assert.IsTrue(foreign.Errors.ContainsKey("Slots"));
        TrainingScheduleValidationException unknown = await Assert.ThrowsAsync<TrainingScheduleValidationException>(() =>
            handler.SaveAsync(SaveTrainingScheduleMutation.Create(Metadata(), 0, Schedule(scheduleId, push, Guid.NewGuid())), TestContext.CancellationToken));
        Assert.AreEqual(unknown.Errors["Slots"], foreign.Errors["Slots"]);
        TrainingScheduleValidationException foreignException = await Assert.ThrowsAsync<TrainingScheduleValidationException>(() =>
            handler.SaveAsync(SaveTrainingScheduleMutation.Create(Metadata(), 0, Schedule(scheduleId, push) with
            {
                Exceptions = [new TrainingScheduleExceptionValues(new DateOnly(2026, 10, 22), foreignPlan, null)],
            }), TestContext.CancellationToken));
        Assert.IsTrue(foreignException.Errors.ContainsKey("Exceptions"));
        Assert.AreEqual(0, await context.TrainingSchedules.CountAsync(TestContext.CancellationToken));

        TrainingScheduleSnapshot saved = await handler.SaveAsync(
            SaveTrainingScheduleMutation.Create(Metadata(), 0, Schedule(scheduleId, push, archivedPlan)), TestContext.CancellationToken);
        Assert.AreEqual(1, saved.Version);
        Assert.HasCount(3, saved.Slots);
        await Assert.ThrowsAsync<TrainingScheduleConflictException>(() =>
            handler.SaveAsync(SaveTrainingScheduleMutation.Create(Metadata(), 0, Schedule(Guid.NewGuid(), push)), TestContext.CancellationToken));
    }

    private static TrainingScheduleValues Schedule(Guid scheduleId, params Guid[] planIds) => new(
        scheduleId,
        TrainingScheduleModes.Cycle,
        new DateOnly(2026, 10, 20),
        new DateOnly(2026, 10, 21),
        [.. planIds.Select(id => new TrainingScheduleSlotValues(id)), new TrainingScheduleSlotValues(null)],
        [],
        []);

    private static async Task<Guid> CreatePlanAsync(string connectionString, Guid userId, Guid exerciseId, string name)
    {
        Guid planId = Guid.NewGuid();
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
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
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
        return await context.Exercises.Where(item => item.OwnerUserId == null)
            .OrderBy(item => item.Id).Select(item => item.Id).Take(count).ToArrayAsync();
    }

    private static async Task<(string ConnectionString, Guid FirstUser, Guid SecondUser)> CreateDatabaseAsync()
    {
        string connectionString = await Fixture.CreateIsolatedDatabaseAsync();
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString);
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
