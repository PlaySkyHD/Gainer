using Gainer.Core.Security;
using Gainer.Core.Mutations;
using Gainer.Core.Training;
using Gainer.Infrastructure.Catalog;
using Gainer.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Gainer.IntegrationTests;

[TestClass]
[DoNotParallelize]
public sealed class ExerciseCatalogPersistenceTests
{
    private static PostgreSqlTestFixture? fixture;

    private static PostgreSqlTestFixture Fixture =>
        fixture ?? throw new InvalidOperationException("The PostgreSQL fixture has not started.");

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
        if (fixture is not null)
        {
            await fixture.DisposeAsync();
        }
    }

    [TestMethod]
    public async Task VersionedSnapshotSeedsStableUniqueBaseExerciseIds()
    {
        string connectionString = await CreateDatabaseAsync();
        await using AppDbContext context = Fixture.CreateContext(connectionString, Guid.NewGuid());
        List<Exercise> exercises = await context.Exercises
            .IgnoreQueryFilters()
            .Where(item => item.OwnerUserId == null)
            .OrderBy(item => item.Id)
            .ToListAsync();

        Assert.HasCount(ExerciseCatalogSnapshot.Document.Entries.Count, exercises);
        CollectionAssert.AreEqual(
            ExerciseCatalogSnapshot.Document.Entries.Select(item => item.Id).Order().ToArray(),
            exercises.Select(item => item.Id).ToArray());
        Assert.IsTrue(exercises.All(item =>
            item.CatalogVersion == ExerciseCatalogSnapshot.Document.CatalogVersion &&
            !item.IsArchived));
    }

    [TestMethod]
    public async Task SearchIsBoundedFilteredAndContainsOnlyBaseAndOwnCustomExercises()
    {
        string connectionString = await CreateDatabaseAsync();
        Guid firstUser = Guid.NewGuid();
        Guid secondUser = Guid.NewGuid();
        await SeedUserAsync(connectionString, firstUser);
        await SeedUserAsync(connectionString, secondUser);
        await AddCustomAsync(connectionString, firstUser, "My Bench Variation", "Chest", "Barbell");
        await AddCustomAsync(connectionString, secondUser, "Secret Bench Variation", "Chest", "Barbell");

        await using AppDbContext context = Fixture.CreateContext(connectionString, firstUser);
        var queries = new ExerciseCatalogQueries(context, new TestUserContext(firstUser));
        ExerciseCatalogPage page = await queries.SearchAsync(new ExerciseCatalogFilter(
            Search: "Bench",
            MuscleGroup: "Chest",
            Equipment: "Barbell",
            Limit: 10));

        Assert.AreEqual(2, page.Total);
        Assert.IsTrue(page.Items.Any(item => item.Name == "Barbell Bench Press" && !item.IsCustom));
        Assert.IsTrue(page.Items.Any(item => item.Name == "My Bench Variation" && item.IsCustom));
        Assert.IsFalse(page.Items.Any(item => item.Name.Contains("Secret", StringComparison.Ordinal)));
        await Assert.ThrowsAsync<ArgumentOutOfRangeException>(() =>
            queries.SearchAsync(new ExerciseCatalogFilter(Limit: 101)));
    }

    [TestMethod]
    public async Task BaseExerciseCannotBeChangedOrDeletedThroughPersistence()
    {
        string connectionString = await CreateDatabaseAsync();
        Guid userId = Guid.NewGuid();
        await SeedUserAsync(connectionString, userId);
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        Exercise exercise = await context.Exercises.FirstAsync(item => item.OwnerUserId == null);
        exercise.Name = "Changed";

        await Assert.ThrowsAsync<BaseExerciseImmutableException>(() => context.SaveChangesAsync());
    }

    [TestMethod]
    public async Task CustomExerciseLifecycleIsOwnerOnlyAndArchivedEntryRemainsResolvable()
    {
        string connectionString = await CreateDatabaseAsync();
        Guid ownerId = Guid.NewGuid();
        Guid otherId = Guid.NewGuid();
        await SeedUserAsync(connectionString, ownerId);
        await SeedUserAsync(connectionString, otherId);
        Guid exerciseId = Guid.NewGuid();

        await using (AppDbContext createContext = Fixture.CreateContext(connectionString, ownerId))
        {
            var handler = new CustomExerciseMutationHandler(
                createContext,
                new TestUserContext(ownerId),
                new FixedTimeProvider(new DateTimeOffset(2026, 8, 18, 12, 0, 0, TimeSpan.Zero)));
            CustomExerciseSnapshot created = await handler.CreateAsync(CreateCustomExerciseMutation.Create(
                Metadata(),
                exerciseId,
                new CustomExerciseValues("  My Fly  ", MuscleGroup: "Chest", Equipment: "Cable")));
            Assert.AreEqual("My Fly", created.Values.Name);
            Assert.AreEqual(1, created.Version);
        }

        await using (AppDbContext otherContext = Fixture.CreateContext(connectionString, otherId))
        {
            var otherQueries = new ExerciseCatalogQueries(otherContext, new TestUserContext(otherId));
            Assert.IsNull(await otherQueries.ResolveAsync(exerciseId, includeArchived: true));
            var handler = new CustomExerciseMutationHandler(
                otherContext,
                new TestUserContext(otherId),
                TimeProvider.System);
            await Assert.ThrowsAsync<CustomExerciseNotFoundException>(() => handler.UpdateAsync(
                UpdateCustomExerciseMutation.Create(
                    Metadata(),
                    exerciseId,
                    1,
                    new CustomExerciseValues("Stolen"))));
        }

        await using (AppDbContext archiveContext = Fixture.CreateContext(connectionString, ownerId))
        {
            var handler = new CustomExerciseMutationHandler(
                archiveContext,
                new TestUserContext(ownerId),
                new FixedTimeProvider(new DateTimeOffset(2026, 8, 19, 12, 0, 0, TimeSpan.Zero)));
            CustomExerciseSnapshot archived = await handler.ArchiveAsync(
                ArchiveCustomExerciseMutation.Create(Metadata(), exerciseId, 1));
            Assert.IsTrue(archived.IsArchived);
            Assert.AreEqual(2, archived.Version);
        }

        await using (AppDbContext readContext = Fixture.CreateContext(connectionString, ownerId))
        {
            var queries = new ExerciseCatalogQueries(readContext, new TestUserContext(ownerId));
            Assert.IsNull(await queries.ResolveAsync(exerciseId, includeArchived: false));
            ExerciseCatalogItem? historicalReference = await queries.ResolveAsync(exerciseId, includeArchived: true);
            Assert.IsNotNull(historicalReference);
            Assert.AreEqual("My Fly", historicalReference.Name);
            ExerciseCatalogPage selectable = await queries.SearchAsync(new ExerciseCatalogFilter(Search: "My Fly"));
            Assert.AreEqual(0, selectable.Total);
        }
    }

    [TestMethod]
    public async Task InvalidCustomExerciseAndStaleVersionLeaveStoredStateUnchanged()
    {
        string connectionString = await CreateDatabaseAsync();
        Guid ownerId = Guid.NewGuid();
        await SeedUserAsync(connectionString, ownerId);
        Guid exerciseId = Guid.NewGuid();
        await using AppDbContext context = Fixture.CreateContext(connectionString, ownerId);
        var handler = new CustomExerciseMutationHandler(context, new TestUserContext(ownerId), TimeProvider.System);
        await Assert.ThrowsAsync<CustomExerciseValidationException>(() => handler.CreateAsync(
            CreateCustomExerciseMutation.Create(Metadata(), exerciseId, new CustomExerciseValues("  "))));
        Assert.AreEqual(0, await context.Exercises.CountAsync(item => item.OwnerUserId == ownerId));

        CustomExerciseSnapshot created = await handler.CreateAsync(CreateCustomExerciseMutation.Create(
            Metadata(), exerciseId, new CustomExerciseValues("Original")));
        await Assert.ThrowsAsync<CustomExerciseConflictException>(() => handler.UpdateAsync(
            UpdateCustomExerciseMutation.Create(
                Metadata(), exerciseId, created.Version + 1, new CustomExerciseValues("Changed"))));
        context.ChangeTracker.Clear();
        Exercise stored = await context.Exercises.SingleAsync(item => item.Id == exerciseId);
        Assert.AreEqual("Original", stored.Name);
        Assert.AreEqual(1, stored.Version);
    }

    private static async Task<string> CreateDatabaseAsync()
    {
        string connectionString = await Fixture.CreateIsolatedDatabaseAsync();
        await using AppDbContext context = Fixture.CreateContext(connectionString);
        await context.Database.MigrateAsync();
        return connectionString;
    }

    private static async Task SeedUserAsync(string connectionString, Guid userId)
    {
        await using AppDbContext context = Fixture.CreateContext(connectionString);
        context.Users.Add(new AppUser
        {
            Id = userId,
            UserName = $"{userId:N}@example.test",
            NormalizedUserName = $"{userId:N}@EXAMPLE.TEST",
            Email = $"{userId:N}@example.test",
            NormalizedEmail = $"{userId:N}@EXAMPLE.TEST",
            IsActive = true,
            SecurityStamp = Guid.NewGuid().ToString("N"),
            ConcurrencyStamp = Guid.NewGuid().ToString("N"),
        });
        await context.SaveChangesAsync();
    }

    private static async Task AddCustomAsync(
        string connectionString,
        Guid userId,
        string name,
        string muscleGroup,
        string equipment)
    {
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        context.Exercises.Add(new Exercise
        {
            Id = Guid.NewGuid(),
            OwnerUserId = userId,
            Name = name,
            MuscleGroup = muscleGroup,
            Equipment = equipment,
            CreatedAtUtc = DateTime.UtcNow,
            UpdatedAtUtc = DateTime.UtcNow,
            Version = 1,
        });
        await context.SaveChangesAsync();
    }

    private static MutationMetadata Metadata() =>
        MutationMetadata.Create(Guid.NewGuid(), Guid.NewGuid(), 1);

    private sealed class FixedTimeProvider(DateTimeOffset utcNow) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => utcNow;
    }

    private sealed record TestUserContext(Guid UserIdValue) : IUserContext
    {
        Guid? IUserContext.UserId => UserIdValue;
    }
}
