using Gainer.Core.Security;
using Gainer.Core.Mutations;
using Gainer.Core.Training;
using Gainer.Infrastructure.Catalog;
using Gainer.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.Extensions.DependencyInjection;

namespace Gainer.IntegrationTests;

[TestClass]
[DoNotParallelize]
public sealed class ExerciseCatalogPersistenceTests
{
    public TestContext TestContext { get; set; } = null!;

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
            .ToListAsync(TestContext.CancellationToken);

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
            Limit: 10), TestContext.CancellationToken);

        Assert.AreEqual(2, page.Total);
        Assert.IsTrue(page.Items.Any(item => item.Name == "Barbell Bench Press" && !item.IsCustom));
        Assert.IsTrue(page.Items.Any(item => item.Name == "My Bench Variation" && item.IsCustom));
        Assert.IsFalse(page.Items.Any(item => item.Name.Contains("Secret", StringComparison.Ordinal)));
        await Assert.ThrowsAsync<ArgumentOutOfRangeException>(() =>
            queries.SearchAsync(new ExerciseCatalogFilter(Limit: 101), TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task BaseExerciseCannotBeChangedOrDeletedThroughPersistence()
    {
        string connectionString = await CreateDatabaseAsync();
        Guid userId = Guid.NewGuid();
        await SeedUserAsync(connectionString, userId);
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        Exercise exercise = await context.Exercises.FirstAsync(item => item.OwnerUserId == null, TestContext.CancellationToken);
        exercise.Name = "Changed";

        await Assert.ThrowsAsync<BaseExerciseImmutableException>(() => context.SaveChangesAsync(TestContext.CancellationToken));
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
                new CustomExerciseValues("  My Fly  ", "strength", MuscleGroup: "Chest", Equipment: "Cable")), TestContext.CancellationToken);
            Assert.AreEqual("My Fly", created.Values.Name);
            Assert.AreEqual(1, created.Version);
        }

        await using (AppDbContext otherContext = Fixture.CreateContext(connectionString, otherId))
        {
            var otherQueries = new ExerciseCatalogQueries(otherContext, new TestUserContext(otherId));
            Assert.IsNull(await otherQueries.ResolveAsync(exerciseId, includeArchived: true, TestContext.CancellationToken));
            var handler = new CustomExerciseMutationHandler(
                otherContext,
                new TestUserContext(otherId),
                TimeProvider.System);
            await Assert.ThrowsAsync<CustomExerciseNotFoundException>(() => handler.UpdateAsync(
                UpdateCustomExerciseMutation.Create(
                    Metadata(),
                    exerciseId,
                    1,
                    new CustomExerciseValues("Stolen", "strength")), TestContext.CancellationToken));
        }

        await using (AppDbContext archiveContext = Fixture.CreateContext(connectionString, ownerId))
        {
            var handler = new CustomExerciseMutationHandler(
                archiveContext,
                new TestUserContext(ownerId),
                new FixedTimeProvider(new DateTimeOffset(2026, 8, 19, 12, 0, 0, TimeSpan.Zero)));
            CustomExerciseSnapshot archived = await handler.ArchiveAsync(
                ArchiveCustomExerciseMutation.Create(Metadata(), exerciseId, 1), TestContext.CancellationToken);
            Assert.IsTrue(archived.IsArchived);
            Assert.AreEqual(2, archived.Version);
        }

        await using (AppDbContext readContext = Fixture.CreateContext(connectionString, ownerId))
        {
            var queries = new ExerciseCatalogQueries(readContext, new TestUserContext(ownerId));
            Assert.IsNull(await queries.ResolveAsync(exerciseId, includeArchived: false, TestContext.CancellationToken));
            ExerciseCatalogItem? historicalReference = await queries.ResolveAsync(exerciseId, includeArchived: true, TestContext.CancellationToken);
            Assert.IsNotNull(historicalReference);
            Assert.AreEqual("My Fly", historicalReference.Name);
            ExerciseCatalogPage selectable = await queries.SearchAsync(new ExerciseCatalogFilter(Search: "My Fly"), TestContext.CancellationToken);
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
            CreateCustomExerciseMutation.Create(Metadata(), exerciseId, new CustomExerciseValues("  ", "strength")), TestContext.CancellationToken));
        Assert.AreEqual(0, await context.Exercises.CountAsync(item => item.OwnerUserId == ownerId, TestContext.CancellationToken));

        CustomExerciseSnapshot created = await handler.CreateAsync(CreateCustomExerciseMutation.Create(
            Metadata(), exerciseId, new CustomExerciseValues("Original", "strength")), TestContext.CancellationToken);
        await Assert.ThrowsAsync<CustomExerciseConflictException>(() => handler.UpdateAsync(
            UpdateCustomExerciseMutation.Create(
                Metadata(), exerciseId, created.Version + 1, new CustomExerciseValues("Changed", "strength")), TestContext.CancellationToken));
        context.ChangeTracker.Clear();
        Exercise stored = await context.Exercises.SingleAsync(item => item.Id == exerciseId, TestContext.CancellationToken);
        Assert.AreEqual("Original", stored.Name);
        Assert.AreEqual(1, stored.Version);
    }

    [TestMethod]
    public async Task CustomExerciseMusclesAreValidatedStoredAndReturned()
    {
        string connectionString = await CreateDatabaseAsync();
        Guid ownerId = Guid.NewGuid();
        await SeedUserAsync(connectionString, ownerId);
        Guid exerciseId = Guid.NewGuid();
        await using AppDbContext context = Fixture.CreateContext(connectionString, ownerId);
        var handler = new CustomExerciseMutationHandler(context, new TestUserContext(ownerId), TimeProvider.System);

        CustomExerciseValidationException overlap = await Assert.ThrowsAsync<CustomExerciseValidationException>(() => handler.CreateAsync(
            CreateCustomExerciseMutation.Create(Metadata(), exerciseId, new CustomExerciseValues(
                "Incline Press", "strength", PrimaryMuscles: ["chest"], SecondaryMuscles: ["chest"])),
            TestContext.CancellationToken));
        Assert.IsTrue(overlap.Errors.ContainsKey(nameof(CustomExerciseValues.PrimaryMuscles)));
        await Assert.ThrowsAsync<CustomExerciseValidationException>(() => handler.CreateAsync(
            CreateCustomExerciseMutation.Create(Metadata(), exerciseId, new CustomExerciseValues(
                "Incline Press", "strength", PrimaryMuscles: ["pecs"])),
            TestContext.CancellationToken));

        CustomExerciseSnapshot created = await handler.CreateAsync(CreateCustomExerciseMutation.Create(
            Metadata(), exerciseId, new CustomExerciseValues(
                "Incline Press", "strength", PrimaryMuscles: ["chest"], SecondaryMuscles: ["triceps", "frontDelts"])),
            TestContext.CancellationToken);
        CollectionAssert.AreEqual(new[] { "triceps", "frontDelts" }, created.Values.SecondaryMuscles!.ToArray());

        CustomExerciseSnapshot updated = await handler.UpdateAsync(UpdateCustomExerciseMutation.Create(
            Metadata(), exerciseId, created.Version, new CustomExerciseValues("Incline Press", "strength")),
            TestContext.CancellationToken);
        Assert.IsEmpty(updated.Values.PrimaryMuscles!);

        await handler.UpdateAsync(UpdateCustomExerciseMutation.Create(
            Metadata(), exerciseId, updated.Version, new CustomExerciseValues(
                "Incline Press", "strength", PrimaryMuscles: ["chest", "frontDelts"])),
            TestContext.CancellationToken);
        context.ChangeTracker.Clear();
        var queries = new ExerciseCatalogQueries(context, new TestUserContext(ownerId));
        ExerciseCatalogItem? item = await queries.ResolveAsync(exerciseId, includeArchived: false, TestContext.CancellationToken);
        Assert.IsNotNull(item);
        CollectionAssert.AreEqual(new[] { "chest", "frontDelts" }, item.PrimaryMuscles.ToArray());
        Assert.IsEmpty(item.SecondaryMuscles);
    }

    [TestMethod]
    public async Task BaseExercisesCarryTheirCatalogMuscles()
    {
        string connectionString = await CreateDatabaseAsync();
        await using AppDbContext context = Fixture.CreateContext(connectionString, Guid.NewGuid());
        Dictionary<Guid, Exercise> exercises = await context.Exercises
            .IgnoreQueryFilters()
            .Where(item => item.OwnerUserId == null)
            .ToDictionaryAsync(item => item.Id, TestContext.CancellationToken);

        foreach (ExerciseCatalogEntry entry in ExerciseCatalogSnapshot.Document.Entries)
        {
            CollectionAssert.AreEqual(entry.PrimaryMuscles.ToArray(), exercises[entry.Id].PrimaryMuscles);
            CollectionAssert.AreEqual(entry.SecondaryMuscles.ToArray(), exercises[entry.Id].SecondaryMuscles);
        }
    }

    [TestMethod]
    public async Task EveryBaseExerciseHasTypeBaseCategoriesAndFactorsInAllowedRange()
    {
        string connectionString = await CreateDatabaseAsync();
        await using AppDbContext context = Fixture.CreateContext(connectionString, Guid.NewGuid());
        List<Exercise> exercises = await context.Exercises
            .IgnoreQueryFilters()
            .Where(item => item.OwnerUserId == null)
            .ToListAsync(TestContext.CancellationToken);
        List<ExerciseCategoryAssignment> assignments = await context.ExerciseCategoryAssignments.ToListAsync(TestContext.CancellationToken);
        HashSet<Guid> baseCategoryIds = (await context.ExerciseCategories
            .Where(item => item.OwnerUserId == null)
            .Select(item => item.Id)
            .ToListAsync(TestContext.CancellationToken)).ToHashSet();

        Assert.HasCount(ExerciseCatalogSnapshot.Document.Entries.Count, exercises);
        foreach (Exercise exercise in exercises)
        {
            List<Guid> categoryIds = assignments
                .Where(item => item.ExerciseId == exercise.Id)
                .Select(item => item.CategoryId)
                .ToList();
            Assert.IsNotEmpty(categoryIds, exercise.Name);
            Assert.IsTrue(categoryIds.All(baseCategoryIds.Contains), exercise.Name);
            ExerciseCatalogEntry entry = ExerciseCatalogSnapshot.Document.Entries.Single(item => item.Id == exercise.Id);
            Assert.AreEqual(ExerciseTypes.Parse(entry.ExerciseType), exercise.ExerciseType, exercise.Name);
            Assert.HasCount(entry.CategoryKeys.Count, categoryIds, exercise.Name);
            ExerciseFactors.EnsureValid(exercise.BodyweightFactor, exercise.WeightFactor);
        }

        Assert.HasCount(
            ExerciseCatalogSnapshot.Document.Entries.Sum(item => item.CategoryKeys.Count),
            assignments);
    }

    [TestMethod]
    public async Task BaseCategoriesAreSeededAsBaseEntriesAndCannotBeChangedOrArchived()
    {
        string connectionString = await CreateDatabaseAsync();
        await using (AppDbContext context = Fixture.CreateContext(connectionString, Guid.NewGuid()))
        {
            List<ExerciseCategory> categories = await context.ExerciseCategories.ToListAsync(TestContext.CancellationToken);
            Assert.HasCount(ExerciseCatalogSnapshot.Document.Categories.Count, categories);
            Assert.IsTrue(categories.All(item =>
                item.OwnerUserId == null &&
                !item.IsArchived &&
                item.CatalogVersion == ExerciseCatalogSnapshot.Document.CatalogVersion));
        }

        Guid userId = Guid.NewGuid();
        await SeedUserAsync(connectionString, userId);
        await using (AppDbContext renameContext = Fixture.CreateContext(connectionString, userId))
        {
            ExerciseCategory category = await renameContext.ExerciseCategories.FirstAsync(item => item.OwnerUserId == null, TestContext.CancellationToken);
            category.Name = "Changed";
            await Assert.ThrowsAsync<BaseExerciseImmutableException>(() => renameContext.SaveChangesAsync(TestContext.CancellationToken));
        }

        await using AppDbContext archiveContext = Fixture.CreateContext(connectionString, userId);
        ExerciseCategory archived = await archiveContext.ExerciseCategories.FirstAsync(item => item.OwnerUserId == null, TestContext.CancellationToken);
        archived.IsArchived = true;
        await Assert.ThrowsAsync<BaseExerciseImmutableException>(() => archiveContext.SaveChangesAsync(TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task BaseExerciseTypeAndFactorsCannotBeChangedThroughPersistence()
    {
        string connectionString = await CreateDatabaseAsync();
        Guid userId = Guid.NewGuid();
        await SeedUserAsync(connectionString, userId);
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        Exercise exercise = await context.Exercises.FirstAsync(item => item.OwnerUserId == null, TestContext.CancellationToken);
        exercise.ExerciseType = ExerciseType.Assisted;
        exercise.WeightFactor = 2m;

        await Assert.ThrowsAsync<BaseExerciseImmutableException>(() => context.SaveChangesAsync(TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task CustomExerciseTypeFactorsAndOwnCategoriesPersistAndStayOwnerOnly()
    {
        string connectionString = await CreateDatabaseAsync();
        Guid ownerId = Guid.NewGuid();
        Guid otherId = Guid.NewGuid();
        await SeedUserAsync(connectionString, ownerId);
        await SeedUserAsync(connectionString, otherId);
        Guid exerciseId = Guid.NewGuid();
        Guid categoryId = Guid.NewGuid();
        Guid baseCategoryId = ExerciseCatalogSnapshot.Document.CategoryId("legs");

        await using (AppDbContext createContext = Fixture.CreateContext(connectionString, ownerId))
        {
            createContext.ExerciseCategories.Add(new ExerciseCategory
            {
                Id = categoryId,
                OwnerUserId = ownerId,
                Name = "Reha",
                CreatedAtUtc = DateTime.UtcNow,
                UpdatedAtUtc = DateTime.UtcNow,
                Version = 1,
            });
            createContext.Exercises.Add(new Exercise
            {
                Id = exerciseId,
                OwnerUserId = ownerId,
                Name = "Assisted Pull-Up",
                ExerciseType = ExerciseType.Assisted,
                Notes = "Band",
                BodyweightFactor = 0.9m,
                WeightFactor = 1.5m,
                CreatedAtUtc = DateTime.UtcNow,
                UpdatedAtUtc = DateTime.UtcNow,
                Version = 1,
            });
            createContext.ExerciseCategoryAssignments.AddRange(
                new ExerciseCategoryAssignment { ExerciseId = exerciseId, CategoryId = categoryId },
                new ExerciseCategoryAssignment { ExerciseId = exerciseId, CategoryId = baseCategoryId });
            await createContext.SaveChangesAsync(TestContext.CancellationToken);
        }

        await using (AppDbContext readContext = Fixture.CreateContext(connectionString, ownerId))
        {
            Exercise stored = await readContext.Exercises.SingleAsync(item => item.Id == exerciseId, TestContext.CancellationToken);
            Assert.AreEqual(ExerciseType.Assisted, stored.ExerciseType);
            Assert.AreEqual("Band", stored.Notes);
            Assert.AreEqual(0.9m, stored.BodyweightFactor);
            Assert.AreEqual(1.5m, stored.WeightFactor);
            Assert.AreEqual(2, await readContext.ExerciseCategoryAssignments.CountAsync(item => item.ExerciseId == exerciseId, TestContext.CancellationToken));
        }

        await using AppDbContext otherContext = Fixture.CreateContext(connectionString, otherId);
        ExerciseCategory foreignCategory = await otherContext.ExerciseCategories.SingleAsync(item => item.Id == categoryId, TestContext.CancellationToken);
        foreignCategory.Name = "Stolen";
        await Assert.ThrowsAsync<UserIsolationViolationException>(() => otherContext.SaveChangesAsync(TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task InvalidFactorsAreRejectedByDatabaseConstraints()
    {
        string connectionString = await CreateDatabaseAsync();
        Guid ownerId = Guid.NewGuid();
        await SeedUserAsync(connectionString, ownerId);

        foreach ((decimal? bodyweightFactor, decimal? weightFactor) in new (decimal?, decimal?)[] { (1.01m, null), (-0.01m, null), (null, 0m), (null, 10.01m) })
        {
            await using AppDbContext context = Fixture.CreateContext(connectionString, ownerId);
            context.Exercises.Add(new Exercise
            {
                Id = Guid.NewGuid(),
                OwnerUserId = ownerId,
                Name = "Invalid Factor",
                BodyweightFactor = bodyweightFactor,
                WeightFactor = weightFactor,
                CreatedAtUtc = DateTime.UtcNow,
                UpdatedAtUtc = DateTime.UtcNow,
                Version = 1,
            });
            await Assert.ThrowsAsync<DbUpdateException>(() => context.SaveChangesAsync(TestContext.CancellationToken));
        }
    }

    [TestMethod]
    public async Task MigrationGivesExistingCustomExercisesTheStrengthType()
    {
        string connectionString = await CreateDatabaseAsync();
        Guid ownerId = Guid.NewGuid();
        Guid exerciseId = Guid.NewGuid();
        await SeedUserAsync(connectionString, ownerId);
        await using AppDbContext context = Fixture.CreateContext(connectionString, ownerId);
        List<string> migrations = context.Database.GetMigrations().ToList();
        string migration = migrations.Single(item => item.EndsWith("_AddExerciseTypesAndCategories", StringComparison.Ordinal));
        string previous = migrations[migrations.IndexOf(migration) - 1];

        await context.GetInfrastructure().GetRequiredService<IMigrator>().MigrateAsync(previous, TestContext.CancellationToken);
        await context.Database.ExecuteSqlRawAsync(
            "INSERT INTO training.exercises (\"Id\", \"OwnerUserId\", \"Name\", \"IsArchived\", \"CreatedAtUtc\", \"UpdatedAtUtc\", \"Version\") " +
            "VALUES ({0}, {1}, {2}, FALSE, now(), now(), 1)",
            exerciseId,
            ownerId,
            "Existing Custom");

        await context.GetInfrastructure().GetRequiredService<IMigrator>().MigrateAsync(migration, TestContext.CancellationToken);
        context.ChangeTracker.Clear();
        // Project only columns that exist at this migration; later migrations add more.
        var migrated = await context.Exercises
            .Where(item => item.Id == exerciseId)
            .Select(item => new { item.ExerciseType, item.BodyweightFactor, item.WeightFactor })
            .SingleAsync(TestContext.CancellationToken);
        Assert.AreEqual(ExerciseType.Strength, migrated.ExerciseType);
        Assert.IsNull(migrated.BodyweightFactor);
        Assert.IsNull(migrated.WeightFactor);

        // RebuildTrainingModel resets own exercises together with the training data (D11).
        await context.Database.MigrateAsync(TestContext.CancellationToken);
        context.ChangeTracker.Clear();
        Assert.IsFalse(await context.Exercises.AnyAsync(item => item.Id == exerciseId, TestContext.CancellationToken));
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
