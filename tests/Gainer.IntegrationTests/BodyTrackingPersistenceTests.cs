using Gainer.Core.BodyTracking;
using Gainer.Core.Mutations;
using Gainer.Core.Security;
using Gainer.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Gainer.IntegrationTests;

[TestClass]
[DoNotParallelize]
public sealed class BodyTrackingPersistenceTests
{
    private static readonly string[] ExpectedInvalidGoalFields = ["Kind", "StartWeightKg", "TargetWeightKg", "TargetDate"];
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
    public async Task PartialUniqueIndexAllowsOnlyOneActiveGoalPerUser()
    {
        (string connectionString, Guid firstUser, Guid secondUser) = await CreateDatabaseAsync();
        await using (AppDbContext first = Fixture.CreateContext(connectionString, firstUser))
        {
            AddOwned(first, Goal(Guid.NewGuid(), startDate: new DateOnly(2026, 8, 1)), firstUser);
            await first.SaveChangesAsync();
        }
        await using (AppDbContext second = Fixture.CreateContext(connectionString, secondUser))
        {
            AddOwned(second, Goal(Guid.NewGuid(), startDate: new DateOnly(2026, 8, 1)), secondUser);
            await second.SaveChangesAsync();
        }
        await using (AppDbContext duplicate = Fixture.CreateContext(connectionString, firstUser))
        {
            AddOwned(duplicate, Goal(Guid.NewGuid(), startDate: new DateOnly(2026, 8, 2)), firstUser);
            await Assert.ThrowsAsync<DbUpdateException>(() => duplicate.SaveChangesAsync());
        }
        await using (AppDbContext history = Fixture.CreateContext(connectionString, firstUser))
        {
            BodyGoal active = await history.BodyGoals.SingleAsync();
            active.EndedAtUtc = new DateTime(2026, 8, 18, 12, 0, 0, DateTimeKind.Utc);
            await history.SaveChangesAsync();
            AddOwned(history, Goal(Guid.NewGuid(), startDate: new DateOnly(2026, 8, 19)), firstUser);
            await history.SaveChangesAsync();
            Assert.AreEqual(2, await history.BodyGoals.CountAsync());
            Assert.AreEqual(1, await history.BodyGoals.CountAsync(goal => goal.EndedAtUtc == null));
        }
    }

    [TestMethod]
    public async Task CheckInDateIsUniqueWithinAUserButIndependentAcrossUsers()
    {
        (string connectionString, Guid firstUser, Guid secondUser) = await CreateDatabaseAsync();
        DateOnly date = new(2026, 8, 18);
        await using (AppDbContext first = Fixture.CreateContext(connectionString, firstUser))
        {
            AddOwned(first, CheckIn(Guid.NewGuid(), date), firstUser);
            await first.SaveChangesAsync();
        }
        await using (AppDbContext second = Fixture.CreateContext(connectionString, secondUser))
        {
            AddOwned(second, CheckIn(Guid.NewGuid(), date), secondUser);
            await second.SaveChangesAsync();
        }
        await using (AppDbContext duplicate = Fixture.CreateContext(connectionString, firstUser))
        {
            AddOwned(duplicate, CheckIn(Guid.NewGuid(), date), firstUser);
            await Assert.ThrowsAsync<DbUpdateException>(() => duplicate.SaveChangesAsync());
        }
        await using (AppDbContext firstRead = Fixture.CreateContext(connectionString, firstUser))
        await using (AppDbContext secondRead = Fixture.CreateContext(connectionString, secondUser))
        {
            Assert.AreEqual(1, await firstRead.DailyCheckIns.CountAsync());
            Assert.AreEqual(1, await secondRead.DailyCheckIns.CountAsync());
        }
    }

    [TestMethod]
    public async Task DatabaseChecksRejectInvalidCanonicalValuesAndGoalDates()
    {
        (string connectionString, Guid firstUser, _) = await CreateDatabaseAsync();
        await using (AppDbContext invalidGoal = Fixture.CreateContext(connectionString, firstUser))
        {
            AddOwned(invalidGoal, Goal(
                Guid.NewGuid(),
                startDate: new DateOnly(2026, 8, 18),
                targetDate: new DateOnly(2026, 8, 17)), firstUser);
            await Assert.ThrowsAsync<DbUpdateException>(() => invalidGoal.SaveChangesAsync());
        }
        await using (AppDbContext invalidCheckIn = Fixture.CreateContext(connectionString, firstUser))
        {
            DailyCheckIn checkIn = CheckIn(
                Guid.NewGuid(),
                new DateOnly(2026, 8, 18),
                weightKg: -1,
                sleepMinutes: 1_441);
            AddOwned(invalidCheckIn, checkIn, firstUser);
            await Assert.ThrowsAsync<DbUpdateException>(() => invalidCheckIn.SaveChangesAsync());
        }
    }

    [TestMethod]
    public async Task ActivatingAReplacementPreservesTheOriginalGoalHistory()
    {
        (string connectionString, Guid firstUser, _) = await CreateDatabaseAsync();
        var time = new FixedTimeProvider(new DateTimeOffset(2026, 8, 18, 12, 0, 0, TimeSpan.Zero));
        Guid firstGoalId = Guid.NewGuid();
        await using (AppDbContext firstContext = Fixture.CreateContext(connectionString, firstUser))
        {
            var handler = new BodyGoalMutationHandler(firstContext, new TestUserContext(firstUser), time);
            await handler.ActivateAsync(Mutation(firstGoalId, BodyGoalKind.Bulk, 80, 85));
        }

        time.UtcNow = new DateTimeOffset(2026, 9, 1, 12, 0, 0, TimeSpan.Zero);
        Guid replacementId = Guid.NewGuid();
        await using (AppDbContext replacementContext = Fixture.CreateContext(connectionString, firstUser))
        {
            var handler = new BodyGoalMutationHandler(replacementContext, new TestUserContext(firstUser), time);
            BodyGoalSnapshot replacement = await handler.ActivateAsync(Mutation(
                replacementId,
                BodyGoalKind.Maintain,
                84,
                84,
                new ActiveBodyGoalExpectation(firstGoalId, 1)));
            Assert.AreEqual(1, replacement.Version);
        }

        await using AppDbContext read = Fixture.CreateContext(connectionString, firstUser);
        BodyGoal original = await read.BodyGoals.SingleAsync(goal => goal.Id == firstGoalId);
        BodyGoal active = await read.BodyGoals.SingleAsync(goal => goal.Id == replacementId);
        Assert.AreEqual(80, original.StartWeightKg);
        Assert.AreEqual(85, original.TargetWeightKg);
        Assert.AreEqual(2, original.Version);
        Assert.IsNotNull(original.EndedAtUtc);
        Assert.IsNull(active.EndedAtUtc);
    }

    [TestMethod]
    public async Task InvalidGoalIsRejectedBeforeAnyPersistenceChange()
    {
        (string connectionString, Guid firstUser, _) = await CreateDatabaseAsync();
        await using AppDbContext context = Fixture.CreateContext(connectionString, firstUser);
        var handler = new BodyGoalMutationHandler(
            context,
            new TestUserContext(firstUser),
            new FixedTimeProvider(DateTimeOffset.UtcNow));
        ActivateBodyGoalMutation invalid = ActivateBodyGoalMutation.Create(
            Metadata(),
            Guid.NewGuid(),
            (BodyGoalKind)999,
            startWeightKg: 0,
            targetWeightKg: -1,
            startDate: new DateOnly(2026, 8, 18),
            targetDate: new DateOnly(2026, 8, 17));

        BodyGoalValidationException exception = await Assert.ThrowsAsync<BodyGoalValidationException>(
            () => handler.ActivateAsync(invalid));
        CollectionAssert.AreEquivalent(
            ExpectedInvalidGoalFields,
            exception.Errors.Keys.ToArray());
        Assert.AreEqual(0, await context.BodyGoals.CountAsync());
    }

    [TestMethod]
    public async Task ConcurrentInitialActivationAllowsExactlyOneWinnerWithoutCrossUserBlocking()
    {
        (string connectionString, Guid firstUser, Guid secondUser) = await CreateDatabaseAsync();
        var time = new FixedTimeProvider(new DateTimeOffset(2026, 8, 18, 12, 0, 0, TimeSpan.Zero));
        async Task<bool> TryActivateAsync(Guid userId, Guid goalId)
        {
            await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
            var handler = new BodyGoalMutationHandler(context, new TestUserContext(userId), time);
            try
            {
                await handler.ActivateAsync(Mutation(goalId, BodyGoalKind.Cut, 85, 80));
                return true;
            }
            catch (BodyGoalConflictException)
            {
                return false;
            }
        }

        bool[] firstUserResults = await Task.WhenAll(
            TryActivateAsync(firstUser, Guid.NewGuid()),
            TryActivateAsync(firstUser, Guid.NewGuid()));
        Assert.AreEqual(1, firstUserResults.Count(result => result));
        Assert.IsTrue(await TryActivateAsync(secondUser, Guid.NewGuid()));

        await using AppDbContext firstRead = Fixture.CreateContext(connectionString, firstUser);
        await using AppDbContext secondRead = Fixture.CreateContext(connectionString, secondUser);
        Assert.AreEqual(1, await firstRead.BodyGoals.CountAsync(goal => goal.EndedAtUtc == null));
        Assert.AreEqual(1, await secondRead.BodyGoals.CountAsync(goal => goal.EndedAtUtc == null));
    }

    [TestMethod]
    public async Task CheckInStoresRestingValuesAndValidatesTheirRanges()
    {
        (string connectionString, Guid firstUser, _) = await CreateDatabaseAsync();
        var time = new FixedTimeProvider(new DateTimeOffset(2026, 8, 18, 8, 0, 0, TimeSpan.Zero));
        Guid checkInId = Guid.NewGuid();
        await using (AppDbContext context = Fixture.CreateContext(connectionString, firstUser))
        {
            var handler = new DailyCheckInMutationHandler(context, new TestUserContext(firstUser), time);
            DailyCheckInSnapshot created = await handler.CreateAsync(CreateCheckInMutation(
                checkInId, new DailyCheckInValues(82.5m, RestingHeartRateBpm: 25, RestingHrvMs: 300)));
            Assert.AreEqual(25, created.Values.RestingHeartRateBpm);
            Assert.AreEqual(300, created.Values.RestingHrvMs);
        }
        await using (AppDbContext context = Fixture.CreateContext(connectionString, firstUser))
        {
            DailyCheckIn stored = await context.DailyCheckIns.AsNoTracking().SingleAsync();
            Assert.AreEqual(25, stored.RestingHeartRateBpm);
            Assert.AreEqual(300, stored.RestingHrvMs);
        }
        foreach ((int? hr, int? hrv) in new (int?, int?)[] { (24, null), (151, null), (null, 0), (null, 301) })
        {
            await using AppDbContext context = Fixture.CreateContext(connectionString, firstUser);
            var handler = new DailyCheckInMutationHandler(context, new TestUserContext(firstUser), time);
            DailyCheckInValidationException exception = await Assert.ThrowsAsync<DailyCheckInValidationException>(
                () => handler.CorrectAsync(CorrectCheckInMutation(
                    checkInId, 1, new DailyCheckInValues(82.5m, RestingHeartRateBpm: hr, RestingHrvMs: hrv))));
            Assert.HasCount(1, exception.Errors);
        }
        await using (AppDbContext context = Fixture.CreateContext(connectionString, firstUser))
        {
            var handler = new DailyCheckInMutationHandler(context, new TestUserContext(firstUser), time);
            DailyCheckInSnapshot cleared = await handler.CorrectAsync(CorrectCheckInMutation(
                checkInId, 1, new DailyCheckInValues(82.5m)));
            Assert.IsNull(cleared.Values.RestingHeartRateBpm);
        }
    }

    [TestMethod]
    public async Task CheckInCreationAndCorrectionAreValidatedAndAtomic()
    {
        (string connectionString, Guid firstUser, _) = await CreateDatabaseAsync();
        var time = new FixedTimeProvider(new DateTimeOffset(2026, 8, 18, 8, 0, 0, TimeSpan.Zero));
        Guid checkInId = Guid.NewGuid();
        await using (AppDbContext createContext = Fixture.CreateContext(connectionString, firstUser))
        {
            var handler = new DailyCheckInMutationHandler(createContext, new TestUserContext(firstUser), time);
            DailyCheckInSnapshot created = await handler.CreateAsync(CreateCheckInMutation(
                checkInId,
                new DailyCheckInValues(82.5m, 2_500, 180, 300, 70, 8_000, 480)));
            Assert.AreEqual(1, created.Version);
            Assert.AreEqual(created.CreatedAtUtc, created.UpdatedAtUtc);
        }

        await using (AppDbContext invalidContext = Fixture.CreateContext(connectionString, firstUser))
        {
            var handler = new DailyCheckInMutationHandler(invalidContext, new TestUserContext(firstUser), time);
            var invalid = new DailyCheckInValues(0, -1, -1, -1, -1, -1, 1_441);
            DailyCheckInValidationException exception = await Assert.ThrowsAsync<DailyCheckInValidationException>(
                () => handler.CorrectAsync(CorrectCheckInMutation(checkInId, 1, invalid)));
            Assert.HasCount(7, exception.Errors);
        }

        time.UtcNow = new DateTimeOffset(2026, 8, 18, 9, 0, 0, TimeSpan.Zero);
        await using (AppDbContext correctionContext = Fixture.CreateContext(connectionString, firstUser))
        {
            var handler = new DailyCheckInMutationHandler(correctionContext, new TestUserContext(firstUser), time);
            DailyCheckInSnapshot corrected = await handler.CorrectAsync(CorrectCheckInMutation(
                checkInId,
                1,
                new DailyCheckInValues(82.2m, null, 185, null, 65, 9_000, 510)));
            Assert.AreEqual(2, corrected.Version);
            Assert.AreEqual(new DateTime(2026, 8, 18, 8, 0, 0, DateTimeKind.Utc), corrected.CreatedAtUtc);
            Assert.AreEqual(new DateTime(2026, 8, 18, 9, 0, 0, DateTimeKind.Utc), corrected.UpdatedAtUtc);
            Assert.AreEqual(82.2m, corrected.Values.WeightKg);
            Assert.IsNull(corrected.Values.CaloriesKcal);
        }
    }

    [TestMethod]
    public async Task DuplicateIdsAndConcurrentSameDayCreatesDoNotOverwriteExistingData()
    {
        (string connectionString, Guid firstUser, _) = await CreateDatabaseAsync();
        var time = new FixedTimeProvider(new DateTimeOffset(2026, 8, 18, 8, 0, 0, TimeSpan.Zero));
        Guid stableId = Guid.NewGuid();
        await using (AppDbContext initialContext = Fixture.CreateContext(connectionString, firstUser))
        {
            var handler = new DailyCheckInMutationHandler(initialContext, new TestUserContext(firstUser), time);
            await handler.CreateAsync(CreateCheckInMutation(stableId, new DailyCheckInValues(82.5m)));
        }
        await using (AppDbContext duplicateIdContext = Fixture.CreateContext(connectionString, firstUser))
        {
            var handler = new DailyCheckInMutationHandler(duplicateIdContext, new TestUserContext(firstUser), time);
            await Assert.ThrowsAsync<DailyCheckInConflictException>(() => handler.CreateAsync(
                CreateCheckInMutation(stableId, new DailyCheckInValues(99), new DateOnly(2026, 8, 19))));
        }

        DateOnly concurrentDate = new(2026, 8, 20);
        async Task<bool> TryCreateAsync(Guid id)
        {
            await using AppDbContext context = Fixture.CreateContext(connectionString, firstUser);
            var handler = new DailyCheckInMutationHandler(context, new TestUserContext(firstUser), time);
            try
            {
                await handler.CreateAsync(CreateCheckInMutation(id, new DailyCheckInValues(83), concurrentDate));
                return true;
            }
            catch (DailyCheckInConflictException)
            {
                return false;
            }
        }
        bool[] results = await Task.WhenAll(TryCreateAsync(Guid.NewGuid()), TryCreateAsync(Guid.NewGuid()));
        Assert.AreEqual(1, results.Count(result => result));

        await using AppDbContext read = Fixture.CreateContext(connectionString, firstUser);
        Assert.AreEqual(82.5m, (await read.DailyCheckIns.SingleAsync(item => item.Id == stableId)).WeightKg);
        Assert.AreEqual(1, await read.DailyCheckIns.CountAsync(item => item.LocalDate == concurrentDate));
    }

    [TestMethod]
    public async Task ForeignCheckInCorrectionIsIndistinguishableFromMissingAndLeavesOwnerDataUntouched()
    {
        (string connectionString, Guid firstUser, Guid secondUser) = await CreateDatabaseAsync();
        var time = new FixedTimeProvider(new DateTimeOffset(2026, 8, 18, 8, 0, 0, TimeSpan.Zero));
        Guid checkInId = Guid.NewGuid();
        await using (AppDbContext ownerContext = Fixture.CreateContext(connectionString, firstUser))
        {
            var handler = new DailyCheckInMutationHandler(ownerContext, new TestUserContext(firstUser), time);
            await handler.CreateAsync(CreateCheckInMutation(checkInId, new DailyCheckInValues(82.5m)));
        }
        await using (AppDbContext foreignContext = Fixture.CreateContext(connectionString, secondUser))
        {
            var handler = new DailyCheckInMutationHandler(foreignContext, new TestUserContext(secondUser), time);
            await Assert.ThrowsAsync<DailyCheckInNotFoundException>(() => handler.CorrectAsync(
                CorrectCheckInMutation(checkInId, 1, new DailyCheckInValues(99))));
            await Assert.ThrowsAsync<DailyCheckInNotFoundException>(() => handler.CorrectAsync(
                CorrectCheckInMutation(Guid.NewGuid(), 1, new DailyCheckInValues(99))));
        }
        await using AppDbContext read = Fixture.CreateContext(connectionString, firstUser);
        DailyCheckIn stored = await read.DailyCheckIns.SingleAsync();
        Assert.AreEqual(82.5m, stored.WeightKg);
        Assert.AreEqual(1, stored.Version);
    }

    [TestMethod]
    public async Task ProjectionsAreChronologicalUserScopedAndEveryAcceptedMutationCapturesAFullSnapshot()
    {
        (string connectionString, Guid firstUser, Guid secondUser) = await CreateDatabaseAsync();
        var time = new FixedTimeProvider(new DateTimeOffset(2026, 8, 18, 8, 0, 0, TimeSpan.Zero));
        Guid firstGoalId = Guid.NewGuid();
        var firstGoalChanges = new ChangeCollector();
        await using (AppDbContext context = Fixture.CreateContext(connectionString, firstUser))
        {
            var handler = new BodyGoalMutationHandler(
                context,
                new TestUserContext(firstUser),
                time,
                firstGoalChanges);
            await handler.ActivateAsync(Mutation(firstGoalId, BodyGoalKind.Bulk, 80, 85));
        }
        Assert.HasCount(1, firstGoalChanges.Changes);
        BodyGoalSnapshot firstGoalSnapshot = (BodyGoalSnapshot)((UpsertedResourceChange)firstGoalChanges.Changes[0]).Snapshot;
        Assert.AreEqual(85, firstGoalSnapshot.TargetWeightKg);

        var replacementChanges = new ChangeCollector();
        Guid activeGoalId = Guid.NewGuid();
        await using (AppDbContext context = Fixture.CreateContext(connectionString, firstUser))
        {
            var handler = new BodyGoalMutationHandler(
                context,
                new TestUserContext(firstUser),
                time,
                replacementChanges);
            await handler.ActivateAsync(Mutation(
                activeGoalId,
                BodyGoalKind.Maintain,
                84,
                84,
                new ActiveBodyGoalExpectation(firstGoalId, 1)));
        }
        Assert.HasCount(2, replacementChanges.Changes);
        Assert.IsNotNull(replacementChanges.Changes
            .OfType<UpsertedResourceChange>()
            .Select(change => (BodyGoalSnapshot)change.Snapshot)
            .Single(snapshot => snapshot.GoalId == firstGoalId)
            .EndedAtUtc);

        Guid laterCheckInId = Guid.NewGuid();
        var createChanges = new ChangeCollector();
        await using (AppDbContext context = Fixture.CreateContext(connectionString, firstUser))
        {
            var handler = new DailyCheckInMutationHandler(
                context,
                new TestUserContext(firstUser),
                time,
                createChanges);
            await handler.CreateAsync(CreateCheckInMutation(
                laterCheckInId,
                new DailyCheckInValues(82.5m, 2_500, 180),
                new DateOnly(2026, 8, 18)));
        }
        DailyCheckInSnapshot createdSnapshot = (DailyCheckInSnapshot)((UpsertedResourceChange)createChanges.Changes.Single()).Snapshot;
        Assert.AreEqual(2_500, createdSnapshot.Values.CaloriesKcal);

        var correctionChanges = new ChangeCollector();
        await using (AppDbContext context = Fixture.CreateContext(connectionString, firstUser))
        {
            var handler = new DailyCheckInMutationHandler(
                context,
                new TestUserContext(firstUser),
                time,
                correctionChanges);
            await handler.CorrectAsync(CorrectCheckInMutation(
                laterCheckInId,
                1,
                new DailyCheckInValues(82.2m, null, 185)));
        }
        DailyCheckInSnapshot correctedSnapshot = (DailyCheckInSnapshot)((UpsertedResourceChange)correctionChanges.Changes.Single()).Snapshot;
        Assert.AreEqual(2, correctedSnapshot.Version);
        Assert.IsNull(correctedSnapshot.Values.CaloriesKcal);

        await using (AppDbContext context = Fixture.CreateContext(connectionString, firstUser))
        {
            var handler = new DailyCheckInMutationHandler(context, new TestUserContext(firstUser), time);
            await handler.CreateAsync(CreateCheckInMutation(
                Guid.NewGuid(),
                new DailyCheckInValues(83),
                new DateOnly(2026, 8, 17)));
        }
        await using (AppDbContext context = Fixture.CreateContext(connectionString, secondUser))
        {
            var goalHandler = new BodyGoalMutationHandler(context, new TestUserContext(secondUser), time);
            await goalHandler.ActivateAsync(Mutation(Guid.NewGuid(), BodyGoalKind.Cut, 90, 85));
            var checkInHandler = new DailyCheckInMutationHandler(context, new TestUserContext(secondUser), time);
            await checkInHandler.CreateAsync(CreateCheckInMutation(
                Guid.NewGuid(),
                new DailyCheckInValues(99),
                new DateOnly(2026, 8, 16)));
        }

        await using AppDbContext queryContext = Fixture.CreateContext(connectionString, firstUser);
        var queries = new BodyTrackingQueries(queryContext);
        Assert.AreEqual(activeGoalId, (await queries.GetActiveGoalAsync())?.GoalId);
        Assert.AreEqual(firstGoalId, (await queries.GetGoalHistoryAsync()).Single().GoalId);
        IReadOnlyList<DailyCheckInSnapshot> checkIns = await queries.GetCheckInsAsync(0, 100);
        CollectionAssert.AreEqual(
            new[] { new DateOnly(2026, 8, 17), new DateOnly(2026, 8, 18) },
            checkIns.Select(item => item.LocalDate).ToArray());
        Assert.IsFalse(checkIns.Any(item => item.Values.WeightKg == 99));
    }

    private static async Task<(string ConnectionString, Guid FirstUser, Guid SecondUser)> CreateDatabaseAsync()
    {
        string connectionString = await Fixture.CreateIsolatedDatabaseAsync();
        Guid firstUser = Guid.NewGuid();
        Guid secondUser = Guid.NewGuid();
        await using AppDbContext context = Fixture.CreateContext(connectionString);
        await context.Database.MigrateAsync();
        context.Users.AddRange(User(firstUser, "first-body@example.test"), User(secondUser, "second-body@example.test"));
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

    private static BodyGoal Goal(Guid id, DateOnly startDate, DateOnly? targetDate = null) => new()
    {
        Id = id,
        Kind = BodyGoalKind.Bulk,
        StartWeightKg = 80,
        TargetWeightKg = 85,
        StartDate = startDate,
        TargetDate = targetDate,
        CreatedAtUtc = new DateTime(2026, 8, 18, 12, 0, 0, DateTimeKind.Utc),
        Version = 1,
    };

    private static DailyCheckIn CheckIn(
        Guid id,
        DateOnly localDate,
        decimal weightKg = 82.5m,
        int? sleepMinutes = 480) => new()
        {
            Id = id,
            LocalDate = localDate,
            WeightKg = weightKg,
            CaloriesKcal = 2_500,
            ProteinGrams = 180,
            CarbohydrateGrams = 300,
            FatGrams = 70,
            Steps = 8_000,
            SleepMinutes = sleepMinutes,
            CreatedAtUtc = new DateTime(2026, 8, 18, 12, 0, 0, DateTimeKind.Utc),
            UpdatedAtUtc = new DateTime(2026, 8, 18, 12, 0, 0, DateTimeKind.Utc),
            Version = 1,
        };

    private static void AddOwned<TEntity>(AppDbContext context, TEntity entity, Guid userId)
        where TEntity : UserOwnedEntity
    {
        context.Add(entity);
        context.Entry(entity).Property(item => item.UserId).CurrentValue = userId;
    }

    private static ActivateBodyGoalMutation Mutation(
        Guid goalId,
        BodyGoalKind kind,
        decimal startWeightKg,
        decimal targetWeightKg,
        ActiveBodyGoalExpectation? expectation = null) => ActivateBodyGoalMutation.Create(
            Metadata(),
            goalId,
            kind,
            startWeightKg,
            targetWeightKg,
            new DateOnly(2026, 8, 18),
            new DateOnly(2026, 12, 31),
            expectation);

    private static MutationMetadata Metadata() => MutationMetadata.Create(Guid.NewGuid(), Guid.NewGuid(), 1);

    private static CreateDailyCheckInMutation CreateCheckInMutation(
        Guid checkInId,
        DailyCheckInValues values,
        DateOnly? localDate = null) => CreateDailyCheckInMutation.Create(
            Metadata(),
            checkInId,
            localDate ?? new DateOnly(2026, 8, 18),
            values);

    private static CorrectDailyCheckInMutation CorrectCheckInMutation(
        Guid checkInId,
        long baseVersion,
        DailyCheckInValues values) => CorrectDailyCheckInMutation.Create(
            Metadata(),
            checkInId,
            baseVersion,
            values);

    private sealed record TestUserContext(Guid? UserId) : IUserContext;

    private sealed class FixedTimeProvider(DateTimeOffset utcNow) : TimeProvider
    {
        public DateTimeOffset UtcNow { get; set; } = utcNow;

        public override DateTimeOffset GetUtcNow() => UtcNow;
    }
}
