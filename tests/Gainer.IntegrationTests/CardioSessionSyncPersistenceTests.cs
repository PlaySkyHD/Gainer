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

        await using (AppDbContext context = Fixture.CreateContext(connectionString, firstUser))
        {
            ProcessedSyncMutationResult applied = await Processor(context, firstUser).ProcessAsync(create);
            Assert.IsFalse(applied.Replayed);
            Assert.AreEqual(ResourceKind.CardioSession, applied.Changes.Single().Resource.Kind);
            Assert.AreEqual(1, applied.Changes.Single().Version);
        }
        await using (AppDbContext context = Fixture.CreateContext(connectionString, firstUser))
        {
            ProcessedSyncMutationResult replayed = await Processor(context, firstUser).ProcessAsync(create);
            Assert.IsTrue(replayed.Replayed);
            Assert.AreEqual(1, await context.CardioSessions.CountAsync());
            CardioSession stored = await context.CardioSessions.SingleAsync();
            CollectionAssert.AreEqual(new[] { 0, 95, 130, 250 }, stored.HeartRateBpm);
            CollectionAssert.AreEqual(new[] { 200, 640, 3000 }, stored.RrIntervalsMs);
            Assert.AreEqual(120, stored.TargetZoneLowBpm);
            Assert.AreEqual(140, stored.TargetZoneHighBpm);
            Assert.AreEqual(12.345m, stored.DistanceKm);
            Assert.AreEqual("easy ride", stored.Notes);
            Assert.AreEqual(1, stored.Version);
        }

        CardioSessionValues edited = values with { Notes = "hard ride", HeartRateBpm = [0, 95, 130, 250, 100] };
        Guid updateId = Guid.NewGuid();
        await using (AppDbContext context = Fixture.CreateContext(connectionString, firstUser))
        {
            ProcessedSyncMutationResult updated = await Processor(context, firstUser)
                .ProcessAsync(Save(updateId, client, 2, 1, edited, createId));
            Assert.AreEqual(2, updated.Changes.Single().Version);
            CardioSession stored = await context.CardioSessions.AsNoTracking().SingleAsync();
            Assert.AreEqual("hard ride", stored.Notes);
            Assert.HasCount(5, stored.HeartRateBpm);
            Assert.AreEqual(2, stored.Version);
        }

        await using (AppDbContext context = Fixture.CreateContext(connectionString, firstUser))
        {
            ProcessedSyncMutationResult deleted = await Processor(context, firstUser).ProcessAsync(
                Delete(Guid.NewGuid(), client, 3, sessionId, 2, updateId));
            Assert.IsTrue(deleted.Changes.Single().IsTombstone);
            Assert.AreEqual(3, deleted.Changes.Single().Version);
            Assert.AreEqual(0, await context.CardioSessions.CountAsync());
            SyncChangeFeedPage feed = await new SyncChangeFeed(context).GetAsync(0, 10);
            Assert.HasCount(3, feed.Batches);
            Assert.IsTrue(feed.Batches[2].Changes.Single().IsTombstone);
        }
    }

    [TestMethod]
    public async Task StaleBaseVersionAndExistingCreateConflictWhileMissingUpdateIsNotFound()
    {
        (string connectionString, Guid user, Guid _) = await CreateDatabaseAsync();
        Guid client = Guid.NewGuid();
        await RegisterAsync(connectionString, user, client);
        Guid sessionId = Guid.NewGuid();
        CardioSessionValues values = Session(sessionId);

        await using (AppDbContext context = Fixture.CreateContext(connectionString, user))
        {
            _ = await Processor(context, user).ProcessAsync(Save(Guid.NewGuid(), client, 1, 0, values));
        }
        await using (AppDbContext context = Fixture.CreateContext(connectionString, user))
        {
            SyncMutationConflictException duplicateCreate = await Assert.ThrowsAsync<SyncMutationConflictException>(() =>
                Processor(context, user).ProcessAsync(Save(Guid.NewGuid(), client, 2, 0, values)));
            Assert.AreEqual("stale_base_version", duplicateCreate.Code);
        }
        await using (AppDbContext context = Fixture.CreateContext(connectionString, user))
        {
            SyncMutationConflictException staleUpdate = await Assert.ThrowsAsync<SyncMutationConflictException>(() =>
                Processor(context, user).ProcessAsync(Save(Guid.NewGuid(), client, 2, 5, values)));
            Assert.AreEqual("stale_base_version", staleUpdate.Code);
        }
        await using (AppDbContext context = Fixture.CreateContext(connectionString, user))
        {
            SyncMutationConflictException staleDelete = await Assert.ThrowsAsync<SyncMutationConflictException>(() =>
                Processor(context, user).ProcessAsync(Delete(Guid.NewGuid(), client, 2, sessionId, 4)));
            Assert.AreEqual("stale_base_version", staleDelete.Code);
        }
        await using (AppDbContext context = Fixture.CreateContext(connectionString, user))
        {
            Guid missing = Guid.NewGuid();
            SyncMutationConflictException notFound = await Assert.ThrowsAsync<SyncMutationConflictException>(() =>
                Processor(context, user).ProcessAsync(Save(Guid.NewGuid(), client, 2, 1, Session(missing))));
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

        await using AppDbContext context = Fixture.CreateContext(connectionString, user);
        CardioSessionValidationException error = await Assert.ThrowsAsync<CardioSessionValidationException>(() =>
            Processor(context, user).ProcessAsync(Save(Guid.NewGuid(), client, 1, 0, invalid)));
        Assert.IsTrue(error.Errors.ContainsKey(nameof(CardioSessionValues.HeartRateBpm)));
        await using AppDbContext verify = Fixture.CreateContext(connectionString, user);
        Assert.AreEqual(0, await verify.CardioSessions.CountAsync());
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
        await using (AppDbContext context = Fixture.CreateContext(connectionString, owner))
        {
            _ = await Processor(context, owner).ProcessAsync(Save(Guid.NewGuid(), ownerClient, 1, 0, values));
        }

        await using (AppDbContext context = Fixture.CreateContext(connectionString, intruder))
        {
            SyncMutationConflictException update = await Assert.ThrowsAsync<SyncMutationConflictException>(() =>
                Processor(context, intruder).ProcessAsync(
                    Save(Guid.NewGuid(), intruderClient, 1, 1, values with { Notes = "stolen" })));
            Assert.AreEqual("resource_not_found", update.Code);
        }
        await using (AppDbContext context = Fixture.CreateContext(connectionString, intruder))
        {
            SyncMutationConflictException delete = await Assert.ThrowsAsync<SyncMutationConflictException>(() =>
                Processor(context, intruder).ProcessAsync(Delete(Guid.NewGuid(), intruderClient, 1, sessionId, 1)));
            Assert.AreEqual("resource_not_found", delete.Code);
        }
        await using (AppDbContext context = Fixture.CreateContext(connectionString, intruder))
        {
            Assert.AreEqual(0, await context.CardioSessions.CountAsync());
        }
        await using (AppDbContext context = Fixture.CreateContext(connectionString, owner))
        {
            CardioSession stored = await context.CardioSessions.SingleAsync();
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
                2,
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
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
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
