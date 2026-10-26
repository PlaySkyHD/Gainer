using Gainer.Core.Mutations;
using Gainer.Core.Sync;
using Gainer.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using System.Text.Json;
using Gainer.Core.Security;
using Gainer.Core.BodyTracking;
using Gainer.Core.Training;

namespace Gainer.IntegrationTests;

[TestClass]
[DoNotParallelize]
public sealed class SyncPersistenceTests
{
    public TestContext TestContext { get; set; } = null!;

    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private static readonly int[] ExpectedPositions = [0, 1];
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
    public async Task OneRevisionStoresAnUnsplitOrderedMultiResourceBatch()
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        Guid clientId = Guid.NewGuid();
        Guid mutationId = Guid.NewGuid();
        Guid batchId = Guid.NewGuid();
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        context.SyncClients.Add(Client(clientId));
        context.UserSyncStates.Add(new UserSyncState
        {
            CurrentRevision = 1,
            ActiveClientId = clientId,
            UpdatedAtUtc = DateTime.UtcNow,
            Version = 1,
        });
        context.ProcessedMutations.Add(new ProcessedMutation
        {
            MutationId = mutationId,
            ClientId = clientId,
            ClientSequence = 1,
            ContentHash = Enumerable.Repeat((byte)7, 32).ToArray(),
            ResultJson = "{\"status\":\"applied\"}",
            Revision = 1,
            AppliedAtUtc = DateTime.UtcNow,
        });
        context.ChangeBatches.Add(new ChangeBatch
        {
            Id = batchId,
            Revision = 1,
            MutationId = mutationId,
            CreatedAtUtc = DateTime.UtcNow,
        });
        context.ChangeItems.AddRange(
            new ChangeItem
            {
                Id = Guid.NewGuid(),
                BatchId = batchId,
                Position = 0,
                ResourceType = "Workout",
                ResourceId = Guid.NewGuid(),
                ResourceVersion = 3,
                SnapshotJson = "{\"version\":3}",
            },
            new ChangeItem
            {
                Id = Guid.NewGuid(),
                BatchId = batchId,
                Position = 1,
                ResourceType = "TrainingSchedule",
                ResourceId = Guid.NewGuid(),
                ResourceVersion = 2,
                SnapshotJson = "{\"version\":2}",
            });
        await context.SaveChangesAsync(TestContext.CancellationToken);

        context.ChangeTracker.Clear();
        ChangeBatch stored = await context.ChangeBatches.SingleAsync(TestContext.CancellationToken);
        List<ChangeItem> items = await context.ChangeItems.OrderBy(item => item.Position).ToListAsync(TestContext.CancellationToken);
        Assert.AreEqual(1, stored.Revision);
        CollectionAssert.AreEqual(ExpectedPositions, items.Select(item => item.Position).ToArray());
        Assert.IsTrue(items.All(item => item.BatchId == stored.Id));
    }

    [TestMethod]
    public async Task MutationAndRevisionKeysAreUniquePerUserButIndependentAcrossUsers()
    {
        (string connectionString, Guid firstUser, Guid secondUser) = await CreateDatabaseAsync();
        Guid mutationId = Guid.NewGuid();
        await InsertReceiptAsync(connectionString, firstUser, mutationId, revision: 1);
        await InsertReceiptAsync(connectionString, secondUser, mutationId, revision: 1);
        await using AppDbContext duplicate = Fixture.CreateContext(connectionString, firstUser);
        SyncClient client = await duplicate.SyncClients.SingleAsync(TestContext.CancellationToken);
        duplicate.ProcessedMutations.Add(new ProcessedMutation
        {
            MutationId = mutationId,
            ClientId = client.Id,
            ClientSequence = 2,
            ContentHash = new byte[32],
            ResultJson = "{}",
            Revision = 2,
            AppliedAtUtc = DateTime.UtcNow,
        });
        await Assert.ThrowsAsync<DbUpdateException>(() => duplicate.SaveChangesAsync(TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task PostgreSqlRejectsInvalidHashPayloadAndDuplicateBatchPosition()
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        Guid clientId = Guid.NewGuid();
        await using AppDbContext invalid = Fixture.CreateContext(connectionString, userId);
        invalid.SyncClients.Add(Client(clientId));
        invalid.ProcessedMutations.Add(new ProcessedMutation
        {
            MutationId = Guid.NewGuid(),
            ClientId = clientId,
            ClientSequence = 1,
            ContentHash = [1, 2],
            ResultJson = "{}",
            Revision = 1,
            AppliedAtUtc = DateTime.UtcNow,
        });
        await Assert.ThrowsAsync<DbUpdateException>(() => invalid.SaveChangesAsync(TestContext.CancellationToken));

        invalid.ChangeTracker.Clear();
        Guid batchId = Guid.NewGuid();
        invalid.ChangeBatches.Add(new ChangeBatch { Id = batchId, Revision = 1, CreatedAtUtc = DateTime.UtcNow });
        invalid.ChangeItems.Add(new ChangeItem
        {
            Id = Guid.NewGuid(),
            BatchId = batchId,
            Position = 0,
            ResourceType = "Goal",
            ResourceId = Guid.NewGuid(),
            ResourceVersion = 1,
            IsTombstone = true,
            SnapshotJson = "{\"must\":\"be-null\"}",
        });
        await Assert.ThrowsAsync<DbUpdateException>(() => invalid.SaveChangesAsync(TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task ProcessorCommitsDomainReceiptRevisionAndBatchThenReplaysWithoutSideEffects()
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        Guid clientId = Guid.NewGuid();
        await RegisterActiveClientAsync(connectionString, userId, clientId);
        Guid mutationId = Guid.NewGuid();
        Guid checkInId = Guid.NewGuid();
        ProcessSyncMutationCommand command = CreateCheckInCommand(mutationId, clientId, checkInId, 82.5m);

        await using (AppDbContext firstContext = Fixture.CreateContext(connectionString, userId))
        {
            var user = new UserContext(userId);
            var processor = new SyncMutationProcessor(
                firstContext, user, new SyncMutationExecutor(firstContext, user, TimeProvider.System), TimeProvider.System);
            ProcessedSyncMutationResult applied = await processor.ProcessAsync(command, TestContext.CancellationToken);
            Assert.IsFalse(applied.Replayed);
            Assert.AreEqual(1, applied.Revision);
            Assert.HasCount(1, applied.Changes);
        }
        await using (AppDbContext replayContext = Fixture.CreateContext(connectionString, userId))
        {
            var user = new UserContext(userId);
            var processor = new SyncMutationProcessor(
                replayContext, user, new SyncMutationExecutor(replayContext, user, TimeProvider.System), TimeProvider.System);
            ProcessedSyncMutationResult replayed = await processor.ProcessAsync(command, TestContext.CancellationToken);
            Assert.IsTrue(replayed.Replayed);
            Assert.AreEqual(1, replayed.Revision);
            Assert.AreEqual(1, await replayContext.DailyCheckIns.CountAsync(TestContext.CancellationToken));
            Assert.AreEqual(1, await replayContext.ProcessedMutations.CountAsync(TestContext.CancellationToken));
            Assert.AreEqual(1, await replayContext.ChangeBatches.CountAsync(TestContext.CancellationToken));
            Assert.AreEqual(1, (await replayContext.UserSyncStates.SingleAsync(TestContext.CancellationToken)).CurrentRevision);

            ProcessSyncMutationCommand changed = CreateCheckInCommand(mutationId, clientId, checkInId, 90m);
            SyncMutationConflictException conflict = await Assert.ThrowsAsync<SyncMutationConflictException>(
                () => processor.ProcessAsync(changed, TestContext.CancellationToken));
            Assert.AreEqual("mutation_id_reused", conflict.Code);
            Assert.AreEqual(82.5m, (await replayContext.DailyCheckIns.SingleAsync(TestContext.CancellationToken)).WeightKg);
        }
    }

    [TestMethod]
    public async Task OfflineWorkoutEndReplaysAfterLostAcknowledgementAndRejectsChangedRetryAndForeignId()
    {
        (string connectionString, Guid firstUser, Guid secondUser) = await CreateDatabaseAsync();
        Guid firstClient = Guid.NewGuid();
        Guid secondClient = Guid.NewGuid();
        await RegisterActiveClientAsync(connectionString, firstUser, firstClient);
        await RegisterActiveClientAsync(connectionString, secondUser, secondClient);

        Guid exerciseId;
        await using (AppDbContext catalog = Fixture.CreateContext(connectionString, firstUser))
        {
            exerciseId = await catalog.Exercises.Where(item => item.OwnerUserId == null)
                .Select(item => item.Id).FirstAsync(TestContext.CancellationToken);
        }

        Guid workoutId = Guid.NewGuid();
        Guid createMutationId = Guid.NewGuid();
        Guid endMutationId = Guid.NewGuid();
        DateTime started = new(2026, 8, 18, 17, 0, 0, DateTimeKind.Utc);
        Guid workoutExerciseId = Guid.NewGuid();
        Guid setId = Guid.NewGuid();
        ProcessSyncMutationCommand create = Command(
            createMutationId, firstClient, 1, "createWorkout", "Workout", workoutId, 0,
            new { workout = WorkoutPayload(workoutId, started, null, exerciseId, workoutExerciseId, setId, 100, 8) });
        ProcessSyncMutationCommand end = Command(
            endMutationId, firstClient, 2, "saveWorkout", "Workout", workoutId, 1,
            new { baseVersion = 1, workout = WorkoutPayload(workoutId, started, started.AddMinutes(45), exerciseId, workoutExerciseId, setId, 100, 8) },
            createMutationId);

        await using (AppDbContext apply = Fixture.CreateContext(connectionString, firstUser))
        {
            var user = new UserContext(firstUser);
            var processor = new SyncMutationProcessor(
                apply, user, new SyncMutationExecutor(apply, user, TimeProvider.System), TimeProvider.System);
            await processor.ProcessAsync(create, TestContext.CancellationToken);
            ProcessedSyncMutationResult applied = await processor.ProcessAsync(end, TestContext.CancellationToken);
            Assert.IsFalse(applied.Replayed);
            Assert.AreEqual(2, applied.Revision);
        }

        await using (AppDbContext retry = Fixture.CreateContext(connectionString, firstUser))
        {
            var user = new UserContext(firstUser);
            var processor = new SyncMutationProcessor(
                retry, user, new SyncMutationExecutor(retry, user, TimeProvider.System), TimeProvider.System);
            ProcessedSyncMutationResult replayed = await processor.ProcessAsync(end, TestContext.CancellationToken);
            Assert.IsTrue(replayed.Replayed);
            Assert.AreEqual(2, replayed.Revision);
            Assert.IsNotNull((await retry.Workouts.SingleAsync(TestContext.CancellationToken)).EndedAtUtc);
            Assert.AreEqual(2, await retry.ProcessedMutations.CountAsync(TestContext.CancellationToken));

            ProcessSyncMutationCommand changedRetry = Command(
                endMutationId, firstClient, 2, "saveWorkout", "Workout", workoutId, 1,
                new { baseVersion = 1, workout = WorkoutPayload(workoutId, started, null, exerciseId, workoutExerciseId, setId, 100, 8) },
                createMutationId);
            SyncMutationConflictException changed = await Assert.ThrowsAsync<SyncMutationConflictException>(
                () => processor.ProcessAsync(changedRetry, TestContext.CancellationToken));
            Assert.AreEqual("mutation_id_reused", changed.Code);
        }

        await using (AppDbContext foreign = Fixture.CreateContext(connectionString, secondUser))
        {
            var user = new UserContext(secondUser);
            var processor = new SyncMutationProcessor(
                foreign, user, new SyncMutationExecutor(foreign, user, TimeProvider.System), TimeProvider.System);
            ProcessSyncMutationCommand foreignSave = Command(
                Guid.NewGuid(), secondClient, 1, "saveWorkout", "Workout", workoutId, 2,
                new { baseVersion = 2, workout = WorkoutPayload(workoutId, started, null, exerciseId, workoutExerciseId, setId, 100, 8) });
            SyncMutationConflictException denied = await Assert.ThrowsAsync<SyncMutationConflictException>(
                () => processor.ProcessAsync(foreignSave, TestContext.CancellationToken));
            Assert.AreEqual("resource_not_found", denied.Code);
        }
    }

    [TestMethod]
    public async Task UnsupportedOperationAndInactiveClientRollBackWithoutRevisionOrReceipt()
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        Guid activeClient = Guid.NewGuid();
        Guid inactiveClient = Guid.NewGuid();
        await RegisterActiveClientAsync(connectionString, userId, activeClient, inactiveClient);
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        var user = new UserContext(userId);
        var processor = new SyncMutationProcessor(
            context, user, new SyncMutationExecutor(context, user, TimeProvider.System), TimeProvider.System);
        ProcessSyncMutationCommand inactive = CreateCheckInCommand(Guid.NewGuid(), inactiveClient, Guid.NewGuid(), 80m);
        SyncMutationConflictException inactiveError = await Assert.ThrowsAsync<SyncMutationConflictException>(
            () => processor.ProcessAsync(inactive, TestContext.CancellationToken));
        Assert.AreEqual("inactive_client", inactiveError.Code);

        ProcessSyncMutationCommand unsupported = new(
            Guid.NewGuid(),
            new CanonicalMutationContent(
                2, activeClient, 1, "unknownOperation",
                [new CanonicalResourceVersion("DailyCheckIn", Guid.NewGuid(), 0)],
                null,
                JsonDocument.Parse("{}").RootElement.Clone()));
        SyncMutationValidationException invalid = await Assert.ThrowsAsync<SyncMutationValidationException>(
            () => processor.ProcessAsync(unsupported, TestContext.CancellationToken));
        Assert.AreEqual("unsupported_operation", invalid.Code);
        context.ChangeTracker.Clear();
        Assert.AreEqual(0, await context.ProcessedMutations.CountAsync(TestContext.CancellationToken));
        Assert.AreEqual(0, await context.ChangeBatches.CountAsync(TestContext.CancellationToken));
        Assert.AreEqual(0, await context.DailyCheckIns.CountAsync(TestContext.CancellationToken));
        Assert.AreEqual(0, (await context.UserSyncStates.SingleAsync(TestContext.CancellationToken)).CurrentRevision);
    }

    [TestMethod]
    public async Task ChangeFeedPagesWholeBatchesInRevisionOrderAndNeverLeaksAnotherUser()
    {
        (string connectionString, Guid firstUser, Guid secondUser) = await CreateDatabaseAsync();
        Guid firstResource = Guid.NewGuid();
        Guid tombstonedResource = Guid.NewGuid();
        await InsertFeedBatchAsync(connectionString, firstUser, 1,
            ("Workout", firstResource, 1, false, "{\"version\":1}"),
            ("TrainingSchedule", Guid.NewGuid(), 1, false, "{\"version\":1}"));
        await InsertFeedBatchAsync(connectionString, firstUser, 2,
            ("CustomExercise", tombstonedResource, 3, true, null));
        await InsertFeedBatchAsync(connectionString, secondUser, 1,
            ("DailyCheckIn", Guid.NewGuid(), 1, false, "{\"weightKg\":99}"));

        await using AppDbContext firstContext = Fixture.CreateContext(connectionString, firstUser);
        var feed = new SyncChangeFeed(firstContext);
        const int protocol = Gainer.Contracts.Sync.SyncProtocol.CurrentVersion;
        SyncChangeFeedPage firstPage = await feed.GetAsync(0, 1, protocol, TestContext.CancellationToken);
        Assert.AreEqual(1, firstPage.NextCursor);
        Assert.IsTrue(firstPage.HasMore);
        Assert.HasCount(1, firstPage.Batches);
        Assert.HasCount(2, firstPage.Batches[0].Changes);
        Assert.AreEqual(firstResource, firstPage.Batches[0].Changes[0].ResourceId);

        SyncChangeFeedPage secondPage = await feed.GetAsync(firstPage.NextCursor, 1, protocol, TestContext.CancellationToken);
        Assert.AreEqual(2, secondPage.NextCursor);
        Assert.IsFalse(secondPage.HasMore);
        Assert.HasCount(1, secondPage.Batches);
        SyncFeedChange tombstone = secondPage.Batches[0].Changes.Single();
        Assert.AreEqual(tombstonedResource, tombstone.ResourceId);
        Assert.IsTrue(tombstone.IsTombstone);
        Assert.IsNull(tombstone.Snapshot);

        SyncChangeFeedPage replay = await feed.GetAsync(secondPage.NextCursor, 1, protocol, TestContext.CancellationToken);
        Assert.AreEqual(2, replay.NextCursor);
        Assert.IsFalse(replay.HasMore);
        Assert.IsEmpty(replay.Batches);

        await using AppDbContext secondContext = Fixture.CreateContext(connectionString, secondUser);
        SyncChangeFeedPage secondUserPage = await new SyncChangeFeed(secondContext).GetAsync(0, 10, protocol, TestContext.CancellationToken);
        Assert.HasCount(1, secondUserPage.Batches);
        Assert.AreEqual("DailyCheckIn", secondUserPage.Batches[0].Changes.Single().ResourceType);
    }

    [TestMethod]
    public async Task ClientRegistrationKeepsSecondDeviceReadOnlyUntilExplicitTakeover()
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        Guid firstId = Guid.NewGuid();
        Guid secondId = Guid.NewGuid();
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        var registry = new SyncClientRegistry(context, new UserContext(userId), TimeProvider.System);

        RegisteredSyncClient first = await registry.RegisterAsync(new RegisterSyncClientCommand(
            firstId, "Phone", 2, false), TestContext.CancellationToken);
        RegisteredSyncClient second = await registry.RegisterAsync(new RegisterSyncClientCommand(
            secondId, "Laptop", 2, false), TestContext.CancellationToken);
        Assert.IsTrue(first.IsActiveWriter);
        Assert.IsFalse(second.IsActiveWriter);
        Assert.AreEqual(firstId, (await context.UserSyncStates.SingleAsync(TestContext.CancellationToken)).ActiveClientId);

        RegisteredSyncClient takeover = await registry.RegisterAsync(new RegisterSyncClientCommand(
            secondId, "Laptop", 2, true), TestContext.CancellationToken);
        Assert.IsTrue(takeover.IsActiveWriter);
        UserSyncState state = await context.UserSyncStates.SingleAsync(TestContext.CancellationToken);
        Assert.AreEqual(secondId, state.ActiveClientId);
        Assert.AreEqual(2, state.Version);
    }

    [TestMethod]
    public async Task UnsupportedClientProtocolRequiresUpgradeWithoutPersistingAnything()
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        var registry = new SyncClientRegistry(context, new UserContext(userId), TimeProvider.System);
        SyncUpgradeRequiredException error = await Assert.ThrowsAsync<SyncUpgradeRequiredException>(() =>
            registry.RegisterAsync(new RegisterSyncClientCommand(Guid.NewGuid(), "Old browser", 0, true), TestContext.CancellationToken));
        Assert.AreEqual("upgrade_required", error.Code);
        Assert.AreEqual(0, await context.SyncClients.CountAsync(TestContext.CancellationToken));
        Assert.AreEqual(0, await context.UserSyncStates.CountAsync(TestContext.CancellationToken));
    }

    private const int OldProtocol = SyncResourceProtocol.ProtocolThree;

    /// <summary>Save operation per resource type; a type missing here makes the protocol-3 test fail.</summary>
    private static readonly Dictionary<string, string> SaveOperations = new(StringComparer.Ordinal)
    {
        [nameof(ResourceKind.CardioSession)] = "saveCardioSession",
        [nameof(ResourceKind.TrainingSchedule)] = "saveTrainingSchedule",
        [nameof(ResourceKind.NutritionDayTemplate)] = "saveNutritionDayTemplate",
        [nameof(ResourceKind.WaterIntakeDay)] = "setWaterIntake",
    };

    public static IEnumerable<object[]> TypesNewerThanProtocolThree =>
        SyncResourceProtocol.TypesNewerThan(OldProtocol).Select(type => new object[] { type });

    [TestMethod]
    [DynamicData(nameof(TypesNewerThanProtocolThree))]
    public async Task ProtocolThreeClientsMustUpdateForResourcesAddedAfterIt(string resourceType)
    {
        const int currentProtocol = Gainer.Contracts.Sync.SyncProtocol.CurrentVersion;
        (string connectionString, Guid userId, Guid otherUser) = await CreateDatabaseAsync();
        Guid clientId = Guid.NewGuid();
        await RegisterActiveClientAsync(connectionString, userId, clientId);

        // Push: rejected before any payload is read or anything is stored.
        await using (AppDbContext context = Fixture.CreateContext(connectionString, userId))
        {
            ProcessSyncMutationCommand push = OldProtocolSave(Guid.NewGuid(), clientId, resourceType, Guid.NewGuid());
            SyncUpgradeRequiredException rejected = await Assert.ThrowsAsync<SyncUpgradeRequiredException>(
                () => Processor(context, userId).ProcessAsync(push, TestContext.CancellationToken));
            Assert.AreEqual("upgrade_required", rejected.Code);
            context.ChangeTracker.Clear();
            Assert.AreEqual(0, await context.ProcessedMutations.CountAsync(TestContext.CancellationToken));
        }

        Guid checkIn = Guid.NewGuid();
        await InsertFeedBatchAsync(connectionString, userId, 1,
            (nameof(ResourceKind.DailyCheckIn), checkIn, 1, false, "{\"weightKg\":80}"));
        await InsertFeedBatchAsync(connectionString, userId, 2,
            (resourceType, Guid.NewGuid(), 1, false, "{\"version\":1}"));

        // Pull: an old client gets the batch before the new type and keeps its cursor there.
        await using (AppDbContext context = Fixture.CreateContext(connectionString, userId))
        {
            var feed = new SyncChangeFeed(context);
            SyncChangeFeedPage old = await feed.GetAsync(0, 200, OldProtocol, TestContext.CancellationToken);
            Assert.IsTrue(old.UpgradeRequired);
            Assert.AreEqual(1, old.NextCursor);
            Assert.AreEqual(checkIn, old.Batches.Single().Changes.Single().ResourceId);
            SyncChangeFeedPage blocked = await feed.GetAsync(1, 200, OldProtocol, TestContext.CancellationToken);
            Assert.IsTrue(blocked.UpgradeRequired);
            Assert.HasCount(0, blocked.Batches);

            SyncChangeFeedPage current = await feed.GetAsync(0, 200, currentProtocol, TestContext.CancellationToken);
            Assert.IsFalse(current.UpgradeRequired);
            Assert.AreEqual(resourceType, current.Batches[1].Changes.Single().ResourceType);
        }

        // Registration: an old app of this account must update, another account is unaffected.
        await using (AppDbContext context = Fixture.CreateContext(connectionString, userId))
        {
            var registry = new SyncClientRegistry(context, new UserContext(userId), TimeProvider.System);
            SyncUpgradeRequiredException upgrade = await Assert.ThrowsAsync<SyncUpgradeRequiredException>(() =>
                registry.RegisterAsync(
                    new RegisterSyncClientCommand(Guid.NewGuid(), "Old phone", OldProtocol, false),
                    TestContext.CancellationToken));
            Assert.AreEqual("upgrade_required", upgrade.Code);
        }
        await using AppDbContext other = Fixture.CreateContext(connectionString, otherUser);
        RegisteredSyncClient foreign = await new SyncClientRegistry(other, new UserContext(otherUser), TimeProvider.System)
            .RegisterAsync(new RegisterSyncClientCommand(Guid.NewGuid(), "Other account", OldProtocol, false), TestContext.CancellationToken);
        Assert.AreEqual(OldProtocol, foreign.ProtocolVersion);
    }

    [TestMethod]
    [DynamicData(nameof(TypesNewerThanProtocolThree))]
    public async Task RetryOfAMutationAppliedBeforeTheGateStillGetsItsReceipt(string resourceType)
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        Guid clientId = Guid.NewGuid();
        await RegisterActiveClientAsync(connectionString, userId, clientId);
        Guid mutationId = Guid.NewGuid();
        Guid resourceId = Guid.NewGuid();
        ProcessSyncMutationCommand applied = OldProtocolSave(mutationId, clientId, resourceType, resourceId);

        // The server applied this protocol-3 mutation before the type required protocol 4; only the receipt remains.
        await using (AppDbContext seed = Fixture.CreateContext(connectionString, userId))
        {
            seed.ProcessedMutations.Add(new ProcessedMutation
            {
                MutationId = mutationId,
                ClientId = clientId,
                ClientSequence = applied.Content.ClientSequence,
                ContentHash = CanonicalMutationHasher.Hash(applied.Content),
                ResultJson = JsonSerializer.Serialize(new
                {
                    revision = 1,
                    changes = new[] { new { resourceType, resourceId, version = 1, snapshot = new { version = 1 }, isTombstone = false } },
                }, JsonOptions),
                Revision = 1,
                AppliedAtUtc = DateTime.UtcNow,
            });
            await seed.SaveChangesAsync(TestContext.CancellationToken);
        }

        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        ProcessedSyncMutationResult replay = await Processor(context, userId).ProcessAsync(applied, TestContext.CancellationToken);
        Assert.IsTrue(replay.Replayed);
        Assert.AreEqual(1, replay.Revision);
        ExecutedSyncChange change = replay.Changes.Single();
        Assert.AreEqual(resourceType, change.Resource.Kind.ToString());
        Assert.AreEqual(resourceId, change.Resource.ResourceId);

        // A new mutation with the same old protocol is still gated.
        SyncUpgradeRequiredException rejected = await Assert.ThrowsAsync<SyncUpgradeRequiredException>(() =>
            Processor(context, userId).ProcessAsync(
                OldProtocolSave(Guid.NewGuid(), clientId, resourceType, Guid.NewGuid(), sequence: 2),
                TestContext.CancellationToken));
        Assert.AreEqual("upgrade_required", rejected.Code);
    }

    private static ProcessSyncMutationCommand OldProtocolSave(
        Guid mutationId, Guid clientId, string resourceType, Guid resourceId, long sequence = 1) => new(
            mutationId,
            new CanonicalMutationContent(
                OldProtocol,
                clientId,
                sequence,
                SaveOperations[resourceType],
                [new CanonicalResourceVersion(resourceType, resourceId, 0)],
                null,
                JsonSerializer.SerializeToElement(new { }, JsonOptions)));

    private static SyncMutationProcessor Processor(AppDbContext context, Guid userId)
    {
        var user = new UserContext(userId);
        return new SyncMutationProcessor(
            context, user, new SyncMutationExecutor(context, user, TimeProvider.System), TimeProvider.System);
    }

    [TestMethod]
    public async Task BlockedDependencyAndStaleBaseRollBackWhileIndependentMutationCanAdvance()
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        Guid clientId = Guid.NewGuid();
        await RegisterActiveClientAsync(connectionString, userId, clientId);
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        var user = new UserContext(userId);
        var processor = new SyncMutationProcessor(
            context, user, new SyncMutationExecutor(context, user, TimeProvider.System), TimeProvider.System);

        ProcessSyncMutationCommand blocked = CreateCheckInCommand(
            Guid.NewGuid(), clientId, Guid.NewGuid(), 81m, sequence: 1, dependsOn: Guid.NewGuid());
        SyncMutationConflictException dependencyError = await Assert.ThrowsAsync<SyncMutationConflictException>(
            () => processor.ProcessAsync(blocked, TestContext.CancellationToken));
        Assert.AreEqual("dependency_not_applied", dependencyError.Code);

        Guid checkInId = Guid.NewGuid();
        ProcessSyncMutationCommand independent = CreateCheckInCommand(
            Guid.NewGuid(), clientId, checkInId, 82m, sequence: 2);
        ProcessedSyncMutationResult applied = await processor.ProcessAsync(independent, TestContext.CancellationToken);
        Assert.AreEqual(1, applied.Revision);

        ProcessSyncMutationCommand stale = CorrectCheckInCommand(
            Guid.NewGuid(), clientId, checkInId, 2, 83m, sequence: 3);
        SyncMutationConflictException staleError = await Assert.ThrowsAsync<SyncMutationConflictException>(
            () => processor.ProcessAsync(stale, TestContext.CancellationToken));
        Assert.AreEqual("stale_base_version", staleError.Code);

        context.ChangeTracker.Clear();
        Assert.AreEqual(82m, (await context.DailyCheckIns.SingleAsync(TestContext.CancellationToken)).WeightKg);
        Assert.AreEqual(1, await context.ProcessedMutations.CountAsync(TestContext.CancellationToken));
        Assert.AreEqual(1, await context.ChangeBatches.CountAsync(TestContext.CancellationToken));
        Assert.AreEqual(1, (await context.UserSyncStates.SingleAsync(TestContext.CancellationToken)).CurrentRevision);
    }

    private static async Task InsertReceiptAsync(string connectionString, Guid userId, Guid mutationId, long revision)
    {
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        Guid clientId = Guid.NewGuid();
        context.SyncClients.Add(Client(clientId));
        context.ProcessedMutations.Add(new ProcessedMutation
        {
            MutationId = mutationId,
            ClientId = clientId,
            ClientSequence = 1,
            ContentHash = new byte[32],
            ResultJson = "{}",
            Revision = revision,
            AppliedAtUtc = DateTime.UtcNow,
        });
        await context.SaveChangesAsync();
    }

    private static async Task InsertFeedBatchAsync(
        string connectionString,
        Guid userId,
        long revision,
        params (string Type, Guid Id, long Version, bool Tombstone, string? Snapshot)[] changes)
    {
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        Guid batchId = Guid.NewGuid();
        context.ChangeBatches.Add(new ChangeBatch
        {
            Id = batchId,
            Revision = revision,
            CreatedAtUtc = DateTime.UtcNow,
        });
        context.ChangeItems.AddRange(changes.Select((change, position) => new ChangeItem
        {
            Id = Guid.NewGuid(),
            BatchId = batchId,
            Position = position,
            ResourceType = change.Type,
            ResourceId = change.Id,
            ResourceVersion = change.Version,
            IsTombstone = change.Tombstone,
            SnapshotJson = change.Snapshot,
        }));
        await context.SaveChangesAsync();
    }

    private static async Task RegisterActiveClientAsync(
        string connectionString,
        Guid userId,
        Guid activeClientId,
        Guid? inactiveClientId = null)
    {
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        context.SyncClients.Add(Client(activeClientId));
        if (inactiveClientId is { } inactive) context.SyncClients.Add(Client(inactive));
        context.UserSyncStates.Add(new UserSyncState
        {
            CurrentRevision = 0,
            ActiveClientId = activeClientId,
            UpdatedAtUtc = DateTime.UtcNow,
            Version = 1,
        });
        await context.SaveChangesAsync();
    }

    private static ProcessSyncMutationCommand CreateCheckInCommand(
        Guid mutationId,
        Guid clientId,
        Guid checkInId,
        decimal weightKg,
        long sequence = 1,
        Guid? dependsOn = null)
    {
        JsonElement payload = JsonSerializer.SerializeToElement(new
        {
            checkInId,
            localDate = new DateOnly(2026, 8, 18),
            values = new DailyCheckInValues(weightKg),
        }, JsonOptions);
        return new ProcessSyncMutationCommand(
            mutationId,
            new CanonicalMutationContent(
                2,
                clientId,
                sequence,
                "createDailyCheckIn",
                [new CanonicalResourceVersion("DailyCheckIn", checkInId, 0)],
                dependsOn,
                payload));
    }

    private static ProcessSyncMutationCommand CorrectCheckInCommand(
        Guid mutationId,
        Guid clientId,
        Guid checkInId,
        long baseVersion,
        decimal weightKg,
        long sequence)
    {
        JsonElement payload = JsonSerializer.SerializeToElement(new
        {
            checkInId,
            baseVersion,
            values = new DailyCheckInValues(weightKg),
        }, JsonOptions);
        return new ProcessSyncMutationCommand(
            mutationId,
            new CanonicalMutationContent(
                2,
                clientId,
                sequence,
                "correctDailyCheckIn",
                [new CanonicalResourceVersion("DailyCheckIn", checkInId, baseVersion)],
                null,
                payload));
    }

    private static object WorkoutPayload(
        Guid workoutId,
        DateTime startedAtUtc,
        DateTime? endedAtUtc,
        Guid exerciseId,
        Guid workoutExerciseId,
        Guid setId,
        decimal weightKg,
        int repetitions) => new
        {
            workoutId,
            title = "Push",
            notes = (string?)null,
            startedAtUtc,
            endedAtUtc,
            previousValueSource = "exercise",
            sourcePlanId = (Guid?)null,
            sourceWorkoutId = (Guid?)null,
            exercises = new[]
        {
            new
            {
                workoutExerciseId,
                sourceExerciseId = exerciseId,
                exerciseNameSnapshot = "Bench press",
                exerciseTypeSnapshot = "strength",
                notes = (string?)null,
                supersetId = (Guid?)null,
                sets = new[]
                {
                    new
                    {
                        setId,
                        setType = "normal",
                        weightKg = (decimal?)weightKg,
                        repetitions = (int?)repetitions,
                        rir = (decimal?)2,
                        notes = (string?)null,
                    },
                },
            },
        },
        };

    private static ProcessSyncMutationCommand Command(
        Guid mutationId,
        Guid clientId,
        long sequence,
        string operation,
        string resourceType,
        Guid resourceId,
        long baseVersion,
        object payload,
        Guid? dependsOn = null) =>
        new(
            mutationId,
            new CanonicalMutationContent(
                3,
                clientId,
                sequence,
                operation,
                [new CanonicalResourceVersion(resourceType, resourceId, baseVersion)],
                dependsOn,
                JsonSerializer.SerializeToElement(payload, JsonOptions)));

    private static SyncClient Client(Guid id) => new()
    {
        Id = id,
        DisplayName = "Test browser",
        ProtocolVersion = 1,
        RegisteredAtUtc = DateTime.UtcNow,
        LastSeenAtUtc = DateTime.UtcNow,
    };

    private static async Task<(string ConnectionString, Guid FirstUser, Guid SecondUser)> CreateDatabaseAsync()
    {
        string connectionString = await Fixture.CreateIsolatedDatabaseAsync();
        Guid first = Guid.NewGuid();
        Guid second = Guid.NewGuid();
        await using AppDbContext context = Fixture.CreateContext(connectionString);
        await context.Database.MigrateAsync();
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

    private sealed record UserContext(Guid Value) : IUserContext
    {
        Guid? IUserContext.UserId => Value;
    }
}
