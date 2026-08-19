using Gainer.Core.Mutations;
using Gainer.Core.Nutrition;
using Gainer.Core.Security;
using Gainer.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Gainer.IntegrationTests;

[TestClass]
[DoNotParallelize]
public sealed class NutritionPersistenceTests
{
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
    public async Task SaveReadReplaceAndDeleteAreVersionedAndAtomic()
    {
        (string connectionString, Guid firstUser, _) = await CreateDatabaseAsync();
        Guid dayId = Guid.NewGuid();
        Guid breakfastId = Guid.NewGuid();
        var time = new FixedTimeProvider(new DateTimeOffset(2026, 8, 19, 7, 0, 0, TimeSpan.Zero));

        await using (AppDbContext context = Fixture.CreateContext(connectionString, firstUser))
        {
            var changes = new ChangeCollector();
            var handler = new NutritionDayMutationHandler(context, new TestUserContext(firstUser), time, changes);
            NutritionDaySnapshot created = await handler.SaveAsync(Save(
                dayId,
                0,
                Entry(breakfastId, MealType.Breakfast, 0, "Haferflocken", 150m, 250m, 20m)));
            Assert.AreEqual(1, created.Version);
            Assert.AreEqual(375m, created.Totals.Kilocalories);
            Assert.AreEqual(30m, created.Totals.ProteinGrams);
            Assert.HasCount(1, changes.Changes);
        }

        time.UtcNow = new DateTimeOffset(2026, 8, 19, 12, 0, 0, TimeSpan.Zero);
        await using (AppDbContext context = Fixture.CreateContext(connectionString, firstUser))
        {
            var handler = new NutritionDayMutationHandler(context, new TestUserContext(firstUser), time);
            NutritionDaySnapshot replaced = await handler.SaveAsync(Save(
                dayId,
                1,
                Entry(Guid.NewGuid(), MealType.Lunch, 0, "Reis", 200m, 130m, 2.7m),
                Entry(Guid.NewGuid(), MealType.Snacks, 0, "Apfel", 100m, 52m, null)));
            Assert.AreEqual(2, replaced.Version);
            Assert.AreEqual(312m, replaced.Totals.Kilocalories);
            CollectionAssert.AreEqual(new[] { MealType.Lunch, MealType.Snacks }, replaced.Entries.Select(item => item.Meal).ToArray());
        }

        await using (AppDbContext context = Fixture.CreateContext(connectionString, firstUser))
        {
            var queries = new NutritionQueries(context);
            NutritionDaySnapshot stored = await queries.GetDayAsync(new DateOnly(2026, 8, 19)) ?? throw new AssertFailedException();
            Assert.AreEqual(2, stored.Version);
            Assert.HasCount(2, stored.Entries);
            Assert.IsFalse(stored.Entries.Any(item => item.EntryId == breakfastId));
            Assert.HasCount(2, await queries.GetRecentEntriesAsync(10));
        }

        await using (AppDbContext context = Fixture.CreateContext(connectionString, firstUser))
        {
            var changes = new ChangeCollector();
            var handler = new NutritionDayMutationHandler(context, new TestUserContext(firstUser), time, changes);
            Assert.AreEqual(3, await handler.DeleteAsync(DeleteNutritionDayMutation.Create(Metadata(), dayId, 2)));
            Assert.IsInstanceOfType<DeletedResourceChange>(changes.Changes.Single());
            Assert.AreEqual(0, await context.NutritionDays.CountAsync());
            Assert.AreEqual(0, await context.NutritionEntries.CountAsync());
        }
    }

    [TestMethod]
    public async Task SameDateIsUniquePerUserAndQueriesNeverCrossUserBoundary()
    {
        (string connectionString, Guid firstUser, Guid secondUser) = await CreateDatabaseAsync();
        Guid firstDayId = Guid.NewGuid();
        await SaveForUserAsync(connectionString, firstUser, firstDayId, "First food");
        await SaveForUserAsync(connectionString, secondUser, Guid.NewGuid(), "Second food");

        await using (AppDbContext firstContext = Fixture.CreateContext(connectionString, firstUser))
        {
            NutritionDaySnapshot first = await new NutritionQueries(firstContext).GetDayAsync(new DateOnly(2026, 8, 19)) ?? throw new AssertFailedException();
            Assert.AreEqual("First food", first.Entries.Single().ProductName);
            await Assert.ThrowsAsync<NutritionDayConflictException>(() =>
                new NutritionDayMutationHandler(firstContext, new TestUserContext(firstUser), TimeProvider.System)
                    .SaveAsync(Save(Guid.NewGuid(), 0, Entry(Guid.NewGuid(), MealType.Dinner, 0, "Duplicate", 100m, 100m, null))));
        }

        await using (AppDbContext secondContext = Fixture.CreateContext(connectionString, secondUser))
        {
            var handler = new NutritionDayMutationHandler(secondContext, new TestUserContext(secondUser), TimeProvider.System);
            await Assert.ThrowsAsync<NutritionDayNotFoundException>(() =>
                handler.DeleteAsync(DeleteNutritionDayMutation.Create(Metadata(), firstDayId, 1)));
        }

        await using AppDbContext ownerRead = Fixture.CreateContext(connectionString, firstUser);
        Assert.AreEqual("First food", (await ownerRead.NutritionEntries.SingleAsync()).ProductName);
    }

    [TestMethod]
    public async Task StaleVersionLeavesStoredEntriesUntouched()
    {
        (string connectionString, Guid firstUser, _) = await CreateDatabaseAsync();
        Guid dayId = Guid.NewGuid();
        await SaveForUserAsync(connectionString, firstUser, dayId, "Original");
        await using AppDbContext context = Fixture.CreateContext(connectionString, firstUser);
        var handler = new NutritionDayMutationHandler(context, new TestUserContext(firstUser), TimeProvider.System);
        await Assert.ThrowsAsync<NutritionDayConflictException>(() =>
            handler.SaveAsync(Save(dayId, 2, Entry(Guid.NewGuid(), MealType.Breakfast, 0, "Changed", 100m, 100m, null))));
        Assert.AreEqual("Original", (await context.NutritionEntries.AsNoTracking().SingleAsync()).ProductName);
    }

    private static async Task SaveForUserAsync(string connectionString, Guid userId, Guid dayId, string productName)
    {
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        var handler = new NutritionDayMutationHandler(context, new TestUserContext(userId), TimeProvider.System);
        await handler.SaveAsync(Save(dayId, 0, Entry(Guid.NewGuid(), MealType.Breakfast, 0, productName, 100m, 100m, 10m)));
    }

    private static SaveNutritionDayMutation Save(Guid dayId, long version, params NutritionEntryInput[] entries) =>
        SaveNutritionDayMutation.Create(Metadata(), dayId, new DateOnly(2026, 8, 19), version, entries);

    private static NutritionEntryInput Entry(Guid id, MealType meal, int position, string name, decimal amount, decimal kcal, decimal? protein) =>
        NutritionEntryInput.Create(id, meal, position, name, amount, new NutritionPer100Grams(kcal, protein, null, null));

    private static MutationMetadata Metadata() => MutationMetadata.Create(Guid.NewGuid(), Guid.NewGuid(), 1);

    private static async Task<(string ConnectionString, Guid FirstUser, Guid SecondUser)> CreateDatabaseAsync()
    {
        string connectionString = await Fixture.CreateIsolatedDatabaseAsync();
        Guid firstUser = Guid.NewGuid();
        Guid secondUser = Guid.NewGuid();
        await using AppDbContext context = Fixture.CreateContext(connectionString);
        await context.Database.MigrateAsync();
        context.Users.AddRange(User(firstUser, "first-nutrition@example.test"), User(secondUser, "second-nutrition@example.test"));
        await context.SaveChangesAsync();
        return (connectionString, firstUser, secondUser);
    }

    private static AppUser User(Guid id, string email) => new()
    {
        Id = id,
        UserName = email,
        NormalizedUserName = email.ToUpperInvariant(),
        Email = email,
        NormalizedEmail = email.ToUpperInvariant(),
        EmailConfirmed = true,
        IsActive = true,
        SecurityStamp = Guid.NewGuid().ToString("N"),
        ConcurrencyStamp = Guid.NewGuid().ToString("N"),
    };

    private sealed record TestUserContext(Guid? UserId) : IUserContext;

    private sealed class FixedTimeProvider(DateTimeOffset utcNow) : TimeProvider
    {
        public DateTimeOffset UtcNow { get; set; } = utcNow;
        public override DateTimeOffset GetUtcNow() => UtcNow;
    }
}
