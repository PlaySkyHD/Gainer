using System.Text.Json;
using Gainer.Contracts.Sync;
using Gainer.Core.BodyTracking;
using Gainer.Core.Security;
using Gainer.Core.Sync;
using Gainer.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.Logging;
using Npgsql;

namespace Gainer.IntegrationTests;

/// <summary>
/// Database and payload errors that no retry or pull can resolve are permanent 422 errors, never a stale base version
/// (which the app shows as a newer server version) and never a retryable concurrent mutation or a 500.
/// </summary>
[TestClass]
[DoNotParallelize]
public sealed class SyncErrorMappingTests
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private static readonly DateTimeOffset ServerNow = new(2026, 10, 25, 9, 0, 0, TimeSpan.Zero);
    private static readonly DateOnly Day = new(2026, 10, 25);
    private static readonly DateTime Started = new(2026, 10, 24, 17, 0, 0, DateTimeKind.Utc);
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
    public async Task ReusedWorkoutChildIdIsInvalidPayloadWhileReusedWorkoutIdStaysStale()
    {
        (string connectionString, Guid user, Guid client) = await SetupAsync();
        Guid exerciseId = await BaseExerciseIdAsync(connectionString, user);
        Guid firstWorkout = Guid.NewGuid();
        Guid workoutExerciseId = Guid.NewGuid();
        await Run(connectionString, user, client, 1, Command("createWorkout", "Workout", firstWorkout, 0,
            new { workout = Workout(firstWorkout, exerciseId, workoutExerciseId, Guid.NewGuid()) }));

        // A second workout reusing the child row id of the first one collides on a primary key; no newer stand exists.
        Guid secondWorkout = Guid.NewGuid();
        await ExpectInvalid(connectionString, user, client, 2, Command("createWorkout", "Workout", secondWorkout, 0,
            new { workout = Workout(secondWorkout, exerciseId, workoutExerciseId, Guid.NewGuid()) }), "invalid_payload");

        // The workout id itself already exists: the server holds a stored stand of this resource.
        await ExpectConflict(connectionString, user, client, 2, Command("createWorkout", "Workout", firstWorkout, 0,
            new { workout = Workout(firstWorkout, exerciseId, Guid.NewGuid(), Guid.NewGuid()) }), "stale_base_version");
    }

    [TestMethod]
    public async Task ReusedNutritionEntryIdAndNewDayIdOnStoredDateAreInvalidPayloads()
    {
        (string connectionString, Guid user, Guid client) = await SetupAsync();
        Guid firstDay = Guid.NewGuid();
        Guid entryId = Guid.NewGuid();
        await Run(connectionString, user, client, 1, NutritionDay(firstDay, Day, 0, Entry(entryId)));

        await ExpectInvalid(connectionString, user, client, 2,
            NutritionDay(Guid.NewGuid(), Day.AddDays(1), 0, Entry(entryId)), "invalid_payload");
        await ExpectInvalid(connectionString, user, client, 2,
            NutritionDay(Guid.NewGuid(), Day, 0, Entry(Guid.NewGuid())), "invalid_payload");
        await ExpectConflict(connectionString, user, client, 2,
            NutritionDay(firstDay, Day, 0, Entry(Guid.NewGuid())), "stale_base_version");
    }

    [TestMethod]
    public async Task ValuesBeyondTheStoredRangeAreRejectedBeforeTheDatabase()
    {
        (string connectionString, Guid user, Guid client) = await SetupAsync();

        await ExpectInvalid(connectionString, user, client, 1,
            NutritionDay(Guid.NewGuid(), Day, 0, Entry(Guid.NewGuid(), amountGrams: 100_000m, kilocaloriesPer100Grams: 10_000m)),
            "invalid_payload");
        await ExpectInvalid(connectionString, user, client, 1,
            NutritionDay(Guid.NewGuid(), Day, 0, Entry(Guid.NewGuid(), kilocaloriesPer100Grams: 1_000_000m)),
            "invalid_payload");
        await ExpectInvalid(connectionString, user, client, 1,
            NutritionDay(Guid.NewGuid(), Day, 0, Entry(Guid.NewGuid(), basisGrams: 100_000_000m)),
            "invalid_payload");

        Guid checkInId = Guid.NewGuid();
        await ExpectThrows<DailyCheckInValidationException>(connectionString, user, client, 1,
            Command("createDailyCheckIn", "DailyCheckIn", checkInId, 0,
                new { checkInId, localDate = Day, values = new DailyCheckInValues(10_000m) }));
        await ExpectThrows<DailyCheckInValidationException>(connectionString, user, client, 1,
            Command("createDailyCheckIn", "DailyCheckIn", checkInId, 0,
                new { checkInId, localDate = Day, values = new DailyCheckInValues(80m, CaloriesKcal: 10_000_000m) }));

        Guid goalId = Guid.NewGuid();
        await ExpectThrows<BodyGoalValidationException>(connectionString, user, client, 1,
            Command("activateBodyGoal", "BodyGoal", goalId, 0, new
            {
                goalId,
                kind = "Cut",
                startWeightKg = 10_000m,
                targetWeightKg = 80m,
                startDate = Day,
                targetDate = (DateOnly?)null,
                expectedActiveGoalId = (Guid?)null,
                expectedActiveGoalVersion = (long?)null,
            }));
    }

    [TestMethod]
    public async Task MissingRequiredPayloadFieldsAreInvalidPayloads()
    {
        (string connectionString, Guid user, Guid client) = await SetupAsync();
        Guid dayId = Guid.NewGuid();
        await ExpectInvalid(connectionString, user, client, 1, Command("saveNutritionDay", "NutritionDay", dayId, 0,
            new { nutritionDayId = dayId, localDate = Day, baseVersion = 0 }), "invalid_payload");
        await ExpectInvalid(connectionString, user, client, 1, Command("saveNutritionDay", "NutritionDay", dayId, 0,
            new { nutritionDayId = dayId, localDate = Day, baseVersion = 0, entries = new object?[] { null } }), "invalid_payload");
        await ExpectInvalid(connectionString, user, client, 1, Command("saveNutritionDay", "NutritionDay", dayId, 0,
            new
            {
                nutritionDayId = dayId,
                localDate = Day,
                baseVersion = 0,
                entries = new[] { new { entryId = Guid.NewGuid(), meal = "Lunch", position = 0, amountGrams = 100m, kilocaloriesPer100Grams = 100m } },
            }), "invalid_payload");

        Guid mealId = Guid.NewGuid();
        await ExpectInvalid(connectionString, user, client, 1, Command("saveReusableMeal", "ReusableMeal", mealId, 0,
            new { reusableMealId = mealId, baseVersion = 0, name = "Bowl", standardPortion = 1m }), "invalid_payload");
        await ExpectInvalid(connectionString, user, client, 1, Command("saveReusableMeal", "ReusableMeal", mealId, 0,
            new
            {
                reusableMealId = mealId,
                baseVersion = 0,
                standardPortion = 1m,
                components = new[] { new { componentId = Guid.NewGuid(), position = 0, name = "Reis", amountGrams = 100m, kilocaloriesPer100Grams = 130m } },
            }), "invalid_payload");

        Guid scheduleId = Guid.NewGuid();
        await ExpectInvalid(connectionString, user, client, 1, Command("saveNutritionTargetSchedule", "NutritionTargetSchedule", scheduleId, 0,
            new { nutritionTargetScheduleId = scheduleId, baseVersion = 0 }), "invalid_payload");
    }

    [TestMethod]
    public async Task UnhashablePayloadsAndNullResourcesAreRejectedAsInvalid()
    {
        (string connectionString, Guid user, Guid client) = await SetupAsync();
        Guid dayId = Guid.NewGuid();

        using JsonDocument duplicate = JsonDocument.Parse($$"""{"waterIntakeDayId":"{{dayId}}","waterIntakeDayId":"{{dayId}}","localDate":"2026-10-25","baseVersion":0,"amountMl":200}""");
        await ExpectInvalid(connectionString, user, client, 1, Water(dayId, duplicate.RootElement.Clone()), "invalid_payload");
        using JsonDocument huge = JsonDocument.Parse($$"""{"waterIntakeDayId":"{{dayId}}","localDate":"2026-10-25","baseVersion":0,"amountMl":1e100}""");
        await ExpectInvalid(connectionString, user, client, 1, Water(dayId, huge.RootElement.Clone()), "invalid_payload");
        await ExpectInvalid(connectionString, user, client, 1, Water(dayId, default), "invalid_payload");

        ProcessSyncMutationCommand nullResource = Water(dayId, JsonSerializer.SerializeToElement(new { }, JsonOptions));
        nullResource = nullResource with { Content = nullResource.Content with { Resources = [null!] } };
        await ExpectInvalid(connectionString, user, client, 1, nullResource, "invalid_resources");
    }

    [TestMethod]
    public async Task PayloadDeserializationErrorsUseAFixedTitle()
    {
        (string connectionString, Guid user, Guid client) = await SetupAsync();
        Guid dayId = Guid.NewGuid();
        SyncMutationValidationException invalid = await ExpectInvalid(connectionString, user, client, 1,
            Water(dayId, JsonSerializer.SerializeToElement(
                new { waterIntakeDayId = dayId, localDate = Day, baseVersion = 0, amountMl = "viel" }, JsonOptions)),
            "invalid_payload");

        Assert.AreEqual("The mutation payload is invalid.", invalid.Message);
    }

    [TestMethod]
    public async Task ReusedClientSequenceIsAPermanentEnvelopeError()
    {
        (string connectionString, Guid user, Guid client) = await SetupAsync();
        Guid firstDay = Guid.NewGuid();
        await Run(connectionString, user, client, 1, Water(firstDay, WaterPayload(firstDay, Day)));

        // A reset sequence counter: another mutation id with the same client sequence fails on every retry.
        Guid secondDay = Guid.NewGuid();
        SyncMutationValidationException invalid = await ExpectInvalid(connectionString, user, client, 1,
            Water(secondDay, WaterPayload(secondDay, Day.AddDays(1))), "invalid_envelope");
        Assert.IsInstanceOfType<DbUpdateException>(invalid.InnerException);
    }

    [TestMethod]
    [DataRow(PostgresErrorCodes.SerializationFailure)]
    [DataRow(PostgresErrorCodes.DeadlockDetected)]
    public async Task SerializationFailuresInTheBodyGoalHandlerStayRetryable(string sqlState)
    {
        (string connectionString, Guid user, Guid client) = await SetupAsync();
        Guid goalId = Guid.NewGuid();
        await using AppDbContext context = PostgreSqlTestFixture.CreateContextWithInterceptors(
            connectionString, user, new FailingInsertInterceptor<BodyGoal>(sqlState));

        SyncMutationConflictException conflict = await Assert.ThrowsExactlyAsync<SyncMutationConflictException>(() =>
            Processor(context, user).ProcessAsync(For(ActivateGoal(goalId), client, 1), TestContext.CancellationToken));
        Assert.AreEqual("concurrent_mutation", conflict.Code);
    }

    [TestMethod]
    public async Task NewCheckInIdOnAStoredDateIsInvalidPayloadWhileTheSameIdStaysStale()
    {
        (string connectionString, Guid user, Guid client) = await SetupAsync();
        Guid checkInId = Guid.NewGuid();
        await Run(connectionString, user, client, 1, CheckIn(checkInId, Day));

        await ExpectInvalid(connectionString, user, client, 2, CheckIn(Guid.NewGuid(), Day), "invalid_payload");
        await ExpectConflict(connectionString, user, client, 2, CheckIn(checkInId, Day.AddDays(1)), "stale_base_version");
    }

    [TestMethod]
    public async Task AnIdOwnedByAnotherUserIsInvalidPayloadWithoutDetails()
    {
        (string connectionString, Guid owner, Guid ownerClient) = await SetupAsync();
        (Guid other, Guid otherClient) = await AddUserAsync(connectionString);
        Guid exerciseId = await BaseExerciseIdAsync(connectionString, owner);
        Guid dayId = Guid.NewGuid();
        Guid workoutId = Guid.NewGuid();
        Guid checkInId = Guid.NewGuid();
        Guid scheduleId = Guid.NewGuid();
        await Run(connectionString, owner, ownerClient, 1, NutritionDay(dayId, Day, 0, Entry(Guid.NewGuid())));
        await Run(connectionString, owner, ownerClient, 2, Command("createWorkout", "Workout", workoutId, 0,
            new { workout = Workout(workoutId, exerciseId, Guid.NewGuid(), Guid.NewGuid()) }));
        await Run(connectionString, owner, ownerClient, 3, CheckIn(checkInId, Day));
        await Run(connectionString, owner, ownerClient, 4, TargetSchedule(scheduleId));

        // The other user's lookup cannot see these ids, so the insert hits the primary key. No pull can heal that.
        ProcessSyncMutationCommand[] foreign =
        [
            NutritionDay(dayId, Day, 0, Entry(Guid.NewGuid())),
            Command("createWorkout", "Workout", workoutId, 0,
                new { workout = Workout(workoutId, exerciseId, Guid.NewGuid(), Guid.NewGuid()) }),
            CheckIn(checkInId, Day),
            TargetSchedule(scheduleId),
        ];
        foreach (ProcessSyncMutationCommand command in foreign)
        {
            SyncMutationValidationException invalid =
                await ExpectInvalid(connectionString, other, otherClient, 1, command, "invalid_payload");
            Assert.AreEqual("The mutation payload conflicts with stored data.", invalid.Message);
        }

        await using AppDbContext read = PostgreSqlTestFixture.CreateContext(connectionString, owner);
        Assert.AreEqual(1, (await read.NutritionDays.SingleAsync(item => item.Id == dayId, TestContext.CancellationToken)).Version);
        Assert.AreEqual(1, (await read.Workouts.SingleAsync(item => item.Id == workoutId, TestContext.CancellationToken)).Version);
    }

    [TestMethod]
    public async Task DatabaseRejectionsKeepTheirCauseAndLogItWithoutValues()
    {
        (string connectionString, Guid user, Guid client) = await SetupAsync();
        Guid exerciseId = await BaseExerciseIdAsync(connectionString, user);
        Guid firstWorkout = Guid.NewGuid();
        Guid workoutExerciseId = Guid.NewGuid();
        await Run(connectionString, user, client, 1, Command("createWorkout", "Workout", firstWorkout, 0,
            new { workout = Workout(firstWorkout, exerciseId, workoutExerciseId, Guid.NewGuid()) }));

        var logger = new ListLogger();
        Guid secondWorkout = Guid.NewGuid();
        SyncMutationValidationException invalid = await ExpectInvalid(connectionString, user, client, 2,
            Command("createWorkout", "Workout", secondWorkout, 0,
                new { workout = Workout(secondWorkout, exerciseId, workoutExerciseId, Guid.NewGuid()) }),
            "invalid_payload", logger);

        Assert.IsInstanceOfType<DbUpdateException>(invalid.InnerException);
        string entry = logger.Messages.Single();
        Assert.Contains(PostgresErrorCodes.UniqueViolation, entry);
        Assert.Contains("workout_exercises", entry);
        Assert.IsFalse(entry.Contains(workoutExerciseId.ToString(), StringComparison.OrdinalIgnoreCase));
    }

    [TestMethod]
    public async Task PayloadDeserializationErrorsLogThePathWithoutTheValue()
    {
        (string connectionString, Guid user, Guid client) = await SetupAsync();
        Guid dayId = Guid.NewGuid();
        var logger = new ListLogger();
        SyncMutationValidationException invalid = await ExpectInvalid(connectionString, user, client, 1,
            Water(dayId, JsonSerializer.SerializeToElement(
                new { waterIntakeDayId = dayId, localDate = Day, baseVersion = 0, amountMl = "viel" }, JsonOptions)),
            "invalid_payload", logger);

        Assert.IsInstanceOfType<JsonException>(invalid.InnerException);
        string entry = logger.Messages.Single();
        Assert.Contains("$.amountMl", entry);
        Assert.IsFalse(entry.Contains("viel", StringComparison.Ordinal));
    }

    [TestMethod]
    public async Task SaltAndFiberOutsideTheirRangeAreInvalidPayloads()
    {
        (string connectionString, Guid user, Guid client) = await SetupAsync();

        await ExpectInvalid(connectionString, user, client, 1,
            NutritionDay(Guid.NewGuid(), Day, 0, Entry(Guid.NewGuid(), saltGramsPer100Grams: 1e8m)), "invalid_payload");
        await ExpectInvalid(connectionString, user, client, 1,
            NutritionDay(Guid.NewGuid(), Day, 0, Entry(Guid.NewGuid(), fiberGramsPer100Grams: -1m)), "invalid_payload");
    }

    private static JsonElement WaterPayload(Guid dayId, DateOnly localDate) =>
        JsonSerializer.SerializeToElement(new { waterIntakeDayId = dayId, localDate, baseVersion = 0, amountMl = 200 }, JsonOptions);

    private static ProcessSyncMutationCommand CheckIn(Guid checkInId, DateOnly localDate) =>
        Command("createDailyCheckIn", "DailyCheckIn", checkInId, 0,
            new { checkInId, localDate, values = new DailyCheckInValues(80m) });

    private static ProcessSyncMutationCommand ActivateGoal(Guid goalId) =>
        Command("activateBodyGoal", "BodyGoal", goalId, 0, new
        {
            goalId,
            kind = "Cut",
            startWeightKg = 85m,
            targetWeightKg = 80m,
            startDate = Day,
            targetDate = (DateOnly?)null,
            expectedActiveGoalId = (Guid?)null,
            expectedActiveGoalVersion = (long?)null,
        });

    private static ProcessSyncMutationCommand TargetSchedule(Guid scheduleId) =>
        Command("saveNutritionTargetSchedule", "NutritionTargetSchedule", scheduleId, 0, new
        {
            nutritionTargetScheduleId = scheduleId,
            baseVersion = 0,
            versions = new[]
            {
                new { targetVersionId = Guid.NewGuid(), effectiveFrom = Day, kilocalories = 2500m, proteinGrams = 180m, carbohydrateGrams = 260m, fatGrams = 80m, origin = "Manual" },
            },
        });

    private static ProcessSyncMutationCommand Water(Guid dayId, JsonElement payload) => new(
        Guid.NewGuid(),
        new CanonicalMutationContent(
            SyncProtocol.CurrentVersion, Guid.Empty, 0, "setWaterIntake",
            [new CanonicalResourceVersion("WaterIntakeDay", dayId, 0)], null, payload));

    private static ProcessSyncMutationCommand NutritionDay(Guid dayId, DateOnly localDate, long baseVersion, object entry) =>
        Command("saveNutritionDay", "NutritionDay", dayId, baseVersion,
            new { nutritionDayId = dayId, localDate, baseVersion, entries = new[] { entry } });

    private static object Entry(
        Guid entryId,
        decimal amountGrams = 150m,
        decimal kilocaloriesPer100Grams = 120m,
        decimal basisGrams = 100m,
        decimal? saltGramsPer100Grams = null,
        decimal? fiberGramsPer100Grams = null) => new
        {
            entryId,
            meal = "Lunch",
            position = 0,
            productName = "Joghurt",
            brand = (string?)null,
            amountGrams,
            kilocaloriesPer100Grams,
            proteinGramsPer100Grams = (decimal?)4m,
            carbohydrateGramsPer100Grams = (decimal?)5m,
            fatGramsPer100Grams = (decimal?)3m,
            saltGramsPer100Grams,
            fiberGramsPer100Grams,
            source = new { provider = (string?)null, barcode = (string?)null, retrievedAtUtc = (DateTime?)null, basisGrams },
        };

    private static object Workout(Guid workoutId, Guid exerciseId, Guid workoutExerciseId, Guid setId) => new
    {
        workoutId,
        title = "Push",
        notes = (string?)null,
        startedAtUtc = Started,
        endedAtUtc = Started.AddHours(1),
        previousValueSource = "exercise",
        sourcePlanId = (Guid?)null,
        sourceWorkoutId = (Guid?)null,
        exercises = new[]
        {
            new
            {
                workoutExerciseId,
                sourceExerciseId = exerciseId,
                exerciseNameSnapshot = "Bench",
                exerciseTypeSnapshot = "strength",
                notes = (string?)null,
                supersetId = (Guid?)null,
                sets = new[]
                {
                    new { setId, setType = "normal", weightKg = (decimal?)100, repetitions = (int?)8, rir = (decimal?)null, notes = (string?)null },
                },
            },
        },
    };

    private static ProcessSyncMutationCommand Command(
        string operation, string resourceType, Guid resourceId, long baseVersion, object payload) => new(
            Guid.NewGuid(),
            new CanonicalMutationContent(
                SyncProtocol.CurrentVersion,
                Guid.Empty,
                0,
                operation,
                [new CanonicalResourceVersion(resourceType, resourceId, baseVersion)],
                null,
                JsonSerializer.SerializeToElement(payload, JsonOptions)));

    private static ProcessSyncMutationCommand For(ProcessSyncMutationCommand command, Guid client, long sequence) =>
        command with { Content = command.Content with { ClientId = client, ClientSequence = sequence } };

    private static async Task Run(string connectionString, Guid user, Guid client, long sequence, ProcessSyncMutationCommand command)
    {
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, user);
        _ = await Processor(context, user).ProcessAsync(For(command, client, sequence));
    }

    private static async Task ExpectConflict(
        string connectionString, Guid user, Guid client, long sequence, ProcessSyncMutationCommand command, string code)
    {
        SyncMutationConflictException conflict =
            await ExpectThrows<SyncMutationConflictException>(connectionString, user, client, sequence, command);
        Assert.AreEqual(code, conflict.Code);
    }

    private static async Task<SyncMutationValidationException> ExpectInvalid(
        string connectionString,
        Guid user,
        Guid client,
        long sequence,
        ProcessSyncMutationCommand command,
        string code,
        ILogger<SyncMutationProcessor>? logger = null)
    {
        SyncMutationValidationException invalid =
            await ExpectThrows<SyncMutationValidationException>(connectionString, user, client, sequence, command, logger);
        Assert.AreEqual(code, invalid.Code);
        return invalid;
    }

    private static async Task<TException> ExpectThrows<TException>(
        string connectionString,
        Guid user,
        Guid client,
        long sequence,
        ProcessSyncMutationCommand command,
        ILogger<SyncMutationProcessor>? logger = null)
        where TException : Exception
    {
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, user);
        return await Assert.ThrowsExactlyAsync<TException>(() =>
            Processor(context, user, logger).ProcessAsync(For(command, client, sequence)));
    }

    private static SyncMutationProcessor Processor(
        AppDbContext context,
        Guid userId,
        ILogger<SyncMutationProcessor>? logger = null)
    {
        var user = new UserContext(userId);
        var time = new FixedTimeProvider(ServerNow);
        return new SyncMutationProcessor(context, user, new SyncMutationExecutor(context, user, time), time, logger);
    }

    private static async Task<Guid> BaseExerciseIdAsync(string connectionString, Guid userId)
    {
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
        return await context.Exercises.Where(item => item.OwnerUserId == null)
            .OrderBy(item => item.Id).Select(item => item.Id).FirstAsync();
    }

    private static async Task<(string ConnectionString, Guid User, Guid Client)> SetupAsync()
    {
        string connectionString = await Fixture.CreateIsolatedDatabaseAsync();
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString))
        {
            await context.Database.MigrateAsync();
        }
        (Guid user, Guid client) = await AddUserAsync(connectionString);
        return (connectionString, user, client);
    }

    private static async Task<(Guid User, Guid Client)> AddUserAsync(string connectionString)
    {
        Guid user = Guid.NewGuid();
        Guid client = Guid.NewGuid();
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString))
        {
            context.Users.Add(User(user));
            await context.SaveChangesAsync();
        }
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, user))
        {
            context.SyncClients.Add(new SyncClient
            {
                Id = client,
                DisplayName = "Error mapping test",
                ProtocolVersion = SyncProtocol.CurrentVersion,
                RegisteredAtUtc = DateTime.UtcNow,
                LastSeenAtUtc = DateTime.UtcNow,
            });
            context.UserSyncStates.Add(new UserSyncState
            {
                CurrentRevision = 0,
                ActiveClientId = client,
                UpdatedAtUtc = DateTime.UtcNow,
                Version = 1,
            });
            await context.SaveChangesAsync();
        }
        return (user, client);
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

    private sealed class FixedTimeProvider(DateTimeOffset utcNow) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => utcNow;
    }

    /// <summary>Fails the save that inserts a <typeparamref name="TEntity"/> with the given PostgreSQL error.</summary>
    private sealed class FailingInsertInterceptor<TEntity>(string sqlState) : SaveChangesInterceptor
        where TEntity : class
    {
        public override ValueTask<InterceptionResult<int>> SavingChangesAsync(
            DbContextEventData eventData,
            InterceptionResult<int> result,
            CancellationToken cancellationToken = default)
        {
            if (eventData.Context?.ChangeTracker.Entries<TEntity>().Any(entry => entry.State == EntityState.Added) == true)
            {
                throw new DbUpdateException(
                    "Injected database failure.",
                    new PostgresException("Injected failure.", "ERROR", "ERROR", sqlState));
            }
            return base.SavingChangesAsync(eventData, result, cancellationToken);
        }
    }

    private sealed class ListLogger : ILogger<SyncMutationProcessor>
    {
        public List<string> Messages { get; } = [];

        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;

        public bool IsEnabled(LogLevel logLevel) => true;

        public void Log<TState>(
            LogLevel logLevel,
            EventId eventId,
            TState state,
            Exception? exception,
            Func<TState, Exception?, string> formatter) =>
            Messages.Add(formatter(state, exception));
    }
}
