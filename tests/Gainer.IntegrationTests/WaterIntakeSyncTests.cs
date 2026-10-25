using System.Text.Json;
using Gainer.Contracts.Sync;
using Gainer.Core.BodyTracking;
using Gainer.Core.Nutrition;
using Gainer.Core.Security;
using Gainer.Core.Sync;
using Gainer.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Gainer.IntegrationTests;

[TestClass]
[DoNotParallelize]
public sealed class WaterIntakeSyncTests
{
    private const int OldProtocol = 3;
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private static readonly DateTimeOffset ServerNow = new(2026, 10, 25, 9, 0, 0, TimeSpan.Zero);
    private static readonly DateOnly Day = new(2026, 10, 25);
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
    public async Task SetAdvancesVersionsAndPublishesSnapshots()
    {
        (string connectionString, Guid user, _) = await CreateDatabaseAsync();
        Guid client = Guid.NewGuid();
        await RegisterAsync(connectionString, user, client);
        Guid dayId = Guid.NewGuid();

        WaterIntakeDaySnapshot created = await Apply(connectionString, user, client, 1, Set(dayId, 0, 300));
        Assert.AreEqual(300, created.AmountMl);
        Assert.AreEqual(1, created.Version);
        Assert.AreEqual(Day, created.LocalDate);

        WaterIntakeDaySnapshot raised = await Apply(connectionString, user, client, 2, Set(dayId, 1, 800));
        Assert.AreEqual(800, raised.AmountMl);
        Assert.AreEqual(2, raised.Version);

        // Undo to zero keeps the day as a stored state instead of a tombstone.
        WaterIntakeDaySnapshot reset = await Apply(connectionString, user, client, 3, Set(dayId, 2, 0));
        Assert.AreEqual(0, reset.AmountMl);
        Assert.AreEqual(3, reset.Version);

        await using AppDbContext context = Fixture.CreateContext(connectionString, user);
        SyncChangeFeedPage feed = await new SyncChangeFeed(context).GetAsync(0, 50, SyncProtocol.CurrentVersion, TestContext.CancellationToken);
        SyncFeedChange[] changes = feed.Batches.SelectMany(batch => batch.Changes).ToArray();
        Assert.HasCount(3, changes);
        Assert.IsTrue(changes.All(change => change.ResourceType == "WaterIntakeDay" && change.ResourceId == dayId));
        Assert.IsFalse(changes.Any(change => change.IsTombstone));
        JsonElement last = changes[^1].Snapshot ?? throw new AssertFailedException("Snapshot missing.");
        Assert.AreEqual(3, changes[^1].Version);
        Assert.AreEqual(0, last.GetProperty("amountMl").GetInt32());
        Assert.AreEqual("2026-10-25", last.GetProperty("localDate").GetString());
        Assert.AreEqual(dayId, last.GetProperty("waterIntakeDayId").GetGuid());

        AccountDataExport export = await new AccountDataExportQuery(context).ExportAsync(TestContext.CancellationToken);
        AccountExportResource water = export.Resources.Single(item => item.ResourceType == "WaterIntakeDay");
        Assert.AreEqual(dayId, water.ResourceId);
        Assert.AreEqual(3, water.Version);
        Assert.AreEqual(0, water.Snapshot.GetProperty("amountMl").GetInt32());
    }

    [TestMethod]
    public async Task ReplayedSetIsAppliedOnce()
    {
        (string connectionString, Guid user, _) = await CreateDatabaseAsync();
        Guid client = Guid.NewGuid();
        await RegisterAsync(connectionString, user, client);
        ProcessSyncMutationCommand set = For(Set(Guid.NewGuid(), 0, 500), client, 1);

        await using AppDbContext context = Fixture.CreateContext(connectionString, user);
        ProcessedSyncMutationResult first = await Processor(context, user).ProcessAsync(set, TestContext.CancellationToken);
        ProcessedSyncMutationResult replayed = await Processor(context, user).ProcessAsync(set, TestContext.CancellationToken);

        Assert.IsFalse(first.Replayed);
        Assert.IsTrue(replayed.Replayed);
        WaterIntakeDay stored = await context.WaterIntakeDays.SingleAsync(TestContext.CancellationToken);
        Assert.AreEqual(500, stored.AmountMl);
        Assert.AreEqual(1, stored.Version);
    }

    [TestMethod]
    public async Task StaleBaseVersionAndSecondIdForTheSameDayAreConflicts()
    {
        (string connectionString, Guid user, _) = await CreateDatabaseAsync();
        Guid client = Guid.NewGuid();
        await RegisterAsync(connectionString, user, client);
        Guid dayId = Guid.NewGuid();
        _ = await Apply(connectionString, user, client, 1, Set(dayId, 0, 300));
        _ = await Apply(connectionString, user, client, 2, Set(dayId, 1, 600));

        await ExpectConflict(connectionString, user, client, 3, Set(dayId, 1, 200), "stale_base_version");
        await ExpectConflict(connectionString, user, client, 3, Set(dayId, 3, 200), "stale_base_version");
        await ExpectConflict(connectionString, user, client, 3, Set(dayId, 0, 200), "stale_base_version");
        // Another id for a stored date is no stale version: retrying cannot resolve it.
        await ExpectInvalid(connectionString, user, client, 3, Set(Guid.NewGuid(), 0, 200), "water_day_exists");
        await ExpectConflict(connectionString, user, client, 3, Set(Guid.NewGuid(), 1, 200), "resource_not_found");

        await using AppDbContext context = Fixture.CreateContext(connectionString, user);
        WaterIntakeDay stored = await context.WaterIntakeDays.SingleAsync(TestContext.CancellationToken);
        Assert.AreEqual(600, stored.AmountMl);
        Assert.AreEqual(2, stored.Version);
    }

    [TestMethod]
    public async Task AnotherDateForAKnownIdIsAnInvalidPayloadNotAConflict()
    {
        (string connectionString, Guid user, _) = await CreateDatabaseAsync();
        Guid client = Guid.NewGuid();
        await RegisterAsync(connectionString, user, client);
        Guid dayId = Guid.NewGuid();
        _ = await Apply(connectionString, user, client, 1, Set(dayId, 0, 300));

        await ExpectInvalid(connectionString, user, client, 2, Set(dayId, 1, 500, Day.AddDays(1)));

        await using AppDbContext context = Fixture.CreateContext(connectionString, user);
        WaterIntakeDay stored = await context.WaterIntakeDays.SingleAsync(TestContext.CancellationToken);
        Assert.AreEqual(Day, stored.LocalDate);
        Assert.AreEqual(300, stored.AmountMl);
    }

    [TestMethod]
    public async Task AmountsOutsideTheDailyLimitsAreRejected()
    {
        (string connectionString, Guid user, _) = await CreateDatabaseAsync();
        Guid client = Guid.NewGuid();
        await RegisterAsync(connectionString, user, client);
        Guid dayId = Guid.NewGuid();
        _ = await Apply(connectionString, user, client, 1, Set(dayId, 0, 9_800));

        await ExpectInvalid(connectionString, user, client, 2, Set(dayId, 1, 10_001));
        await ExpectInvalid(connectionString, user, client, 2, Set(dayId, 1, -1));

        WaterIntakeDaySnapshot atLimit = await Apply(connectionString, user, client, 2, Set(dayId, 1, 10_000));
        Assert.AreEqual(WaterIntakeLimits.MaxDailyMl, atLimit.AmountMl);
    }

    [TestMethod]
    public async Task UsersOnlySeeAndChangeTheirOwnWaterIntake()
    {
        (string connectionString, Guid user, Guid otherUser) = await CreateDatabaseAsync();
        Guid client = Guid.NewGuid();
        Guid otherClient = Guid.NewGuid();
        await RegisterAsync(connectionString, user, client);
        await RegisterAsync(connectionString, otherUser, otherClient);
        Guid dayId = Guid.NewGuid();
        _ = await Apply(connectionString, user, client, 1, Set(dayId, 0, 700));

        // The other user addresses the foreign id like a missing resource and cannot change it.
        await ExpectConflict(connectionString, otherUser, otherClient, 1, Set(dayId, 1, 300), "resource_not_found");
        // The same local date is free for the other user.
        WaterIntakeDaySnapshot own = await Apply(connectionString, otherUser, otherClient, 1, Set(Guid.NewGuid(), 0, 250));
        Assert.AreEqual(250, own.AmountMl);

        await using (AppDbContext context = Fixture.CreateContext(connectionString, otherUser))
        {
            WaterIntakeDay[] visible = await context.WaterIntakeDays.ToArrayAsync(TestContext.CancellationToken);
            Assert.HasCount(1, visible);
            Assert.AreEqual(250, visible[0].AmountMl);
            AccountDataExport export = await new AccountDataExportQuery(context).ExportAsync(TestContext.CancellationToken);
            Assert.IsFalse(export.Resources.Any(item => item.ResourceId == dayId));
        }

        await using AppDbContext owner = Fixture.CreateContext(connectionString, user);
        WaterIntakeDay stored = await owner.WaterIntakeDays.SingleAsync(TestContext.CancellationToken);
        Assert.AreEqual(700, stored.AmountMl);
        Assert.AreEqual(1, stored.Version);
    }

    [TestMethod]
    public async Task OldProtocolCannotWriteWater()
    {
        (string connectionString, Guid user, _) = await CreateDatabaseAsync();
        Guid client = Guid.NewGuid();
        await RegisterAsync(connectionString, user, client);
        ProcessSyncMutationCommand set = Set(Guid.NewGuid(), 0, 300);
        ProcessSyncMutationCommand old = set with { Content = set.Content with { ProtocolVersion = OldProtocol } };

        await ExpectConflict(connectionString, user, client, 1, old, "upgrade_required");

        await using AppDbContext context = Fixture.CreateContext(connectionString, user);
        Assert.IsFalse(await context.WaterIntakeDays.AnyAsync(TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task OldClientsGetOlderBatchesThenMustUpdateAndNewClientsReceiveWater()
    {
        (string connectionString, Guid user, _) = await CreateDatabaseAsync();
        Guid client = Guid.NewGuid();
        await RegisterAsync(connectionString, user, client);
        Guid checkIn = Guid.NewGuid();
        await using (AppDbContext context = Fixture.CreateContext(connectionString, user))
        {
            _ = await Processor(context, user).ProcessAsync(For(CheckIn(checkIn), client, 1));
        }
        Guid dayId = Guid.NewGuid();
        _ = await Apply(connectionString, user, client, 2, Set(dayId, 0, 500));
        await using (AppDbContext context = Fixture.CreateContext(connectionString, user))
        {
            _ = await Processor(context, user).ProcessAsync(
                For(CheckIn(Guid.NewGuid(), Day.AddDays(-1)), client, 3));
        }

        await using AppDbContext reader = Fixture.CreateContext(connectionString, user);
        var feed = new SyncChangeFeed(reader);

        // An old client gets the check-in before the water batch, never past it.
        SyncChangeFeedPage oldFirst = await feed.GetAsync(0, 200, OldProtocol, TestContext.CancellationToken);
        Assert.IsTrue(oldFirst.UpgradeRequired);
        Assert.IsTrue(oldFirst.HasMore);
        Assert.AreEqual(1, oldFirst.NextCursor);
        Assert.AreEqual(checkIn, oldFirst.Batches.Single().Changes.Single().ResourceId);

        SyncChangeFeedPage oldBlocked = await feed.GetAsync(1, 200, OldProtocol, TestContext.CancellationToken);
        Assert.IsTrue(oldBlocked.UpgradeRequired);
        Assert.HasCount(0, oldBlocked.Batches);
        Assert.AreEqual(1, oldBlocked.NextCursor);

        SyncChangeFeedPage current = await feed.GetAsync(0, 200, SyncProtocol.CurrentVersion, TestContext.CancellationToken);
        Assert.IsFalse(current.UpgradeRequired);
        Assert.AreEqual(3, current.NextCursor);
        Assert.AreEqual(
            "WaterIntakeDay",
            current.Batches[1].Changes.Single().ResourceType);
    }

    [TestMethod]
    public async Task OldClientsMustUpdateOnceTheAccountHasWater()
    {
        (string connectionString, Guid user, Guid otherUser) = await CreateDatabaseAsync();
        Guid client = Guid.NewGuid();
        await RegisterAsync(connectionString, user, client);
        Guid oldDevice = Guid.NewGuid();

        // Without water an old app keeps working.
        await using (AppDbContext context = Fixture.CreateContext(connectionString, user))
        {
            RegisteredSyncClient registered = await Registry(context, user)
                .RegisterAsync(new RegisterSyncClientCommand(oldDevice, "Altes iPhone", OldProtocol, false));
            Assert.AreEqual(OldProtocol, registered.ProtocolVersion);
        }

        _ = await Apply(connectionString, user, client, 1, Set(Guid.NewGuid(), 0, 500));

        await using (AppDbContext context = Fixture.CreateContext(connectionString, user))
        {
            SyncUpgradeRequiredException upgrade = await Assert.ThrowsAsync<SyncUpgradeRequiredException>(() =>
                Registry(context, user).RegisterAsync(
                    new RegisterSyncClientCommand(oldDevice, "Altes iPhone", OldProtocol, false)));
            Assert.AreEqual("upgrade_required", upgrade.Code);
            RegisteredSyncClient updated = await Registry(context, user).RegisterAsync(
                new RegisterSyncClientCommand(oldDevice, "Altes iPhone", SyncProtocol.CurrentVersion, false));
            Assert.AreEqual(SyncProtocol.CurrentVersion, updated.ProtocolVersion);
        }

        // Water of one account does not block old apps of another account.
        await using AppDbContext other = Fixture.CreateContext(connectionString, otherUser);
        RegisteredSyncClient foreign = await Registry(other, otherUser)
            .RegisterAsync(new RegisterSyncClientCommand(Guid.NewGuid(), "Anderes Konto", OldProtocol, false));
        Assert.AreEqual(OldProtocol, foreign.ProtocolVersion);
    }

    [TestMethod]
    public async Task HandlerRequiresAnAuthenticatedUser()
    {
        (string connectionString, _, _) = await CreateDatabaseAsync();
        await using AppDbContext context = Fixture.CreateContext(connectionString);
        var handler = new WaterIntakeMutationHandler(context, new AnonymousContext(), new FixedTimeProvider(ServerNow));
        SetWaterIntakeMutation mutation = SetWaterIntakeMutation.Create(
            Gainer.Core.Mutations.MutationMetadata.Create(Guid.NewGuid(), Guid.NewGuid(), 1),
            Guid.NewGuid(), Day, 0, 200);

        _ = await Assert.ThrowsAsync<UnauthorizedAccessException>(() =>
            handler.SetAsync(mutation, TestContext.CancellationToken));
    }

    private static ProcessSyncMutationCommand Set(Guid dayId, long baseVersion, int amountMl, DateOnly? localDate = null) =>
        Command("setWaterIntake", "WaterIntakeDay", dayId, baseVersion,
            new { waterIntakeDayId = dayId, localDate = localDate ?? Day, baseVersion, amountMl });

    private static ProcessSyncMutationCommand CheckIn(Guid checkInId, DateOnly? localDate = null) =>
        Command("createDailyCheckIn", "DailyCheckIn", checkInId, 0,
            new { checkInId, localDate = localDate ?? Day, values = new DailyCheckInValues(80m) });

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

    private static async Task<WaterIntakeDaySnapshot> Apply(
        string connectionString, Guid user, Guid client, long sequence, ProcessSyncMutationCommand command)
    {
        await using AppDbContext context = Fixture.CreateContext(connectionString, user);
        ProcessedSyncMutationResult result = await Processor(context, user).ProcessAsync(For(command, client, sequence));
        ExecutedSyncChange change = result.Changes.Single();
        Assert.IsFalse(change.IsTombstone);
        return (WaterIntakeDaySnapshot)(change.Snapshot ?? throw new AssertFailedException("Snapshot missing."));
    }

    private static async Task ExpectConflict(
        string connectionString, Guid user, Guid client, long sequence, ProcessSyncMutationCommand command, string code)
    {
        await using AppDbContext context = Fixture.CreateContext(connectionString, user);
        SyncMutationConflictException conflict = await Assert.ThrowsAsync<SyncMutationConflictException>(() =>
            Processor(context, user).ProcessAsync(For(command, client, sequence)));
        Assert.AreEqual(code, conflict.Code);
    }

    private static async Task ExpectInvalid(
        string connectionString,
        Guid user,
        Guid client,
        long sequence,
        ProcessSyncMutationCommand command,
        string code = "invalid_payload")
    {
        await using AppDbContext context = Fixture.CreateContext(connectionString, user);
        SyncMutationValidationException invalid = await Assert.ThrowsAsync<SyncMutationValidationException>(() =>
            Processor(context, user).ProcessAsync(For(command, client, sequence)));
        Assert.AreEqual(code, invalid.Code);
    }

    private static SyncMutationProcessor Processor(AppDbContext context, Guid userId)
    {
        var user = new UserContext(userId);
        var time = new FixedTimeProvider(ServerNow);
        return new SyncMutationProcessor(context, user, new SyncMutationExecutor(context, user, time), time);
    }

    private static SyncClientRegistry Registry(AppDbContext context, Guid userId) =>
        new(context, new UserContext(userId), new FixedTimeProvider(ServerNow));

    private static async Task RegisterAsync(string connectionString, Guid userId, Guid clientId)
    {
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        context.SyncClients.Add(new SyncClient
        {
            Id = clientId,
            DisplayName = "Water test",
            ProtocolVersion = SyncProtocol.CurrentVersion,
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

    private sealed class AnonymousContext : IUserContext
    {
        public Guid? UserId => null;
    }

    private sealed class FixedTimeProvider(DateTimeOffset utcNow) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => utcNow;
    }
}
