using System.Text.Json;
using Gainer.Contracts.Sync;
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
    public async Task AddAndSetAdvanceVersionsAndPublishSnapshots()
    {
        (string connectionString, Guid user, _) = await CreateDatabaseAsync();
        Guid client = Guid.NewGuid();
        await RegisterAsync(connectionString, user, client);
        Guid dayId = Guid.NewGuid();

        WaterIntakeDaySnapshot created = await Apply(connectionString, user, client, 1, Add(dayId, 0, 300));
        Assert.AreEqual(300, created.AmountMl);
        Assert.AreEqual(1, created.Version);
        Assert.AreEqual(Day, created.LocalDate);

        WaterIntakeDaySnapshot added = await Apply(connectionString, user, client, 2, Add(dayId, 1, 500));
        Assert.AreEqual(800, added.AmountMl);
        Assert.AreEqual(2, added.Version);

        WaterIntakeDaySnapshot corrected = await Apply(connectionString, user, client, 3, Set(dayId, 2, 450));
        Assert.AreEqual(450, corrected.AmountMl);
        Assert.AreEqual(3, corrected.Version);

        // Undo to zero keeps the day as a stored state instead of a tombstone.
        WaterIntakeDaySnapshot reset = await Apply(connectionString, user, client, 4, Set(dayId, 3, 0));
        Assert.AreEqual(0, reset.AmountMl);
        Assert.AreEqual(4, reset.Version);

        await using AppDbContext context = Fixture.CreateContext(connectionString, user);
        SyncChangeFeedPage feed = await new SyncChangeFeed(context).GetAsync(0, 50, TestContext.CancellationToken);
        SyncFeedChange[] changes = feed.Batches.SelectMany(batch => batch.Changes).ToArray();
        Assert.HasCount(4, changes);
        Assert.IsTrue(changes.All(change => change.ResourceType == "WaterIntakeDay" && change.ResourceId == dayId));
        Assert.IsFalse(changes.Any(change => change.IsTombstone));
        JsonElement last = changes[^1].Snapshot ?? throw new AssertFailedException("Snapshot missing.");
        Assert.AreEqual(4, changes[^1].Version);
        Assert.AreEqual(0, last.GetProperty("amountMl").GetInt32());
        Assert.AreEqual("2026-10-25", last.GetProperty("localDate").GetString());
        Assert.AreEqual(dayId, last.GetProperty("waterIntakeDayId").GetGuid());

        AccountDataExport export = await new AccountDataExportQuery(context).ExportAsync(TestContext.CancellationToken);
        AccountExportResource water = export.Resources.Single(item => item.ResourceType == "WaterIntakeDay");
        Assert.AreEqual(dayId, water.ResourceId);
        Assert.AreEqual(4, water.Version);
        Assert.AreEqual(0, water.Snapshot.GetProperty("amountMl").GetInt32());
    }

    [TestMethod]
    public async Task ReplayedAddCountsOnce()
    {
        (string connectionString, Guid user, _) = await CreateDatabaseAsync();
        Guid client = Guid.NewGuid();
        await RegisterAsync(connectionString, user, client);
        Guid dayId = Guid.NewGuid();
        ProcessSyncMutationCommand add = For(Add(dayId, 0, 500), client, 1);

        await using AppDbContext context = Fixture.CreateContext(connectionString, user);
        ProcessedSyncMutationResult first = await Processor(context, user).ProcessAsync(add, TestContext.CancellationToken);
        ProcessedSyncMutationResult replayed = await Processor(context, user).ProcessAsync(add, TestContext.CancellationToken);

        Assert.IsFalse(first.Replayed);
        Assert.IsTrue(replayed.Replayed);
        Assert.AreEqual(500, (await context.WaterIntakeDays.SingleAsync(TestContext.CancellationToken)).AmountMl);
    }

    [TestMethod]
    public async Task StaleBaseVersionAndSecondIdForTheSameDayAreConflicts()
    {
        (string connectionString, Guid user, _) = await CreateDatabaseAsync();
        Guid client = Guid.NewGuid();
        await RegisterAsync(connectionString, user, client);
        Guid dayId = Guid.NewGuid();
        _ = await Apply(connectionString, user, client, 1, Add(dayId, 0, 300));
        _ = await Apply(connectionString, user, client, 2, Add(dayId, 1, 300));

        await ExpectConflict(connectionString, user, client, 3, Add(dayId, 1, 200), "stale_base_version");
        await ExpectConflict(connectionString, user, client, 3, Set(dayId, 3, 200), "stale_base_version");
        await ExpectConflict(connectionString, user, client, 3, Add(dayId, 0, 200), "stale_base_version");
        await ExpectConflict(connectionString, user, client, 3, Set(dayId, 2, 200, Day.AddDays(1)), "stale_base_version");
        await ExpectConflict(connectionString, user, client, 3, Add(Guid.NewGuid(), 0, 200), "stale_base_version");
        await ExpectConflict(connectionString, user, client, 3, Set(Guid.NewGuid(), 1, 200), "resource_not_found");

        await using AppDbContext context = Fixture.CreateContext(connectionString, user);
        WaterIntakeDay stored = await context.WaterIntakeDays.SingleAsync(TestContext.CancellationToken);
        Assert.AreEqual(600, stored.AmountMl);
        Assert.AreEqual(2, stored.Version);
    }

    [TestMethod]
    public async Task AmountsOutsideTheDailyLimitsAreRejected()
    {
        (string connectionString, Guid user, _) = await CreateDatabaseAsync();
        Guid client = Guid.NewGuid();
        await RegisterAsync(connectionString, user, client);
        Guid dayId = Guid.NewGuid();
        _ = await Apply(connectionString, user, client, 1, Set(dayId, 0, 9_800));

        await ExpectInvalid(connectionString, user, client, 2, Add(dayId, 1, 300));
        await ExpectInvalid(connectionString, user, client, 2, Set(dayId, 1, 10_001));
        await ExpectInvalid(connectionString, user, client, 2, Set(dayId, 1, -1));
        await ExpectInvalid(connectionString, user, client, 2, Add(dayId, 1, 0));
        await ExpectInvalid(connectionString, user, client, 2, Add(dayId, 1, int.MaxValue));

        WaterIntakeDaySnapshot atLimit = await Apply(connectionString, user, client, 2, Add(dayId, 1, 200));
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
        _ = await Apply(connectionString, user, client, 1, Add(dayId, 0, 700));

        // The other user addresses the foreign id like a missing resource and cannot change it.
        await ExpectConflict(connectionString, otherUser, otherClient, 1, Add(dayId, 1, 300), "resource_not_found");
        // The same local date is free for the other user.
        WaterIntakeDaySnapshot own = await Apply(connectionString, otherUser, otherClient, 1, Add(Guid.NewGuid(), 0, 250));
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
    public async Task HandlerRequiresAnAuthenticatedUser()
    {
        (string connectionString, _, _) = await CreateDatabaseAsync();
        await using AppDbContext context = Fixture.CreateContext(connectionString);
        var handler = new WaterIntakeMutationHandler(context, new AnonymousContext(), new FixedTimeProvider(ServerNow));
        ChangeWaterIntakeMutation mutation = ChangeWaterIntakeMutation.Create(
            Gainer.Core.Mutations.MutationMetadata.Create(Guid.NewGuid(), Guid.NewGuid(), 1),
            Guid.NewGuid(), Day, 0, WaterIntakeChange.Add, 200);

        _ = await Assert.ThrowsAsync<UnauthorizedAccessException>(() =>
            handler.ChangeAsync(mutation, TestContext.CancellationToken));
    }

    private static ProcessSyncMutationCommand Add(Guid dayId, long baseVersion, int amountMl) =>
        Command("addWaterIntake", dayId, baseVersion, amountMl, Day);

    private static ProcessSyncMutationCommand Set(Guid dayId, long baseVersion, int amountMl, DateOnly? localDate = null) =>
        Command("setWaterIntake", dayId, baseVersion, amountMl, localDate ?? Day);

    private static ProcessSyncMutationCommand Command(
        string operation, Guid dayId, long baseVersion, int amountMl, DateOnly localDate) => new(
            Guid.NewGuid(),
            new CanonicalMutationContent(
                SyncProtocol.CurrentVersion,
                Guid.Empty,
                0,
                operation,
                [new CanonicalResourceVersion("WaterIntakeDay", dayId, baseVersion)],
                null,
                JsonSerializer.SerializeToElement(
                    new { waterIntakeDayId = dayId, localDate, baseVersion, amountMl },
                    JsonOptions)));

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
        string connectionString, Guid user, Guid client, long sequence, ProcessSyncMutationCommand command)
    {
        await using AppDbContext context = Fixture.CreateContext(connectionString, user);
        SyncMutationValidationException invalid = await Assert.ThrowsAsync<SyncMutationValidationException>(() =>
            Processor(context, user).ProcessAsync(For(command, client, sequence)));
        Assert.AreEqual("invalid_payload", invalid.Code);
    }

    private static SyncMutationProcessor Processor(AppDbContext context, Guid userId)
    {
        var user = new UserContext(userId);
        var time = new FixedTimeProvider(ServerNow);
        return new SyncMutationProcessor(context, user, new SyncMutationExecutor(context, user, time), time);
    }

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
