using Gainer.Api.Composition;
using Gainer.Api.Controllers;
using Gainer.Contracts.Sync;
using Gainer.Core.Sync;
using Gainer.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;

namespace Gainer.IntegrationTests;

[TestClass]
[DoNotParallelize]
public sealed class AccountDataExportTests
{
    public TestContext TestContext { get; set; } = null!;

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
    public async Task ExportHoldsTheNewestStateOfEveryExistingResourceOfTheCurrentUserOnly()
    {
        (string connectionString, Guid firstUser, Guid secondUser) = await CreateDatabaseAsync();
        Guid workout = Guid.NewGuid();
        Guid checkIn = Guid.NewGuid();
        Guid deletedDay = Guid.NewGuid();
        Guid recreatedDay = Guid.NewGuid();
        Guid foreignWorkout = Guid.NewGuid();

        await AddBatchAsync(connectionString, firstUser, 1,
            Upsert("Workout", workout, 1, "{\"title\":\"first-v1\"}"),
            Upsert("DailyCheckIn", checkIn, 1, "{\"weightKg\":82.5}"),
            Upsert("NutritionDay", deletedDay, 1, "{\"day\":\"deleted\"}"),
            Upsert("NutritionDay", recreatedDay, 1, "{\"day\":\"old\"}"));
        await AddBatchAsync(connectionString, firstUser, 2,
            Upsert("Workout", workout, 2, "{\"title\":\"first-v2\"}"),
            Tombstone("NutritionDay", deletedDay, 2),
            Tombstone("NutritionDay", recreatedDay, 2));
        // Hard-deleted resources recreated under the same id restart at version 1.
        await AddBatchAsync(connectionString, firstUser, 3,
            Upsert("NutritionDay", recreatedDay, 1, "{\"day\":\"recreated\"}"));
        await AddBatchAsync(connectionString, secondUser, 1,
            Upsert("Workout", foreignWorkout, 5, "{\"title\":\"second-private\"}"));

        await using AppDbContext context = Fixture.CreateContext(connectionString, firstUser);
        AccountDataExport export = await new AccountDataExportQuery(context).ExportAsync(TestContext.CancellationToken);

        Assert.AreEqual(3, export.AsOfRevision);
        CollectionAssert.AreEquivalent(
            new[] { workout, checkIn, recreatedDay },
            export.Resources.Select(item => item.ResourceId).ToArray());
        AccountExportResource newestWorkout = export.Resources.Single(item => item.ResourceId == workout);
        Assert.AreEqual(2, newestWorkout.Version);
        Assert.AreEqual("first-v2", newestWorkout.Snapshot.GetProperty("title").GetString());
        Assert.AreEqual(
            "recreated",
            export.Resources.Single(item => item.ResourceId == recreatedDay).Snapshot.GetProperty("day").GetString());
        Assert.IsFalse(export.Resources.Any(item => item.Snapshot.GetRawText().Contains("second-private", StringComparison.Ordinal)));
        CollectionAssert.AreEqual(
            export.Resources.OrderBy(item => item.ResourceType, StringComparer.Ordinal).ThenBy(item => item.ResourceId)
                .Select(item => item.ResourceId).ToArray(),
            export.Resources.Select(item => item.ResourceId).ToArray());

        await using AppDbContext foreign = Fixture.CreateContext(connectionString, secondUser);
        AccountDataExport secondExport = await new AccountDataExportQuery(foreign).ExportAsync(TestContext.CancellationToken);
        Assert.AreEqual(1, secondExport.AsOfRevision);
        Assert.AreEqual(foreignWorkout, secondExport.Resources.Single().ResourceId);
    }

    [TestMethod]
    public async Task ExportOfAnAccountWithoutChangesIsEmpty()
    {
        (string connectionString, Guid firstUser, _) = await CreateDatabaseAsync();
        await using AppDbContext context = Fixture.CreateContext(connectionString, firstUser);
        AccountDataExport export = await new AccountDataExportQuery(context).ExportAsync(TestContext.CancellationToken);
        Assert.AreEqual(0, export.AsOfRevision);
        Assert.IsEmpty(export.Resources);
    }

    [TestMethod]
    public async Task ControllerReturnsVersionedFileWithResources()
    {
        (string connectionString, Guid firstUser, _) = await CreateDatabaseAsync();
        Guid workout = Guid.NewGuid();
        await AddBatchAsync(connectionString, firstUser, 1, Upsert("Workout", workout, 1, "{\"title\":\"push\"}"));
        await using AppDbContext context = Fixture.CreateContext(connectionString, firstUser);
        var time = new FixedTimeProvider(new DateTimeOffset(2026, 10, 24, 18, 0, 0, TimeSpan.Zero));
        var controller = new AccountExportController(new AccountDataExportQuery(context), time)
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
        };

        ActionResult<AccountExportResponse> action = await controller.Get(TestContext.CancellationToken);

        AccountExportResponse response = (AccountExportResponse)((OkObjectResult)action.Result!).Value!;
        Assert.AreEqual(AccountExportFormat.Name, response.Format);
        Assert.AreEqual(AccountExportFormat.SchemaVersion, response.SchemaVersion);
        Assert.AreEqual(SyncProtocol.CurrentVersion, response.SyncProtocolVersion);
        Assert.AreEqual(1, response.AsOfRevision);
        Assert.AreEqual(time.GetUtcNow(), response.ExportedAtUtc);
        Assert.AreEqual(workout, response.Resources.Single().ResourceId);
        Assert.AreEqual(
            "attachment; filename=\"gainer-export-2026-10-24.json\"",
            controller.Response.Headers.ContentDisposition.ToString());
    }

    [TestMethod]
    public void EndpointRequiresAuthenticationAndItsOwnRateLimit()
    {
        Assert.IsNotNull(typeof(AccountExportController).GetCustomAttributes(typeof(AuthorizeAttribute), inherit: true).SingleOrDefault());
        var limit = (EnableRateLimitingAttribute)typeof(AccountExportController)
            .GetCustomAttributes(typeof(EnableRateLimitingAttribute), inherit: true).Single();
        Assert.AreEqual(ApiConstants.AccountExportRateLimitPolicy, limit.PolicyName);
        Assert.IsEmpty(typeof(AccountExportController).GetMethod(nameof(AccountExportController.Get))!
            .GetParameters().Where(parameter => parameter.ParameterType != typeof(CancellationToken)));
    }

    private static ChangeItem Upsert(string type, Guid id, long version, string snapshot) => new()
    {
        Id = Guid.NewGuid(),
        ResourceType = type,
        ResourceId = id,
        ResourceVersion = version,
        SnapshotJson = snapshot,
    };

    private static ChangeItem Tombstone(string type, Guid id, long version) => new()
    {
        Id = Guid.NewGuid(),
        ResourceType = type,
        ResourceId = id,
        ResourceVersion = version,
        IsTombstone = true,
    };

    private async Task AddBatchAsync(string connectionString, Guid userId, long revision, params ChangeItem[] items)
    {
        Guid batchId = Guid.NewGuid();
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        context.ChangeBatches.Add(new ChangeBatch { Id = batchId, Revision = revision, CreatedAtUtc = DateTime.UtcNow });
        context.ChangeItems.AddRange(items.Select((item, position) => new ChangeItem
        {
            Id = item.Id,
            BatchId = batchId,
            Position = position,
            ResourceType = item.ResourceType,
            ResourceId = item.ResourceId,
            ResourceVersion = item.ResourceVersion,
            IsTombstone = item.IsTombstone,
            SnapshotJson = item.SnapshotJson,
        }));
        await context.SaveChangesAsync(TestContext.CancellationToken);
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
        EmailConfirmed = true,
        IsActive = true,
        SecurityStamp = Guid.NewGuid().ToString("N"),
        ConcurrencyStamp = Guid.NewGuid().ToString("N"),
    };

    private sealed class FixedTimeProvider(DateTimeOffset utcNow) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => utcNow;
    }
}
