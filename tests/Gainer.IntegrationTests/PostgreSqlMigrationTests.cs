using Gainer.Core.Sync;
using Gainer.Core.Training;
using Gainer.Infrastructure.HealthChecks;
using Gainer.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Npgsql;

namespace Gainer.IntegrationTests;

[TestClass]
[DoNotParallelize]
public sealed class PostgreSqlMigrationTests
{
    public TestContext TestContext { get; set; } = null!;

    private static PostgreSqlTestFixture? fixture;
    private string? connectionString;

    private static PostgreSqlTestFixture Fixture =>
        fixture ?? throw new InvalidOperationException("The PostgreSQL fixture has not started.");

    private string ConnectionString =>
        connectionString ?? throw new InvalidOperationException("The test database has not been reset.");

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

    [TestInitialize]
    public async Task ResetDatabaseAsync()
    {
        connectionString = await Fixture.CreateIsolatedDatabaseAsync();
    }

    [TestMethod]
    public async Task EmptyDatabaseMigratesAndCreatesRequiredSchemasForTwoUsers()
    {
        await using AppDbContext context = Fixture.CreateContext(ConnectionString);

        await context.Database.MigrateAsync(TestContext.CancellationToken);
        context.Users.AddRange(
            new AppUser { Id = Guid.NewGuid(), UserName = "user-a" },
            new AppUser { Id = Guid.NewGuid(), UserName = "user-b" });
        await context.SaveChangesAsync(TestContext.CancellationToken);

        Assert.AreEqual(2, await context.Users.CountAsync(TestContext.CancellationToken));
        CollectionAssert.AreEquivalent(DatabaseSchemas.All.ToArray(), await ReadSchemasAsync());
        CollectionAssert.Contains(
            (await context.Database.GetAppliedMigrationsAsync(TestContext.CancellationToken)).ToArray(),
            DatabaseSchemaVersion.RequiredMigration);
    }

    [TestMethod]
    public async Task ApplyingMigrationsRepeatedlyKeepsExactlyTheDefinedHistoryEntries()
    {
        await using AppDbContext context = Fixture.CreateContext(ConnectionString);

        await context.Database.MigrateAsync(TestContext.CancellationToken);
        await context.Database.MigrateAsync(TestContext.CancellationToken);
        string[] migrations = (await context.Database.GetAppliedMigrationsAsync(TestContext.CancellationToken)).ToArray();

        CollectionAssert.AreEqual(context.Database.GetMigrations().ToArray(), migrations);
    }

    [TestMethod]
    public async Task TestInitializationProvidesAResetDatabase()
    {
        await using AppDbContext context = Fixture.CreateContext(ConnectionString);

        bool canConnect = await context.Database.CanConnectAsync(TestContext.CancellationToken);
        string[] appliedMigrations = (await context.Database.GetAppliedMigrationsAsync(TestContext.CancellationToken)).ToArray();

        Assert.IsTrue(canConnect);
        Assert.IsEmpty(appliedMigrations);
    }

    [TestMethod]
    public async Task SchemaReadinessRequiresTheCurrentMigration()
    {
        IConfiguration configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ConnectionStrings:gainer-db"] = ConnectionString,
            })
            .Build();
        var healthCheck = new DatabaseSchemaReadinessHealthCheck(configuration);

        HealthCheckResult beforeMigration = await healthCheck.CheckHealthAsync(new HealthCheckContext(), TestContext.CancellationToken);
        await using AppDbContext context = Fixture.CreateContext(ConnectionString);
        await context.Database.MigrateAsync(TestContext.CancellationToken);
        HealthCheckResult afterMigration = await healthCheck.CheckHealthAsync(new HealthCheckContext(), TestContext.CancellationToken);

        Assert.AreEqual(HealthStatus.Unhealthy, beforeMigration.Status);
        Assert.AreEqual(HealthStatus.Healthy, afterMigration.Status);
    }

    [TestMethod]
    public async Task RebuildTrainingModelDropsLegacyTrainingDataAndKeepsCatalog()
    {
        const string previousMigration = "20261017081020_AddExerciseTypesAndCategories";
        Guid userId = Guid.NewGuid();
        Guid workoutId = Guid.NewGuid();
        Guid customExerciseId = Guid.NewGuid();
        Guid mutationId = Guid.NewGuid();
        Guid clientId = Guid.NewGuid();
        await using (AppDbContext previous = Fixture.CreateContext(ConnectionString))
        {
            await ((IInfrastructure<IServiceProvider>)previous).Instance.GetRequiredService<IMigrator>().MigrateAsync(previousMigration, TestContext.CancellationToken);
            previous.Users.Add(new AppUser
            {
                Id = userId,
                UserName = "legacy@example.test",
                NormalizedUserName = "LEGACY@EXAMPLE.TEST",
                Email = "legacy@example.test",
                NormalizedEmail = "LEGACY@EXAMPLE.TEST",
                IsActive = true,
                SecurityStamp = Guid.NewGuid().ToString("N"),
                ConcurrencyStamp = Guid.NewGuid().ToString("N"),
            });
            await previous.SaveChangesAsync(TestContext.CancellationToken);
        }

        await using (NpgsqlConnection connection = new(ConnectionString))
        {
            await connection.OpenAsync(TestContext.CancellationToken);
            await ExecuteAsync(connection, """
                INSERT INTO training.workout_templates ("Id", "Name", "IsArchived", "CreatedAtUtc", "UpdatedAtUtc", "Version", "UserId")
                VALUES (gen_random_uuid(), 'Legacy plan', FALSE, now(), now(), 1, @user);
                INSERT INTO training.workouts ("Id", "UserId", "SourceTemplateId", "TemplateNameSnapshot", "Status", "StartedAtUtc", "CompletedAtUtc", "UpdatedAtUtc", "Version")
                VALUES (@workout, @user, NULL, 'Legacy workout', 'Completed', now() - interval '2 hours', now() - interval '1 hour', now(), 2);
                INSERT INTO training.workout_exercises ("Id", "WorkoutId", "SourceExerciseId", "ExerciseNameSnapshot", "Position", "PlannedSets", "MinimumRepetitions", "MaximumRepetitions", "UserId")
                VALUES (gen_random_uuid(), @workout, NULL, 'Legacy bench', 0, 1, 6, 8, @user);
                """, ("user", userId), ("workout", workoutId));
        }

        await using (AppDbContext previous = Fixture.CreateContext(ConnectionString, userId))
        {
            previous.Exercises.Add(new Exercise
            {
                Id = customExerciseId,
                OwnerUserId = userId,
                Name = "Legacy custom",
                ExerciseType = ExerciseType.Strength,
                CreatedAtUtc = DateTime.UtcNow,
                UpdatedAtUtc = DateTime.UtcNow,
                Version = 1,
            });
            previous.SyncClients.Add(new SyncClient
            {
                Id = clientId,
                DisplayName = "Legacy device",
                ProtocolVersion = 2,
                RegisteredAtUtc = DateTime.UtcNow,
                LastSeenAtUtc = DateTime.UtcNow,
            });
            await previous.SaveChangesAsync(TestContext.CancellationToken);
            previous.UserSyncStates.Add(new UserSyncState
            {
                CurrentRevision = 1,
                ActiveClientId = clientId,
                UpdatedAtUtc = DateTime.UtcNow,
                Version = 1,
            });
            previous.ProcessedMutations.Add(new ProcessedMutation
            {
                MutationId = mutationId,
                ClientId = clientId,
                ClientSequence = 1,
                ContentHash = Enumerable.Repeat((byte)9, 32).ToArray(),
                ResultJson = "{\"revision\":1,\"changes\":[{\"resourceType\":\"Workout\"}]}",
                Revision = 1,
                AppliedAtUtc = DateTime.UtcNow,
            });
            Guid batchId = Guid.NewGuid();
            previous.ChangeBatches.Add(new ChangeBatch
            {
                Id = batchId,
                Revision = 1,
                MutationId = mutationId,
                CreatedAtUtc = DateTime.UtcNow,
            });
            previous.ChangeItems.Add(new ChangeItem
            {
                Id = Guid.NewGuid(),
                BatchId = batchId,
                Position = 0,
                ResourceType = "Workout",
                ResourceId = workoutId,
                ResourceVersion = 2,
                SnapshotJson = "{\"version\":2}",
            });
            await previous.SaveChangesAsync(TestContext.CancellationToken);
        }

        await using (AppDbContext context = Fixture.CreateContext(ConnectionString))
        {
            await context.Database.MigrateAsync(TestContext.CancellationToken);
        }

        await using (NpgsqlConnection connection = new(ConnectionString))
        {
            await connection.OpenAsync(TestContext.CancellationToken);
            Assert.AreEqual(0L, await ScalarAsync(connection, "SELECT COUNT(*) FROM training.workouts"));
            Assert.AreEqual(0L, await ScalarAsync(connection, "SELECT COUNT(*) FROM training.workout_exercises"));
            Assert.AreEqual(0L, await ScalarAsync(connection, "SELECT COUNT(*) FROM sync.change_items WHERE \"ResourceType\" = 'Workout'"));
            Assert.AreEqual(0L, await ScalarAsync(connection, "SELECT COUNT(*) FROM sync.processed_mutations"));
            Assert.AreEqual(0L, await ScalarAsync(connection, "SELECT COUNT(*) FROM training.exercises WHERE \"OwnerUserId\" IS NOT NULL"));
            Assert.IsGreaterThan(0L, await ScalarAsync(connection, "SELECT COUNT(*) FROM training.exercises WHERE \"OwnerUserId\" IS NULL"));
        }
        await using (AppDbContext context = Fixture.CreateContext(ConnectionString, userId))
        {
            Assert.AreEqual(0, await context.TrainingPlans.CountAsync(TestContext.CancellationToken));
            Assert.AreEqual(0, await context.Workouts.CountAsync(TestContext.CancellationToken));
        }
    }

    private static async Task ExecuteAsync(NpgsqlConnection connection, string sql, params (string Name, Guid Value)[] parameters)
    {
        await using var command = new NpgsqlCommand(sql, connection);
        foreach ((string name, Guid value) in parameters) command.Parameters.AddWithValue(name, value);
        await command.ExecuteNonQueryAsync();
    }

    private static async Task<long> ScalarAsync(NpgsqlConnection connection, string sql)
    {
        await using var command = new NpgsqlCommand(sql, connection);
        return Convert.ToInt64(await command.ExecuteScalarAsync());
    }

    private async Task<string[]> ReadSchemasAsync()
    {
        await using var connection = new NpgsqlConnection(ConnectionString);
        await connection.OpenAsync(TestContext.CancellationToken);
        const string query =
            "SELECT schema_name FROM information_schema.schemata " +
            "WHERE schema_name = ANY (@schemas) ORDER BY schema_name";
        await using var command = new NpgsqlCommand(query, connection);
        command.Parameters.AddWithValue("schemas", DatabaseSchemas.All.ToArray());
        await using NpgsqlDataReader reader = await command.ExecuteReaderAsync(TestContext.CancellationToken);
        var schemas = new List<string>();
        while (await reader.ReadAsync(TestContext.CancellationToken))
        {
            schemas.Add(reader.GetString(0));
        }

        return schemas.ToArray();
    }
}
