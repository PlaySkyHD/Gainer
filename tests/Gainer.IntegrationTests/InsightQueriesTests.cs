using Gainer.Core.BodyTracking;
using Gainer.Core.Insights;
using Gainer.Core.Nutrition;
using Gainer.Core.Security;
using Gainer.Core.Training;
using Gainer.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using System.Data;

namespace Gainer.IntegrationTests;

[TestClass]
[DoNotParallelize]
public sealed class InsightQueriesTests
{
    public TestContext TestContext { get; set; } = null!;

    private static PostgreSqlTestFixture? fixture;
    private static PostgreSqlTestFixture Fixture => fixture!;
    private static readonly TimeZoneInfo Berlin = TimeZoneInfo.FindSystemTimeZoneById("Europe/Berlin");

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
    public async Task DashboardUsesOneRevisionAndOnlyCompletedOwnedData()
    {
        (string connectionString, Guid firstUser, Guid secondUser) = await CreateDatabaseAsync();
        Guid exerciseId = Guid.NewGuid();
        await SeedCheckInsAndWorkoutAsync(connectionString, firstUser, exerciseId);
        await using AppDbContext first = PostgreSqlTestFixture.CreateContext(connectionString, firstUser);
        DashboardInsightSnapshot dashboard = await new InsightQueries(first, new TestUserContext(firstUser))
            .DashboardAsync(new DateOnly(2026, 8, 18), 7, Berlin, TestContext.CancellationToken);
        Assert.AreEqual(0, dashboard.AsOfRevision);
        Assert.AreEqual(2, dashboard.Weight.ObservedDays);
        Assert.AreEqual(80.5m, dashboard.Weight.AverageKg);
        Assert.AreEqual(1, dashboard.Training.WorkoutCount);
        Assert.AreEqual(1800m, dashboard.Training.VolumeKgRepetitions);

        await using AppDbContext second = PostgreSqlTestFixture.CreateContext(connectionString, secondUser);
        DashboardInsightSnapshot isolated = await new InsightQueries(second, new TestUserContext(secondUser))
            .DashboardAsync(new DateOnly(2026, 8, 18), 7, Berlin, TestContext.CancellationToken);
        Assert.AreEqual(0, isolated.Weight.ObservedDays);
        Assert.AreEqual(0, isolated.Training.WorkoutCount);
    }

    [TestMethod]
    public async Task DashboardPrefersMealDiaryWithoutAddingLegacyAndPreservesMissingMacros()
    {
        (string connectionString, Guid firstUser, Guid secondUser) = await CreateDatabaseAsync();
        await using (AppDbContext seed = PostgreSqlTestFixture.CreateContext(connectionString, firstUser))
        {
            seed.DailyCheckIns.AddRange(
                CheckIn(new DateOnly(2026, 8, 17), 80m),
                CheckIn(new DateOnly(2026, 8, 18), 81m));
            var day = new NutritionDay
            {
                Id = Guid.NewGuid(),
                LocalDate = new DateOnly(2026, 8, 18),
                CreatedAtUtc = DateTime.UtcNow,
                UpdatedAtUtc = DateTime.UtcNow,
                Version = 1,
            };
            day.Entries.Add(new NutritionEntry
            {
                Id = Guid.NewGuid(),
                NutritionDayId = day.Id,
                Meal = MealType.Dinner,
                Position = 0,
                ProductName = "Meal",
                AmountGrams = 300m,
                Kilocalories = 600m,
                ProteinGrams = null,
                CarbohydrateGrams = 50m,
                FatGrams = null,
                BasisGrams = 100m,
                KilocaloriesPerBasis = 200m,
            });
            seed.NutritionDays.Add(day);
            await seed.SaveChangesAsync(TestContext.CancellationToken);
        }

        await using AppDbContext first = PostgreSqlTestFixture.CreateContext(connectionString, firstUser);
        DashboardInsightSnapshot dashboard = await new InsightQueries(first, new TestUserContext(firstUser))
            .DashboardAsync(new DateOnly(2026, 8, 18), 2, Berlin, TestContext.CancellationToken);
        Assert.AreEqual(1550m, dashboard.Nutrition.CaloriesKcal.Value);
        Assert.AreEqual(180m, dashboard.Nutrition.ProteinGrams.Value);
        Assert.AreEqual(1, dashboard.Nutrition.ProteinGrams.ObservedDays);
        Assert.AreEqual(1, dashboard.Nutrition.MealDiaryDays);
        Assert.AreEqual(1, dashboard.Nutrition.LegacyCheckInDays);

        await using AppDbContext second = PostgreSqlTestFixture.CreateContext(connectionString, secondUser);
        DashboardInsightSnapshot isolated = await new InsightQueries(second, new TestUserContext(secondUser))
            .DashboardAsync(new DateOnly(2026, 8, 18), 2, Berlin, TestContext.CancellationToken);
        Assert.AreEqual(0, isolated.Nutrition.ObservedDays);
        Assert.AreEqual(0, isolated.Nutrition.MealDiaryDays);
    }

    [TestMethod]
    public async Task ExerciseProgressUsesStableExerciseIdTimezoneWindowAndDeterministicTieBreaker()
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        Guid exerciseId = Guid.NewGuid();
        await SeedCheckInsAndWorkoutAsync(connectionString, userId, exerciseId);
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
        ExerciseProgressSnapshot result = await new InsightQueries(context, new TestUserContext(userId)).ExerciseProgressAsync(
            exerciseId,
            7,
            new DateTime(2026, 8, 18, 22, 30, 0, DateTimeKind.Utc),
            Berlin, TestContext.CancellationToken);
        Assert.HasCount(1, result.Points);
        Assert.AreEqual(1800m, result.Points[0].VolumeKgRepetitions);
        Assert.AreEqual(140m, result.BestSet!.EstimatedOneRepMaxKg);

        ExerciseProgressSnapshot missing = await new InsightQueries(context, new TestUserContext(userId)).ExerciseProgressAsync(
            Guid.NewGuid(), 30, new DateTime(2026, 8, 18, 22, 30, 0, DateTimeKind.Utc), TimeZoneInfo.Utc, TestContext.CancellationToken);
        Assert.IsEmpty(missing.Points);
        Assert.IsNull(missing.BestSet);
    }

    [TestMethod]
    public async Task RepeatableReadKeepsRevisionAndDashboardRowsAtOneDataSnapshot()
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        await using (AppDbContext seed = PostgreSqlTestFixture.CreateContext(connectionString, userId))
        {
            seed.DailyCheckIns.Add(CheckIn(new DateOnly(2026, 8, 17), 80m));
            await seed.SaveChangesAsync(TestContext.CancellationToken);
        }
        await using AppDbContext reader = PostgreSqlTestFixture.CreateContext(connectionString, userId);
        await using var transaction = await reader.Database.BeginTransactionAsync(IsolationLevel.RepeatableRead, TestContext.CancellationToken);
        int before = await reader.DailyCheckIns.CountAsync(TestContext.CancellationToken);
        long revisionBefore = await reader.UserSyncStates.Select(item => (long?)item.CurrentRevision).SingleOrDefaultAsync(TestContext.CancellationToken) ?? 0;

        await using (AppDbContext writer = PostgreSqlTestFixture.CreateContext(connectionString, userId))
        {
            writer.DailyCheckIns.Add(CheckIn(new DateOnly(2026, 8, 18), 81m));
            writer.UserSyncStates.Add(new Gainer.Core.Sync.UserSyncState
            {
                CurrentRevision = 1,
                UpdatedAtUtc = DateTime.UtcNow,
                Version = 1,
            });
            await writer.SaveChangesAsync(TestContext.CancellationToken);
        }

        Assert.AreEqual(before, await reader.DailyCheckIns.CountAsync(TestContext.CancellationToken));
        Assert.AreEqual(revisionBefore,
            await reader.UserSyncStates.Select(item => (long?)item.CurrentRevision).SingleOrDefaultAsync(TestContext.CancellationToken) ?? 0);
        await transaction.CommitAsync(TestContext.CancellationToken);
    }

    private static async Task SeedCheckInsAndWorkoutAsync(string connectionString, Guid userId, Guid exerciseId)
    {
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
        context.Exercises.Add(new Exercise
        {
            Id = exerciseId,
            OwnerUserId = userId,
            Name = "Bench",
            CreatedAtUtc = DateTime.UtcNow,
            UpdatedAtUtc = DateTime.UtcNow,
            Version = 1,
        });
        context.DailyCheckIns.AddRange(
            CheckIn(new DateOnly(2026, 8, 17), 80m),
            CheckIn(new DateOnly(2026, 8, 18), 81m));
        Guid workoutId = Guid.NewGuid();
        Guid workoutExerciseId = Guid.NewGuid();
        DateTime completed = new(2026, 8, 18, 20, 0, 0, DateTimeKind.Utc);
        context.Workouts.Add(new Workout
        {
            Id = workoutId,
            Title = "Snapshot",
            StartedAtUtc = completed.AddHours(-1),
            EndedAtUtc = completed,
            PreviousValueSource = PreviousValueSource.Exercise,
            CreatedAtUtc = completed.AddHours(-1),
            UpdatedAtUtc = completed,
            Version = 2,
        });
        context.WorkoutExercises.Add(new WorkoutExercise
        {
            Id = workoutExerciseId,
            WorkoutId = workoutId,
            SourceExerciseId = exerciseId,
            ExerciseNameSnapshot = "Bench",
            ExerciseTypeSnapshot = ExerciseType.Strength,
            Position = 0,
        });
        context.WorkoutSets.AddRange(
            Set(workoutId, workoutExerciseId, 0, 100m, 6),
            Set(workoutId, workoutExerciseId, 1, 100m, 12));
        await context.SaveChangesAsync();
    }

    private static DailyCheckIn CheckIn(DateOnly date, decimal weight) => new()
    {
        Id = Guid.NewGuid(),
        LocalDate = date,
        WeightKg = weight,
        CaloriesKcal = 2500m,
        ProteinGrams = 180m,
        CreatedAtUtc = DateTime.UtcNow,
        UpdatedAtUtc = DateTime.UtcNow,
        Version = 1,
    };

    private static WorkoutSet Set(Guid workoutId, Guid exerciseId, int position, decimal weight, int reps) => new()
    {
        Id = Guid.NewGuid(),
        WorkoutId = workoutId,
        WorkoutExerciseId = exerciseId,
        Position = position,
        SetType = WorkoutSetType.Normal,
        WeightKg = weight,
        Repetitions = reps,
    };

    private sealed record TestUserContext(Guid? UserId) : IUserContext;

    private static async Task<(string ConnectionString, Guid FirstUser, Guid SecondUser)> CreateDatabaseAsync()
    {
        string connectionString = await Fixture.CreateIsolatedDatabaseAsync();
        Guid first = Guid.NewGuid();
        Guid second = Guid.NewGuid();
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString);
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
}
