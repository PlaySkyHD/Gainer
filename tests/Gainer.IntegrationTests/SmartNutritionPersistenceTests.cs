using Gainer.Core.Mutations;
using Gainer.Core.Nutrition;
using Gainer.Core.Security;
using Gainer.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace Gainer.IntegrationTests;

[TestClass]
[DoNotParallelize]
public sealed class SmartNutritionPersistenceTests
{
    private static readonly string[] ExpectedComponentNames = ["Reis", "Hähnchen"];
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
    public async Task ReusableMealCrudPreservesOrderVersionAndArchiveState()
    {
        (string connectionString, Guid firstUser, _) = await CreateDatabaseAsync();
        Guid mealId = Guid.NewGuid();
        var time = new FixedTimeProvider(new DateTimeOffset(2026, 8, 19, 12, 0, 0, TimeSpan.Zero));

        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, firstUser))
        {
            var changes = new ChangeCollector();
            var handler = new ReusableMealMutationHandler(context, new TestUserContext(firstUser), time, changes);
            ReusableMealSnapshot created = await handler.SaveAsync(SaveMeal(mealId, 0, "Bowl", 1m,
                Component(1, "Hähnchen", 150m, 165m),
                Component(0, "Reis", 200m, 130m)), TestContext.CancellationToken);
            Assert.AreEqual(1, created.Version);
            Assert.AreSequenceEqual(ExpectedComponentNames, created.Components.Select(item => item.Name).ToArray());
            Assert.HasCount(1, changes.Changes);
        }

        time.UtcNow = new DateTimeOffset(2026, 8, 20, 12, 0, 0, TimeSpan.Zero);
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, firstUser))
        {
            var handler = new ReusableMealMutationHandler(context, new TestUserContext(firstUser), time);
            ReusableMealSnapshot updated = await handler.SaveAsync(SaveMeal(mealId, 1, "Bowl XL", 2m,
                Component(0, "Reis", 300m, 130m)), TestContext.CancellationToken);
            Assert.AreEqual(2, updated.Version);
            Assert.AreEqual("Bowl XL", updated.Name);
            Assert.HasCount(1, updated.Components);
            ReusableMealSnapshot archived = await handler.ArchiveAsync(
                ArchiveReusableMealMutation.Create(Metadata(), mealId, 2), TestContext.CancellationToken);
            Assert.AreEqual(3, archived.Version);
            Assert.AreEqual(ReusableMealStatus.Archived, archived.Status);
        }

        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, firstUser))
        {
            var queries = new SmartNutritionQueries(context);
            Assert.IsEmpty(await queries.GetReusableMealsAsync(includeArchived: false, TestContext.CancellationToken));
            Assert.HasCount(1, await queries.GetReusableMealsAsync(includeArchived: true, TestContext.CancellationToken));
            Assert.AreEqual(ReusableMealStatus.Archived, (await queries.GetReusableMealAsync(mealId, TestContext.CancellationToken))?.Status);
        }
    }

    [TestMethod]
    public async Task TargetScheduleSelectsEffectiveVersionAndRejectsHistoricalMutation()
    {
        (string connectionString, Guid firstUser, _) = await CreateDatabaseAsync();
        Guid scheduleId = Guid.NewGuid();
        var time = new FixedTimeProvider(new DateTimeOffset(2026, 8, 20, 12, 0, 0, TimeSpan.Zero));
        NutritionTargetVersionDraft august = Target(new DateOnly(2026, 8, 1), 2500m);
        NutritionTargetVersionDraft september = Target(new DateOnly(2026, 9, 1), 2700m);

        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, firstUser))
        {
            var handler = new NutritionTargetScheduleMutationHandler(context, new TestUserContext(firstUser), time);
            NutritionTargetScheduleSnapshot created = await handler.SaveAsync(SaveTargets(scheduleId, 0, august), TestContext.CancellationToken);
            Assert.AreEqual(1, created.Version);
        }

        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, firstUser))
        {
            var handler = new NutritionTargetScheduleMutationHandler(context, new TestUserContext(firstUser), time);
            NutritionTargetVersionDraft closedAugust = august with { EffectiveUntil = new DateOnly(2026, 8, 31) };
            NutritionTargetScheduleSnapshot updated = await handler.SaveAsync(SaveTargets(scheduleId, 1, closedAugust, september), TestContext.CancellationToken);
            Assert.AreEqual(2, updated.Version);
            Assert.AreEqual(2500m, (await new SmartNutritionQueries(context)
                .GetEffectiveNutritionTargetAsync(new DateOnly(2026, 8, 31), TestContext.CancellationToken))?.Kilocalories);
            Assert.AreEqual(2700m, (await new SmartNutritionQueries(context)
                .GetEffectiveNutritionTargetAsync(new DateOnly(2026, 9, 2), TestContext.CancellationToken))?.Kilocalories);
        }

        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, firstUser))
        {
            var handler = new NutritionTargetScheduleMutationHandler(context, new TestUserContext(firstUser), time);
            NutritionTargetVersionDraft changedAugust = NutritionTargetVersionDraft.Create(
                august.TargetVersionId, august.EffectiveFrom, 2600m, august.ProteinGrams,
                august.CarbohydrateGrams, august.FatGrams, august.Origin, august.AlgorithmVersion, august.Reason);
            await Assert.ThrowsAsync<NutritionTargetScheduleConflictException>(() =>
                handler.SaveAsync(SaveTargets(scheduleId, 2, changedAugust with { EffectiveUntil = new DateOnly(2026, 8, 31) }, september), TestContext.CancellationToken));
            Assert.AreEqual(2500m, (await new SmartNutritionQueries(context)
                .GetEffectiveNutritionTargetAsync(new DateOnly(2026, 8, 15), TestContext.CancellationToken))?.Kilocalories);
        }
    }

    [TestMethod]
    public async Task TargetScheduleSupportsPercentagePhaseBoundariesGapsAndFutureEditing()
    {
        (string connectionString, Guid firstUser, _) = await CreateDatabaseAsync();
        Guid scheduleId = Guid.NewGuid();
        var time = new FixedTimeProvider(new DateTimeOffset(2026, 8, 20, 12, 0, 0, TimeSpan.Zero));
        NutritionTargetVersionDraft current = NutritionTargetVersionDraft.CreateInGrams(
            Guid.NewGuid(), "Sommer Cut", NutritionGoalCategory.Cut,
            new DateOnly(2026, 8, 1), new DateOnly(2026, 8, 31), 2500m, 180m, 260m, 80m);
        NutritionTargetVersionDraft future = NutritionTargetVersionDraft.CreateInPercent(
            Guid.NewGuid(), "Maintenance", NutritionGoalCategory.Maintenance,
            new DateOnly(2026, 9, 2), new DateOnly(2026, 10, 31), 2800m, 30m, 40m, 30m);

        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, firstUser))
        {
            var handler = new NutritionTargetScheduleMutationHandler(context, new TestUserContext(firstUser), time);
            await handler.SaveAsync(SaveTargets(scheduleId, 0, current, future), TestContext.CancellationToken);
        }

        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, firstUser))
        {
            var queries = new SmartNutritionQueries(context);
            Assert.AreEqual("Sommer Cut", (await queries.GetEffectiveNutritionTargetAsync(new DateOnly(2026, 8, 31), TestContext.CancellationToken))?.Name);
            Assert.IsNull(await queries.GetEffectiveNutritionTargetAsync(new DateOnly(2026, 9, 1), TestContext.CancellationToken));
            Assert.AreEqual(NutritionTargetInputMode.Percent,
                (await queries.GetEffectiveNutritionTargetAsync(new DateOnly(2026, 9, 2), TestContext.CancellationToken))?.InputMode);
            Assert.IsNull(await queries.GetEffectiveNutritionTargetAsync(new DateOnly(2026, 11, 1), TestContext.CancellationToken));

            NutritionTargetVersionDraft editedFuture = NutritionTargetVersionDraft.CreateInPercent(
                future.TargetVersionId, "Maintenance 2", NutritionGoalCategory.Maintenance,
                future.EffectiveFrom, future.EffectiveUntil, 2900m, 30m, 40m, 30m);
            NutritionTargetScheduleSnapshot edited = await new NutritionTargetScheduleMutationHandler(
                    context, new TestUserContext(firstUser), time)
                .SaveAsync(SaveTargets(scheduleId, 1, current, editedFuture), TestContext.CancellationToken);
            Assert.AreEqual(2, edited.Version);
            Assert.AreEqual("Maintenance 2", edited.Versions.Single(item => item.TargetVersionId == future.TargetVersionId).Name);
        }
    }

    [TestMethod]
    public async Task QueriesAndMutationsNeverExposeAnotherUsersSmartNutritionData()
    {
        (string connectionString, Guid firstUser, Guid secondUser) = await CreateDatabaseAsync();
        Guid mealId = Guid.NewGuid();
        Guid scheduleId = Guid.NewGuid();
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, firstUser))
        {
            await new ReusableMealMutationHandler(context, new TestUserContext(firstUser), TimeProvider.System)
                .SaveAsync(SaveMeal(mealId, 0, "Private bowl", 1m, Component(0, "Rice", 100m, 130m)), TestContext.CancellationToken);
            await new NutritionTargetScheduleMutationHandler(context, new TestUserContext(firstUser), TimeProvider.System)
                .SaveAsync(SaveTargets(scheduleId, 0, Target(new DateOnly(2026, 8, 1), 2500m)), TestContext.CancellationToken);
        }

        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, secondUser))
        {
            var queries = new SmartNutritionQueries(context);
            Assert.IsNull(await queries.GetReusableMealAsync(mealId, TestContext.CancellationToken));
            Assert.IsNull(await queries.GetNutritionTargetScheduleAsync(TestContext.CancellationToken));
            await Assert.ThrowsAsync<ReusableMealNotFoundException>(() =>
                new ReusableMealMutationHandler(context, new TestUserContext(secondUser), TimeProvider.System)
                    .ArchiveAsync(ArchiveReusableMealMutation.Create(Metadata(), mealId, 1), TestContext.CancellationToken));
            await Assert.ThrowsAsync<NutritionTargetScheduleNotFoundException>(() =>
                new NutritionTargetScheduleMutationHandler(context, new TestUserContext(secondUser), TimeProvider.System)
                    .SaveAsync(SaveTargets(scheduleId, 1, Target(new DateOnly(2026, 9, 1), 2600m)), TestContext.CancellationToken));
        }
    }

    [TestMethod]
    public async Task AdditiveMigrationPreservesExistingNutritionDaySnapshot()
    {
        string connectionString = await Fixture.CreateIsolatedDatabaseAsync();
        Guid userId = Guid.NewGuid();
        Guid dayId = Guid.NewGuid();
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString))
        {
            IMigrator migrator = context.GetService<IMigrator>();
            await migrator.MigrateAsync("20260819172804_AddNutritionTracking", TestContext.CancellationToken);
            context.Users.Add(User(userId, "migration-smart-nutrition@example.test"));
            await context.SaveChangesAsync(TestContext.CancellationToken);
        }
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId))
        {
            // Written in the original schema, not through the current model, which has newer columns.
            DateTime now = DateTime.UtcNow;
            await context.Database.ExecuteSqlInterpolatedAsync($"""
                INSERT INTO tracking.nutrition_days ("Id", "LocalDate", "CreatedAtUtc", "UpdatedAtUtc", "Version", "UserId")
                VALUES ({dayId}, {new DateOnly(2026, 8, 19)}, {now}, {now}, 1, {userId});
                INSERT INTO tracking.nutrition_entries
                    ("Id", "NutritionDayId", "Meal", "Position", "ProductName", "AmountGrams", "AmountUnit", "Kilocalories",
                     "ProteinGrams", "BasisGrams", "KilocaloriesPerBasis", "ProteinGramsPerBasis", "UserId")
                VALUES ({Guid.NewGuid()}, {dayId}, 'Breakfast', 0, 'Existing food', 100, 'g', 100, 10, 100, 100, 10, {userId});
                """, TestContext.CancellationToken);
        }
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId))
        {
            await context.Database.MigrateAsync(TestContext.CancellationToken);
            NutritionDaySnapshot day = await new NutritionQueries(context).GetDayAsync(new DateOnly(2026, 8, 19), TestContext.CancellationToken)
                ?? throw new AssertFailedException();
            Assert.AreEqual(dayId, day.NutritionDayId);
            Assert.AreEqual("Existing food", day.Entries.Single().ProductName);
            Assert.AreEqual(1, day.Version);
            Assert.IsNull(day.Entries.Single().Totals.SaltGrams);
            Assert.AreEqual(0, await context.ReusableMeals.CountAsync(TestContext.CancellationToken));
            Assert.AreEqual(0, await context.NutritionTargetSchedules.CountAsync(TestContext.CancellationToken));
        }
    }

    [TestMethod]
    public async Task GoalPhaseMigrationUpgradesAndCanRollbackLegacyTargetVersions()
    {
        string connectionString = await Fixture.CreateIsolatedDatabaseAsync();
        Guid userId = Guid.NewGuid();
        Guid scheduleId = Guid.NewGuid();
        Guid firstId = Guid.NewGuid();
        Guid secondId = Guid.NewGuid();
        const string previousMigration = "20260819195131_AddSmartMealsAndNutritionTargets";

        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString))
        {
            IMigrator migrator = context.GetService<IMigrator>();
            await migrator.MigrateAsync(previousMigration, TestContext.CancellationToken);
            context.Users.Add(User(userId, "migration-target-phases@example.test"));
            await context.SaveChangesAsync(TestContext.CancellationToken);
            DateTime utcNow = new(2026, 8, 20, 12, 0, 0, DateTimeKind.Utc);
            await context.Database.ExecuteSqlInterpolatedAsync($"""
                INSERT INTO tracking.nutrition_target_schedules
                    ("Id", "CreatedAtUtc", "UpdatedAtUtc", "Version", "UserId")
                VALUES ({scheduleId}, {utcNow}, {utcNow}, {1L}, {userId});
                """, TestContext.CancellationToken);
            await context.Database.ExecuteSqlInterpolatedAsync($"""
                INSERT INTO tracking.nutrition_target_versions
                    ("Id", "NutritionTargetScheduleId", "EffectiveFrom", "Kilocalories",
                     "ProteinGrams", "CarbohydrateGrams", "FatGrams", "Origin",
                     "AlgorithmVersion", "Reason", "UserId")
                VALUES
                    ({firstId}, {scheduleId}, {new DateOnly(2026, 8, 1)}, {2500m}, {180m}, {260m}, {80m}, {"Manual"}, {(string?)null}, {(string?)null}, {userId}),
                    ({secondId}, {scheduleId}, {new DateOnly(2026, 9, 1)}, {2700m}, {190m}, {300m}, {80m}, {"Manual"}, {(string?)null}, {(string?)null}, {userId});
                """, TestContext.CancellationToken);
            await migrator.MigrateAsync(cancellationToken: TestContext.CancellationToken);
        }

        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId))
        {
            NutritionTargetScheduleSnapshot schedule = await new SmartNutritionQueries(context)
                .GetNutritionTargetScheduleAsync(TestContext.CancellationToken) ?? throw new AssertFailedException();
            Assert.HasCount(2, schedule.Versions);
            Assert.AreEqual(new DateOnly(2026, 8, 31), schedule.Versions[0].EffectiveUntil);
            Assert.AreEqual(NutritionGoalCategory.Custom, schedule.Versions[0].Category);
            Assert.AreEqual(NutritionTargetInputMode.Grams, schedule.Versions[0].InputMode);
            Assert.AreEqual("Ziel", schedule.Versions[0].Name);
            Assert.IsNull(schedule.Versions[1].EffectiveUntil);

            await context.GetService<IMigrator>().MigrateAsync(previousMigration, TestContext.CancellationToken);
        }
    }

    [TestMethod]
    public async Task ReorderingComponentsWithStableIdsIsNotAConflict()
    {
        (string connectionString, Guid firstUser, _) = await CreateDatabaseAsync();
        Guid mealId = Guid.NewGuid();
        Guid rice = Guid.NewGuid(), chicken = Guid.NewGuid(), sauce = Guid.NewGuid();
        ReusableMealComponentDraft[][] saves =
        [
            [Component(rice, 0, "Reis"), Component(chicken, 1, "Hähnchen"), Component(sauce, 2, "Soße")],
            // Removing the first component moves the others up.
            [Component(chicken, 0, "Hähnchen"), Component(sauce, 1, "Soße")],
            // Swapping two components.
            [Component(sauce, 0, "Soße"), Component(chicken, 1, "Hähnchen")],
        ];

        for (int index = 0; index < saves.Length; index++)
        {
            await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, firstUser);
            var handler = new ReusableMealMutationHandler(context, new TestUserContext(firstUser), TimeProvider.System);
            ReusableMealSnapshot saved = await handler.SaveAsync(SaveMeal(mealId, index, "Bowl", 1m, saves[index]), TestContext.CancellationToken);
            Assert.AreEqual(index + 1, saved.Version);
            Assert.AreSequenceEqual(
                saves[index].Select(item => item.ComponentId).ToArray(), saved.Components.Select(item => item.ComponentId).ToArray());
        }
    }

    private static SaveReusableMealMutation SaveMeal(
        Guid id, long version, string name, decimal portion, params ReusableMealComponentDraft[] components) =>
        SaveReusableMealMutation.Create(Metadata(), id, version, ReusableMealDraft.Create(name, null, portion, components));

    private static ReusableMealComponentDraft Component(int position, string name, decimal amount, decimal kcal) =>
        ReusableMealComponentDraft.Create(Guid.NewGuid(), position, name, amount, new NutritionPer100Grams(kcal, 10m, 20m, 5m));

    private static ReusableMealComponentDraft Component(Guid id, int position, string name) =>
        ReusableMealComponentDraft.Create(id, position, name, 100m, new NutritionPer100Grams(100m, 10m, 20m, 5m));

    private static NutritionTargetVersionDraft Target(DateOnly effectiveFrom, decimal kcal) =>
        NutritionTargetVersionDraft.Create(Guid.NewGuid(), effectiveFrom, kcal, 180m, 260m, 80m, NutritionTargetOrigin.Manual, null, null);

    private static SaveNutritionTargetScheduleMutation SaveTargets(
        Guid id, long version, params NutritionTargetVersionDraft[] targets) =>
        SaveNutritionTargetScheduleMutation.Create(Metadata(), id, version, NutritionTargetScheduleDraft.Create(targets));

    private static MutationMetadata Metadata() => MutationMetadata.Create(Guid.NewGuid(), Guid.NewGuid(), 1);

    private static async Task<(string ConnectionString, Guid FirstUser, Guid SecondUser)> CreateDatabaseAsync()
    {
        string connectionString = await Fixture.CreateIsolatedDatabaseAsync();
        Guid firstUser = Guid.NewGuid();
        Guid secondUser = Guid.NewGuid();
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString);
        await context.Database.MigrateAsync();
        context.Users.AddRange(User(firstUser, "first-smart-nutrition@example.test"), User(secondUser, "second-smart-nutrition@example.test"));
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
