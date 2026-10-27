using System.Text.Json;
using Gainer.Core.Mutations;
using Gainer.Core.Security;
using Gainer.Core.Sync;
using Gainer.Core.Training;
using Gainer.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Gainer.IntegrationTests;

[TestClass]
[DoNotParallelize]
public sealed class CardioSessionSyncPersistenceTests
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private static readonly DateTime Start = new(2026, 10, 18, 8, 0, 0, DateTimeKind.Utc);
    private static PostgreSqlTestFixture? fixture;
    private static PostgreSqlTestFixture Fixture => fixture ?? throw new InvalidOperationException("PostgreSQL is not started.");

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
    public async Task CreateUpdateReplayAndDeleteRoundTripSeriesAndWriteTombstone()
    {
        (string connectionString, Guid firstUser, Guid _) = await CreateDatabaseAsync();
        Guid client = Guid.NewGuid();
        await RegisterAsync(connectionString, firstUser, client);
        Guid sessionId = Guid.NewGuid();
        CardioSessionValues values = Session(sessionId) with
        {
            HeartRateBpm = [0, 95, 130, 250],
            RrIntervalsMs = [200, 640, 3000],
            DistanceKm = 12.345m,
            Notes = "  easy ride  ",
        };
        Guid createId = Guid.NewGuid();
        ProcessSyncMutationCommand create = Save(createId, client, 1, 0, values);

        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, firstUser))
        {
            ProcessedSyncMutationResult applied = await Processor(context, firstUser).ProcessAsync(create, TestContext.CancellationToken);
            Assert.IsFalse(applied.Replayed);
            Assert.AreEqual(ResourceKind.CardioSession, applied.Changes.Single().Resource.Kind);
            Assert.AreEqual(1, applied.Changes.Single().Version);
        }
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, firstUser))
        {
            ProcessedSyncMutationResult replayed = await Processor(context, firstUser).ProcessAsync(create, TestContext.CancellationToken);
            Assert.IsTrue(replayed.Replayed);
            Assert.AreEqual(1, await context.CardioSessions.CountAsync(TestContext.CancellationToken));
            CardioSession stored = await context.CardioSessions.SingleAsync(TestContext.CancellationToken);
            Assert.AreSequenceEqual(ExpectedHeartRates, stored.HeartRateBpm);
            Assert.AreSequenceEqual(ExpectedRrIntervals, stored.RrIntervalsMs);
            Assert.AreEqual(120, stored.TargetZoneLowBpm);
            Assert.AreEqual(140, stored.TargetZoneHighBpm);
            Assert.AreEqual(12.345m, stored.DistanceKm);
            Assert.AreEqual("easy ride", stored.Notes);
            Assert.AreEqual(1, stored.Version);
        }

        CardioSessionValues edited = values with { Notes = "hard ride", HeartRateBpm = [0, 95, 130, 250, 100] };
        Guid updateId = Guid.NewGuid();
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, firstUser))
        {
            ProcessedSyncMutationResult updated = await Processor(context, firstUser)
                .ProcessAsync(Save(updateId, client, 2, 1, edited, createId), TestContext.CancellationToken);
            Assert.AreEqual(2, updated.Changes.Single().Version);
            CardioSession stored = await context.CardioSessions.AsNoTracking().SingleAsync(TestContext.CancellationToken);
            Assert.AreEqual("hard ride", stored.Notes);
            Assert.HasCount(5, stored.HeartRateBpm);
            Assert.AreEqual(2, stored.Version);
        }

        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, firstUser))
        {
            ProcessedSyncMutationResult deleted = await Processor(context, firstUser).ProcessAsync(
                Delete(Guid.NewGuid(), client, 3, sessionId, 2, updateId), TestContext.CancellationToken);
            Assert.IsTrue(deleted.Changes.Single().IsTombstone);
            Assert.AreEqual(3, deleted.Changes.Single().Version);
            Assert.AreEqual(0, await context.CardioSessions.CountAsync(TestContext.CancellationToken));
            SyncChangeFeedPage feed = await new SyncChangeFeed(context).GetAsync(0, 10, Gainer.Contracts.Sync.SyncProtocol.CurrentVersion, TestContext.CancellationToken);
            Assert.HasCount(3, feed.Batches);
            Assert.IsTrue(feed.Batches[2].Changes.Single().IsTombstone);
        }
    }

    [TestMethod]
    public async Task RecoveryTemplateAndJsonbPhasesRoundTripThroughSaveAndUpdate()
    {
        (string connectionString, Guid firstUser, Guid _) = await CreateDatabaseAsync();
        Guid client = Guid.NewGuid();
        await RegisterAsync(connectionString, firstUser, client);
        Guid sessionId = Guid.NewGuid();
        CardioSessionValues values = Session(sessionId) with
        {
            RecoveryStartBpm = 160,
            RecoveryEndBpm = 128,
            TemplateName = "  Intervals 4x1  ",
            Phases = [new(0, 120, "Warm-up", 100, 120), new(120, 60, "Push", 150, 170), new(180, 60, "Rest", null, null)],
        };
        Guid createId = Guid.NewGuid();
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, firstUser))
        {
            ProcessedSyncMutationResult applied = await Processor(context, firstUser)
                .ProcessAsync(Save(createId, client, 1, 0, values), TestContext.CancellationToken);
            var snapshot = (CardioSessionSnapshot)applied.Changes.Single().Snapshot!;
            Assert.AreEqual(160, snapshot.RecoveryStartBpm);
            Assert.AreEqual("Intervals 4x1", snapshot.TemplateName);
            Assert.HasCount(3, snapshot.Phases!);
        }
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, firstUser))
        {
            CardioSession stored = await context.CardioSessions.AsNoTracking().SingleAsync(TestContext.CancellationToken);
            Assert.AreEqual(160, stored.RecoveryStartBpm);
            Assert.AreEqual(128, stored.RecoveryEndBpm);
            Assert.AreEqual("Intervals 4x1", stored.TemplateName);
            Assert.HasCount(3, stored.Phases!);
            Assert.AreEqual(new CardioPhaseValues(120, 60, "Push", 150, 170), stored.Phases![1]);
            Assert.IsNull(stored.Phases[2].LowBpm);
        }

        CardioSessionValues edited = values with { Phases = [new(0, 300, "Steady", 120, 140)], RecoveryStartBpm = null, RecoveryEndBpm = null };
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, firstUser))
        {
            await Processor(context, firstUser).ProcessAsync(Save(Guid.NewGuid(), client, 2, 1, edited, createId), TestContext.CancellationToken);
            CardioSession stored = await context.CardioSessions.AsNoTracking().SingleAsync(TestContext.CancellationToken);
            Assert.HasCount(1, stored.Phases!);
            Assert.AreEqual("Steady", stored.Phases![0].Name);
            Assert.IsNull(stored.RecoveryStartBpm);
            Assert.AreEqual(2, stored.Version);
        }
    }

    [TestMethod]
    public async Task OldPayloadWithoutTheNewFieldsIsStillAccepted()
    {
        (string connectionString, Guid firstUser, Guid _) = await CreateDatabaseAsync();
        Guid client = Guid.NewGuid();
        await RegisterAsync(connectionString, firstUser, client);
        Guid sessionId = Guid.NewGuid();
        var oldSession = new
        {
            sessionId,
            activityType = CardioActivityTypes.IndoorCycling,
            startedAtUtc = Start,
            endedAtUtc = Start.AddMinutes(10),
            targetZone = new { lowBpm = 120, highBpm = 140 },
            sampleIntervalSeconds = 5,
            heartRateBpm = new[] { 100, 110 },
            rrIntervalsMs = new[] { 800 },
            sensorName = "Polar H10",
        };
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, firstUser);
        await Processor(context, firstUser).ProcessAsync(Command(
            Guid.NewGuid(), client, 1, "saveCardioSession", sessionId, 0, new { baseVersion = 0, session = oldSession }, null), TestContext.CancellationToken);
        CardioSession stored = await context.CardioSessions.AsNoTracking().SingleAsync(TestContext.CancellationToken);
        Assert.IsNull(stored.RecoveryStartBpm);
        Assert.IsNull(stored.TemplateName);
        Assert.IsNull(stored.Phases);
    }

    [TestMethod]
    public async Task StaleBaseVersionAndExistingCreateConflictWhileMissingUpdateIsNotFound()
    {
        (string connectionString, Guid user, Guid _) = await CreateDatabaseAsync();
        Guid client = Guid.NewGuid();
        await RegisterAsync(connectionString, user, client);
        Guid sessionId = Guid.NewGuid();
        CardioSessionValues values = Session(sessionId);

        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, user))
        {
            _ = await Processor(context, user).ProcessAsync(Save(Guid.NewGuid(), client, 1, 0, values), TestContext.CancellationToken);
        }
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, user))
        {
            SyncMutationConflictException duplicateCreate = await Assert.ThrowsAsync<SyncMutationConflictException>(() =>
                Processor(context, user).ProcessAsync(Save(Guid.NewGuid(), client, 2, 0, values), TestContext.CancellationToken));
            Assert.AreEqual("stale_base_version", duplicateCreate.Code);
        }
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, user))
        {
            SyncMutationConflictException staleUpdate = await Assert.ThrowsAsync<SyncMutationConflictException>(() =>
                Processor(context, user).ProcessAsync(Save(Guid.NewGuid(), client, 2, 5, values), TestContext.CancellationToken));
            Assert.AreEqual("stale_base_version", staleUpdate.Code);
        }
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, user))
        {
            SyncMutationConflictException staleDelete = await Assert.ThrowsAsync<SyncMutationConflictException>(() =>
                Processor(context, user).ProcessAsync(Delete(Guid.NewGuid(), client, 2, sessionId, 4), TestContext.CancellationToken));
            Assert.AreEqual("stale_base_version", staleDelete.Code);
        }
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, user))
        {
            Guid missing = Guid.NewGuid();
            SyncMutationConflictException notFound = await Assert.ThrowsAsync<SyncMutationConflictException>(() =>
                Processor(context, user).ProcessAsync(Save(Guid.NewGuid(), client, 2, 1, Session(missing)), TestContext.CancellationToken));
            Assert.AreEqual("resource_not_found", notFound.Code);
        }
    }

    [TestMethod]
    public async Task InvalidSeriesIsRejectedWithFieldErrorsAndNothingIsStored()
    {
        (string connectionString, Guid user, Guid _) = await CreateDatabaseAsync();
        Guid client = Guid.NewGuid();
        await RegisterAsync(connectionString, user, client);
        CardioSessionValues invalid = Session(Guid.NewGuid()) with { HeartRateBpm = [400] };

        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, user);
        CardioSessionValidationException error = await Assert.ThrowsAsync<CardioSessionValidationException>(() =>
            Processor(context, user).ProcessAsync(Save(Guid.NewGuid(), client, 1, 0, invalid), TestContext.CancellationToken));
        Assert.IsTrue(error.Errors.ContainsKey(nameof(CardioSessionValues.HeartRateBpm)));
        await using AppDbContext verify = PostgreSqlTestFixture.CreateContext(connectionString, user);
        Assert.AreEqual(0, await verify.CardioSessions.CountAsync(TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task OtherUsersCannotUpdateOrDeleteASessionAndTheOwnerDataStaysIntact()
    {
        (string connectionString, Guid owner, Guid intruder) = await CreateDatabaseAsync();
        Guid ownerClient = Guid.NewGuid();
        Guid intruderClient = Guid.NewGuid();
        await RegisterAsync(connectionString, owner, ownerClient);
        await RegisterAsync(connectionString, intruder, intruderClient);
        Guid sessionId = Guid.NewGuid();
        CardioSessionValues values = Session(sessionId);
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, owner))
        {
            _ = await Processor(context, owner).ProcessAsync(Save(Guid.NewGuid(), ownerClient, 1, 0, values), TestContext.CancellationToken);
        }

        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, intruder))
        {
            SyncMutationConflictException update = await Assert.ThrowsAsync<SyncMutationConflictException>(() =>
                Processor(context, intruder).ProcessAsync(
                    Save(Guid.NewGuid(), intruderClient, 1, 1, values with { Notes = "stolen" }), TestContext.CancellationToken));
            Assert.AreEqual("resource_not_found", update.Code);
        }
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, intruder))
        {
            SyncMutationConflictException delete = await Assert.ThrowsAsync<SyncMutationConflictException>(() =>
                Processor(context, intruder).ProcessAsync(Delete(Guid.NewGuid(), intruderClient, 1, sessionId, 1), TestContext.CancellationToken));
            Assert.AreEqual("resource_not_found", delete.Code);
        }
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, intruder))
        {
            Assert.AreEqual(0, await context.CardioSessions.CountAsync(TestContext.CancellationToken));
        }
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, owner))
        {
            CardioSession stored = await context.CardioSessions.SingleAsync(TestContext.CancellationToken);
            Assert.IsNull(stored.Notes);
            Assert.AreEqual(1, stored.Version);
        }
    }

    private static CardioSessionValues Session(Guid id) => new(
        id,
        CardioActivityTypes.IndoorCycling,
        Start,
        Start.AddMinutes(10),
        new CardioTargetZone(120, 140),
        5,
        [100, 110, 120],
        [800, 810],
        "Polar H10",
        null,
        null,
        null,
        null);

    private static ProcessSyncMutationCommand Save(
        Guid mutationId, Guid clientId, long sequence, long baseVersion, CardioSessionValues session, Guid? dependsOn = null) =>
        Command(mutationId, clientId, sequence, "saveCardioSession", session.SessionId, baseVersion, new { baseVersion, session }, dependsOn);

    private static ProcessSyncMutationCommand Delete(
        Guid mutationId, Guid clientId, long sequence, Guid sessionId, long baseVersion, Guid? dependsOn = null) =>
        Command(mutationId, clientId, sequence, "deleteCardioSession", sessionId, baseVersion, new { sessionId, baseVersion }, dependsOn);

    private static ProcessSyncMutationCommand Command(
        Guid mutationId,
        Guid clientId,
        long sequence,
        string operation,
        Guid sessionId,
        long baseVersion,
        object payload,
        Guid? dependsOn) => new(
            mutationId,
            new CanonicalMutationContent(
                Gainer.Contracts.Sync.SyncProtocol.CurrentVersion,
                clientId,
                sequence,
                operation,
                [new CanonicalResourceVersion("CardioSession", sessionId, baseVersion)],
                dependsOn,
                JsonSerializer.SerializeToElement(payload, JsonOptions)));

    private static SyncMutationProcessor Processor(AppDbContext context, Guid userId)
    {
        var user = new UserContext(userId);
        return new SyncMutationProcessor(context, user, new SyncMutationExecutor(context, user, TimeProvider.System), TimeProvider.System);
    }

    private static async Task RegisterAsync(string connectionString, Guid userId, Guid clientId)
    {
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
        context.SyncClients.Add(new SyncClient
        {
            Id = clientId,
            DisplayName = "Cardio test",
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

    private static async Task<(string ConnectionString, Guid FirstUser, Guid SecondUser)> CreateDatabaseAsync()
    {
        string connectionString = await Fixture.CreateIsolatedDatabaseAsync();
        Guid first = Guid.NewGuid();
        Guid second = Guid.NewGuid();
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString);
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

    public TestContext TestContext { get; set; } = null!;

    private static readonly int[] ExpectedHeartRates = new[] { 0, 95, 130, 250 };
    private static readonly int[] ExpectedRrIntervals = new[] { 200, 640, 3000 };
}
