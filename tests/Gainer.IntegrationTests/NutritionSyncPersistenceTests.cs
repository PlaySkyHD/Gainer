using System.Text.Json;
using Gainer.Core.Nutrition;
using Gainer.Core.Security;
using Gainer.Core.Sync;
using Gainer.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Gainer.IntegrationTests;

[TestClass]
[DoNotParallelize]
public sealed class NutritionSyncPersistenceTests
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
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
    public async Task SaveRetryConflictDeleteAndPullAreIdempotentAndUserScoped()
    {
        (string connectionString, Guid firstUser, Guid secondUser) = await CreateDatabaseAsync();
        Guid firstClient = Guid.NewGuid();
        Guid secondClient = Guid.NewGuid();
        await RegisterAsync(connectionString, firstUser, firstClient);
        await RegisterAsync(connectionString, secondUser, secondClient);
        Guid dayId = Guid.NewGuid();
        Guid saveMutationId = Guid.NewGuid();
        ProcessSyncMutationCommand save = Command(
            saveMutationId,
            firstClient,
            1,
            "saveNutritionDay",
            dayId,
            0,
            new
            {
                nutritionDayId = dayId,
                localDate = new DateOnly(2026, 8, 19),
                baseVersion = 0,
                entries = new[]
                {
                    new
                    {
                        entryId = Guid.NewGuid(),
                        meal = "Breakfast",
                        position = 0,
                        productName = "Oats",
                        brand = (string?)null,
                        amountGrams = 150m,
                        kilocaloriesPer100Grams = 370m,
                        proteinGramsPer100Grams = (decimal?)13m,
                        carbohydrateGramsPer100Grams = (decimal?)60m,
                        fatGramsPer100Grams = (decimal?)7m,
                        source = new NutritionSourceSnapshot("Open Food Facts", "12345678", DateTime.UtcNow, 100m),
                    },
                },
            });

        await using (AppDbContext context = Fixture.CreateContext(connectionString, firstUser))
        {
            ProcessedSyncMutationResult applied = await Processor(context, firstUser).ProcessAsync(save);
            Assert.IsFalse(applied.Replayed);
            Assert.AreEqual(1, applied.Revision);
            Assert.AreEqual("NutritionDay", applied.Changes.Single().Resource.Kind.ToString());
        }
        await using (AppDbContext context = Fixture.CreateContext(connectionString, firstUser))
        {
            ProcessedSyncMutationResult replayed = await Processor(context, firstUser).ProcessAsync(save);
            Assert.IsTrue(replayed.Replayed);
            Assert.AreEqual(1, replayed.Revision);
            Assert.AreEqual(1, await context.NutritionDays.CountAsync());
            Assert.AreEqual(1, await context.NutritionEntries.CountAsync());
        }

        ProcessSyncMutationCommand staleSave = Command(
            Guid.NewGuid(), firstClient, 2, "saveNutritionDay", dayId, 0,
            new
            {
                nutritionDayId = dayId,
                localDate = new DateOnly(2026, 8, 19),
                baseVersion = 0,
                entries = Array.Empty<object>(),
            });
        await using (AppDbContext stale = Fixture.CreateContext(connectionString, firstUser))
        {
            SyncMutationConflictException conflict = await Assert.ThrowsAsync<SyncMutationConflictException>(() =>
                Processor(stale, firstUser).ProcessAsync(staleSave));
            Assert.AreEqual("stale_base_version", conflict.Code);
        }

        await using (AppDbContext foreign = Fixture.CreateContext(connectionString, secondUser))
        {
            ProcessSyncMutationCommand foreignDelete = Command(
                Guid.NewGuid(), secondClient, 1, "deleteNutritionDay", dayId, 1,
                new { nutritionDayId = dayId, baseVersion = 1 });
            SyncMutationConflictException denied = await Assert.ThrowsAsync<SyncMutationConflictException>(() =>
                Processor(foreign, secondUser).ProcessAsync(foreignDelete));
            Assert.AreEqual("resource_not_found", denied.Code);
        }

        Guid deleteMutationId = Guid.NewGuid();
        ProcessSyncMutationCommand delete = Command(
            deleteMutationId, firstClient, 2, "deleteNutritionDay", dayId, 1,
            new { nutritionDayId = dayId, baseVersion = 1 }, saveMutationId);
        await using (AppDbContext context = Fixture.CreateContext(connectionString, firstUser))
        {
            ProcessedSyncMutationResult deleted = await Processor(context, firstUser).ProcessAsync(delete);
            Assert.IsTrue(deleted.Changes.Single().IsTombstone);
            Assert.AreEqual(2, deleted.Changes.Single().Version);
            SyncChangeFeedPage feed = await new SyncChangeFeed(context).GetAsync(0, 10);
            Assert.HasCount(2, feed.Batches);
            Assert.IsTrue(feed.Batches[1].Changes.Single().IsTombstone);
        }

        await using AppDbContext owner = Fixture.CreateContext(connectionString, firstUser);
        Assert.AreEqual(0, await owner.NutritionDays.CountAsync());
        await using AppDbContext other = Fixture.CreateContext(connectionString, secondUser);
        Assert.AreEqual(0, await other.NutritionDays.CountAsync());
    }

    private static SyncMutationProcessor Processor(AppDbContext context, Guid userId)
    {
        var user = new UserContext(userId);
        return new SyncMutationProcessor(context, user, new SyncMutationExecutor(context, user, TimeProvider.System), TimeProvider.System);
    }

    private static ProcessSyncMutationCommand Command(
        Guid mutationId,
        Guid clientId,
        long sequence,
        string operation,
        Guid dayId,
        long baseVersion,
        object payload,
        Guid? dependsOn = null) => new(
            mutationId,
            new CanonicalMutationContent(
                2,
                clientId,
                sequence,
                operation,
                [new CanonicalResourceVersion("NutritionDay", dayId, baseVersion)],
                dependsOn,
                JsonSerializer.SerializeToElement(payload, JsonOptions)));

    private static async Task RegisterAsync(string connectionString, Guid userId, Guid clientId)
    {
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        context.SyncClients.Add(new SyncClient
        {
            Id = clientId,
            DisplayName = "Nutrition test",
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
