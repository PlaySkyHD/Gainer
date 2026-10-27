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

        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, firstUser))
        {
            var changes = new ChangeCollector();
            var handler = new NutritionDayMutationHandler(context, new TestUserContext(firstUser), time, changes);
            NutritionDaySnapshot created = await handler.SaveAsync(Save(
                dayId,
                0,
                Entry(breakfastId, MealType.Breakfast, 0, "Haferflocken", 150m, 250m, 20m)), TestContext.CancellationToken);
            Assert.AreEqual(1, created.Version);
            Assert.AreEqual(375m, created.Totals.Kilocalories);
            Assert.AreEqual(30m, created.Totals.ProteinGrams);
            Assert.HasCount(1, changes.Changes);
        }

        time.UtcNow = new DateTimeOffset(2026, 8, 19, 12, 0, 0, TimeSpan.Zero);
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, firstUser))
        {
            var handler = new NutritionDayMutationHandler(context, new TestUserContext(firstUser), time);
            NutritionDaySnapshot replaced = await handler.SaveAsync(Save(
                dayId,
                1,
                Entry(Guid.NewGuid(), MealType.Lunch, 0, "Reis", 200m, 130m, 2.7m),
                Entry(Guid.NewGuid(), MealType.Snacks, 0, "Apfel", 100m, 52m, null)), TestContext.CancellationToken);
            Assert.AreEqual(2, replaced.Version);
            Assert.AreEqual(312m, replaced.Totals.Kilocalories);
            Assert.AreSequenceEqual(new[] { MealType.Lunch, MealType.Snacks }, replaced.Entries.Select(item => item.Meal).ToArray());
        }

        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, firstUser))
        {
            var queries = new NutritionQueries(context);
            NutritionDaySnapshot stored = await queries.GetDayAsync(new DateOnly(2026, 8, 19), TestContext.CancellationToken) ?? throw new AssertFailedException();
            Assert.AreEqual(2, stored.Version);
            Assert.HasCount(2, stored.Entries);
            Assert.DoesNotContain(item => item.EntryId == breakfastId, stored.Entries);
            Assert.HasCount(2, await queries.GetRecentEntriesAsync(10, TestContext.CancellationToken));
        }

        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, firstUser))
        {
            var changes = new ChangeCollector();
            var handler = new NutritionDayMutationHandler(context, new TestUserContext(firstUser), time, changes);
            Assert.AreEqual(3, await handler.DeleteAsync(DeleteNutritionDayMutation.Create(Metadata(), dayId, 2), TestContext.CancellationToken));
            Assert.IsInstanceOfType<DeletedResourceChange>(changes.Changes.Single());
            Assert.AreEqual(0, await context.NutritionDays.CountAsync(TestContext.CancellationToken));
            Assert.AreEqual(0, await context.NutritionEntries.CountAsync(TestContext.CancellationToken));
        }
    }

    [TestMethod]
    public async Task SameDateIsUniquePerUserAndQueriesNeverCrossUserBoundary()
    {
        (string connectionString, Guid firstUser, Guid secondUser) = await CreateDatabaseAsync();
        Guid firstDayId = Guid.NewGuid();
        await SaveForUserAsync(connectionString, firstUser, firstDayId, "First food");
        await SaveForUserAsync(connectionString, secondUser, Guid.NewGuid(), "Second food");

        await using (AppDbContext firstContext = PostgreSqlTestFixture.CreateContext(connectionString, firstUser))
        {
            NutritionDaySnapshot first = await new NutritionQueries(firstContext).GetDayAsync(new DateOnly(2026, 8, 19), TestContext.CancellationToken) ?? throw new AssertFailedException();
            Assert.AreEqual("First food", first.Entries.Single().ProductName);
            // Another day id on a stored date is no newer stand of this day; the sync processor reports it as invalid_payload.
            await Assert.ThrowsExactlyAsync<DbUpdateException>(() =>
                new NutritionDayMutationHandler(firstContext, new TestUserContext(firstUser), TimeProvider.System)
                    .SaveAsync(Save(Guid.NewGuid(), 0, Entry(Guid.NewGuid(), MealType.Dinner, 0, "Duplicate", 100m, 100m, null)), TestContext.CancellationToken));
        }

        await using (AppDbContext secondContext = PostgreSqlTestFixture.CreateContext(connectionString, secondUser))
        {
            var handler = new NutritionDayMutationHandler(secondContext, new TestUserContext(secondUser), TimeProvider.System);
            await Assert.ThrowsAsync<NutritionDayNotFoundException>(() =>
                handler.DeleteAsync(DeleteNutritionDayMutation.Create(Metadata(), firstDayId, 1), TestContext.CancellationToken));
        }

        await using AppDbContext ownerRead = PostgreSqlTestFixture.CreateContext(connectionString, firstUser);
        Assert.AreEqual("First food", (await ownerRead.NutritionEntries.SingleAsync(TestContext.CancellationToken)).ProductName);
    }

    [TestMethod]
    public async Task StaleVersionLeavesStoredEntriesUntouched()
    {
        (string connectionString, Guid firstUser, _) = await CreateDatabaseAsync();
        Guid dayId = Guid.NewGuid();
        await SaveForUserAsync(connectionString, firstUser, dayId, "Original");
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, firstUser);
        var handler = new NutritionDayMutationHandler(context, new TestUserContext(firstUser), TimeProvider.System);
        await Assert.ThrowsAsync<NutritionDayConflictException>(() =>
            handler.SaveAsync(Save(dayId, 2, Entry(Guid.NewGuid(), MealType.Breakfast, 0, "Changed", 100m, 100m, null)), TestContext.CancellationToken));
        Assert.AreEqual("Original", (await context.NutritionEntries.AsNoTracking().SingleAsync(TestContext.CancellationToken)).ProductName);
    }

    [TestMethod]
    public async Task ReorderingEntriesWithStableIdsIsNotAConflict()
    {
        (string connectionString, Guid firstUser, _) = await CreateDatabaseAsync();
        Guid dayId = Guid.NewGuid();
        Guid a = Guid.NewGuid(), b = Guid.NewGuid(), c = Guid.NewGuid(), added = Guid.NewGuid();
        NutritionEntryInput[][] saves =
        [
            [Entry(a, MealType.Breakfast, 0, "A", 100m, 100m, null), Entry(b, MealType.Breakfast, 1, "B", 100m, 100m, null), Entry(c, MealType.Breakfast, 2, "C", 100m, 100m, null)],
            // Deleting the first entry moves the others up.
            [Entry(b, MealType.Breakfast, 0, "B", 100m, 100m, null), Entry(c, MealType.Breakfast, 1, "C", 100m, 100m, null)],
            // A new first entry moves the others down.
            [Entry(added, MealType.Breakfast, 0, "Neu", 100m, 100m, null), Entry(b, MealType.Breakfast, 1, "B", 100m, 100m, null), Entry(c, MealType.Breakfast, 2, "C", 100m, 100m, null)],
            // Swapping two entries.
            [Entry(added, MealType.Breakfast, 0, "Neu", 100m, 100m, null), Entry(c, MealType.Breakfast, 1, "C", 100m, 100m, null), Entry(b, MealType.Breakfast, 2, "B", 100m, 100m, null)],
            // Moving the first entry to another meal.
            [Entry(c, MealType.Breakfast, 0, "C", 100m, 100m, null), Entry(b, MealType.Breakfast, 1, "B", 100m, 100m, null), Entry(added, MealType.Lunch, 0, "Neu", 100m, 100m, null)],
        ];

        for (int index = 0; index < saves.Length; index++)
        {
            await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, firstUser);
            var handler = new NutritionDayMutationHandler(context, new TestUserContext(firstUser), TimeProvider.System);
            NutritionDaySnapshot saved = await handler.SaveAsync(Save(dayId, index, saves[index]), TestContext.CancellationToken);
            Assert.AreEqual(index + 1, saved.Version);
        }

        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, firstUser))
        {
            NutritionDaySnapshot stored = await new NutritionQueries(context).GetDayAsync(new DateOnly(2026, 8, 19), TestContext.CancellationToken) ?? throw new AssertFailedException();
            Assert.AreSequenceEqual(new[] { c, b, added }, stored.Entries.Select(item => item.EntryId).ToArray());
            Assert.AreEqual(MealType.Lunch, stored.Entries.Single(item => item.EntryId == added).Meal);
        }
    }

    private static async Task SaveForUserAsync(string connectionString, Guid userId, Guid dayId, string productName)
    {
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
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
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString);
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

    public TestContext TestContext { get; set; } = null!;
}
