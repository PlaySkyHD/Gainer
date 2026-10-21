using Gainer.Core.Integrations;
using Gainer.Core.Security;
using Gainer.Core.Training;
using Gainer.Infrastructure.Integrations;
using Gainer.Infrastructure.Persistence;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;

namespace Gainer.IntegrationTests;

[TestClass]
[DoNotParallelize]
public sealed class StravaExportTests
{
    private const long Athlete = 4242;
    private static readonly DateTime Connected = DateTime.UtcNow.AddDays(-10);
    private static PostgreSqlTestFixture? fixture;
    private static PostgreSqlTestFixture Fixture => fixture ?? throw new InvalidOperationException("PostgreSQL is not started.");

    private readonly FakeStrava strava = new();
    private readonly MutableTime time = new(DateTime.UtcNow.AddHours(1));
    private readonly IDataProtectionProvider dataProtection = new EphemeralDataProtectionProvider();
    private readonly MemoryCache usedStates = new(new MemoryCacheOptions());

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

    [TestCleanup]
    public void DisposeCache() => usedStates.Dispose();

    [TestMethod]
    public async Task CardioIsUploadedOnceAndCompletedAfterProcessing()
    {
        (string db, Guid user, Guid _) = await CreateDatabaseAsync();
        await ConnectAsync(db, user);
        Guid sessionId = await AddCardioAsync(db, user, Connected.AddDays(1));
        strava.Upload = _ => new StravaUploadState(77, null, null, null);

        await RunAsync(db, user);

        Assert.HasCount(1, strava.Uploads);
        Assert.AreEqual($"gainer-cardio-{sessionId:N}", strava.Uploads[0].ExternalId);
        StravaExport processing = await SingleExportAsync(db, user);
        Assert.AreEqual(StravaExportStatus.Processing, processing.Status);
        Assert.AreEqual(77, processing.UploadId);

        strava.Poll = id => new StravaUploadState(id, 9001, null, null);
        time.Advance(TimeSpan.FromSeconds(10));
        await RunAsync(db, user);
        StravaExport completed = await SingleExportAsync(db, user);
        Assert.AreEqual(StravaExportStatus.Completed, completed.Status);
        Assert.AreEqual(9001, completed.ActivityId);

        time.Advance(TimeSpan.FromMinutes(10));
        await RunAsync(db, user);
        Assert.HasCount(1, strava.Uploads, "A completed record is never sent again.");
        Assert.IsEmpty(strava.SportTypes, "Cardio keeps the type from the file.");
    }

    [TestMethod]
    public async Task RecentlyChangedRecordsWaitUntilSettled()
    {
        (string db, Guid user, Guid _) = await CreateDatabaseAsync();
        await ConnectAsync(db, user);
        await AddCardioAsync(db, user, time.Now.AddSeconds(-30));
        strava.Upload = _ => new StravaUploadState(1, 2, null, null);

        await RunAsync(db, user);
        Assert.IsEmpty(strava.Uploads);

        time.Advance(TimeSpan.FromMinutes(3));
        await RunAsync(db, user);
        Assert.HasCount(1, strava.Uploads);
    }

    [TestMethod]
    public async Task DuplicateUploadCountsAsCompleted()
    {
        (string db, Guid user, Guid _) = await CreateDatabaseAsync();
        await ConnectAsync(db, user);
        await AddCardioAsync(db, user, Connected.AddDays(1));
        strava.Upload = _ => new StravaUploadState(5, null, "x.tcx duplicate of activity 42", 42);

        await RunAsync(db, user);

        StravaExport export = await SingleExportAsync(db, user);
        Assert.AreEqual(StravaExportStatus.Completed, export.Status);
        Assert.AreEqual(42, export.ActivityId);
    }

    [TestMethod]
    public async Task UnavailableStravaIsRetriedWithBackoffAndThenFails()
    {
        (string db, Guid user, Guid _) = await CreateDatabaseAsync();
        await ConnectAsync(db, user);
        await AddCardioAsync(db, user, Connected.AddDays(1));
        strava.Upload = _ => throw new StravaApiException(StravaFailure.Transient, "503", 503);

        await RunAsync(db, user);

        StravaExport export = await SingleExportAsync(db, user);
        Assert.AreEqual(StravaExportStatus.Pending, export.Status);
        Assert.AreEqual(1, export.Attempts);
        Assert.AreEqual("strava_unavailable", export.LastErrorCode);
        Assert.IsGreaterThan(time.Now, export.NextAttemptAtUtc);

        for (int attempt = 2; attempt <= StravaExportProcessor.MaximumAttempts; attempt++)
        {
            time.Advance(TimeSpan.FromHours(2));
            await RunAsync(db, user);
        }
        Assert.AreEqual(StravaExportStatus.Failed, (await SingleExportAsync(db, user)).Status);
        Assert.HasCount(StravaExportProcessor.MaximumAttempts, strava.Uploads);
    }

    [TestMethod]
    public async Task RejectedRefreshMarksTheConnectionForReconnect()
    {
        (string db, Guid user, Guid _) = await CreateDatabaseAsync();
        await ConnectAsync(db, user, expiresAtUtc: time.Now.AddMinutes(-1));
        await AddCardioAsync(db, user, Connected.AddDays(1));
        strava.Refresh = _ => throw new StravaApiException(StravaFailure.Unauthorized, "400", 400);

        await RunAsync(db, user);

        await using AppDbContext context = Fixture.CreateContext(db, user);
        Assert.IsTrue((await context.StravaConnections.SingleAsync()).NeedsReconnect);
        Assert.IsEmpty(strava.Uploads);
        Assert.IsTrue((await Service(context, user).GetStatusAsync()).NeedsReconnect);
        StravaIntegrationException blocked = await Assert.ThrowsExactlyAsync<StravaIntegrationException>(() =>
            Service(context, user).RequestExportAsync(StravaExportKind.Cardio, Guid.NewGuid()));
        Assert.AreEqual(StravaIntegrationException.NeedsReconnect, blocked.Code);
    }

    [TestMethod]
    public async Task RefreshedTokensAreStoredEncrypted()
    {
        (string db, Guid user, Guid _) = await CreateDatabaseAsync();
        await ConnectAsync(db, user, expiresAtUtc: time.Now.AddMinutes(1));
        await AddCardioAsync(db, user, Connected.AddDays(1));
        strava.Refresh = _ => new StravaTokens("new-access", "new-refresh", time.Now.AddHours(6), null, null);
        strava.Upload = _ => new StravaUploadState(1, 2, null, null);

        await RunAsync(db, user);

        Assert.AreEqual("new-access", strava.Uploads.Single().AccessToken);
        await using AppDbContext context = Fixture.CreateContext(db, user);
        StravaConnection connection = await context.StravaConnections.SingleAsync();
        Assert.DoesNotContain("new-access", connection.ProtectedAccessToken);
        Assert.DoesNotContain("new-refresh", connection.ProtectedRefreshToken);
        Assert.IsLessThan(1, Math.Abs((time.Now.AddHours(6) - connection.AccessTokenExpiresAtUtc).TotalSeconds));
    }

    [TestMethod]
    public async Task OnlySwitchedOnKindsAfterSwitchingOnAreExported()
    {
        (string db, Guid user, Guid _) = await CreateDatabaseAsync();
        await ConnectAsync(db, user);
        await AddCardioAsync(db, user, Connected.AddDays(-1));
        await AddWorkoutAsync(db, user, Connected.AddDays(1));
        strava.Upload = _ => new StravaUploadState(1, 100 + strava.Uploads.Count, null, null);

        await RunAsync(db, user);
        Assert.IsEmpty(strava.Uploads, "Cardio before connecting and strength while off stay local.");

        await using (AppDbContext context = Fixture.CreateContext(db, user))
        {
            StravaStatus status = await Service(context, user).UpdateSettingsAsync(exportCardio: true, exportStrength: true);
            Assert.IsTrue(status.ExportStrength);
            Assert.IsTrue(status.ExportCardio);
        }
        Guid newWorkout = await AddWorkoutAsync(db, user, time.Now.AddMinutes(1));
        time.Advance(TimeSpan.FromMinutes(10));
        await RunAsync(db, user);

        Assert.HasCount(1, strava.Uploads);
        Assert.AreEqual($"gainer-strength-{newWorkout:N}", strava.Uploads[0].ExternalId);
        Assert.AreEqual("Bankdrücken: 3 × 8 · 80 kg", strava.Uploads[0].Description);
        Assert.AreEqual((101L, "WeightTraining"), strava.SportTypes.Single());
    }

    [TestMethod]
    public async Task ManualExportSendsOlderRecordsButNotForeignOnes()
    {
        (string db, Guid first, Guid second) = await CreateDatabaseAsync();
        await ConnectAsync(db, first);
        Guid older = await AddCardioAsync(db, first, Connected.AddDays(-3));
        Guid foreign = await AddCardioAsync(db, second, Connected.AddDays(1));
        strava.Upload = _ => new StravaUploadState(1, 55, null, null);

        await using (AppDbContext context = Fixture.CreateContext(db, first))
        {
            IStravaIntegrationService service = Service(context, first);
            StravaIntegrationException foreignRequest = await Assert.ThrowsExactlyAsync<StravaIntegrationException>(() =>
                service.RequestExportAsync(StravaExportKind.Cardio, foreign));
            Assert.AreEqual(StravaIntegrationException.ResourceNotFound, foreignRequest.Code);
            Assert.IsNull(await service.GetExportAsync(StravaExportKind.Cardio, foreign));

            StravaExportState queued = await service.RequestExportAsync(StravaExportKind.Cardio, older);
            Assert.AreEqual(StravaExportStatus.Pending, queued.Status);
        }
        await RunAsync(db, first);
        await RunAsync(db, second);

        Assert.AreEqual($"gainer-cardio-{older:N}", strava.Uploads.Single().ExternalId);
        await using (AppDbContext context = Fixture.CreateContext(db, first))
        {
            StravaExportState? state = await Service(context, first).GetExportAsync(StravaExportKind.Cardio, older);
            Assert.AreEqual(StravaExportStatus.Completed, state?.Status);
            Assert.AreEqual(55, state?.ActivityId);
        }
        await using (AppDbContext context = Fixture.CreateContext(db, second))
        {
            Assert.AreEqual(0, await context.StravaExports.CountAsync());
            Assert.IsFalse((await Service(context, second).GetStatusAsync()).Connected);
        }
    }

    [TestMethod]
    public async Task CallbackStoresTheConnectionOfTheStateOwnerOnlyOnce()
    {
        (string db, Guid first, Guid second) = await CreateDatabaseAsync();
        string url;
        await using (AppDbContext context = Fixture.CreateContext(db, first))
        {
            url = Service(context, first).BeginAuthorization("https://gainer.example/cb");
        }
        Assert.StartsWith("https://www.strava.com/oauth/mobile/authorize?", url);
        Assert.Contains("scope=read%2Cactivity%3Awrite", url);
        string state = StateOf(url);
        strava.Exchange = _ => new StravaTokens("access", "refresh", time.Now.AddHours(6), Athlete, "Nic M");

        Assert.AreEqual(StravaAuthorizationResult.Failed, await CallbackAsync(db, state + "x", "read,activity:write"));
        Assert.AreEqual(StravaAuthorizationResult.Denied, await CallbackAsync(db, state, "read"));
        Assert.AreEqual(
            StravaAuthorizationResult.Failed,
            await CallbackAsync(db, state, "read,activity:write"),
            "A state is accepted only once.");

        string fresh;
        await using (AppDbContext context = Fixture.CreateContext(db, first))
        {
            fresh = StateOf(Service(context, first).BeginAuthorization("https://gainer.example/cb"));
        }
        Assert.AreEqual(StravaAuthorizationResult.Connected, await CallbackAsync(db, fresh, "read,activity:write"));

        await using (AppDbContext context = Fixture.CreateContext(db, first))
        {
            StravaStatus status = await Service(context, first).GetStatusAsync();
            Assert.IsTrue(status.Connected);
            Assert.AreEqual("Nic M", status.AthleteName);
            Assert.IsTrue(status.ExportCardio);
            Assert.IsFalse(status.ExportStrength);
        }
        await using (AppDbContext context = Fixture.CreateContext(db, second))
        {
            Assert.IsFalse((await Service(context, second).GetStatusAsync()).Connected);
        }
    }

    [TestMethod]
    public async Task DisconnectRevokesAndDeletesTokens()
    {
        (string db, Guid user, Guid _) = await CreateDatabaseAsync();
        await ConnectAsync(db, user);

        await using (AppDbContext context = Fixture.CreateContext(db, user))
        {
            await Service(context, user).DisconnectAsync();
        }

        Assert.AreEqual("access", strava.Deauthorized.Single());
        await using AppDbContext check = Fixture.CreateContext(db, user);
        Assert.AreEqual(0, await check.StravaConnections.CountAsync());
    }

    private static string StateOf(string url) =>
        Uri.UnescapeDataString(url.Split("state=")[1].Split('&')[0]);

    private async Task<StravaAuthorizationResult> CallbackAsync(string db, string state, string scope)
    {
        // Like the anonymous callback: the context only knows the user the service binds from the state.
        var scopeUser = new BackgroundUserScope();
        var userContext = new ScopedUserContext(scopeUser);
        await using AppDbContext context = Fixture.CreateContext(db, userContext);
        return await Service(context, userContext, scopeUser)
            .CompleteAuthorizationAsync(state, "code", scope, null, "https://gainer.example/cb");
    }

    private async Task RunAsync(string db, Guid user)
    {
        await using AppDbContext context = Fixture.CreateContext(db, user);
        await new StravaExportProcessor(
                context,
                strava,
                Vault(),
                Settings(),
                time,
                NullLogger<StravaExportProcessor>.Instance)
            .RunAsync();
    }

    private StravaIntegrationService Service(AppDbContext context, Guid user) =>
        Service(context, new FixedUser(user), new BackgroundUserScope());

    private StravaIntegrationService Service(AppDbContext context, IUserContext user, BackgroundUserScope scope) => new(
        context,
        user,
        scope,
        strava,
        Vault(),
        new StravaExportSignal(),
        dataProtection,
        usedStates,
        Settings(),
        time,
        NullLogger<StravaIntegrationService>.Instance);

    private StravaTokenVault Vault() => new(dataProtection, strava, time);

    private static IOptions<StravaOptions> Settings() => Options.Create(new StravaOptions
    {
        ClientId = "123",
        ClientSecret = "secret",
        SettleSeconds = 120,
    });

    private async Task ConnectAsync(string db, Guid user, DateTime? expiresAtUtc = null)
    {
        await using AppDbContext context = Fixture.CreateContext(db, user);
        var connection = new StravaConnection
        {
            AthleteId = Athlete,
            AthleteName = "Test",
            Scope = "read,activity:write",
            CardioExportSinceUtc = Connected,
            ConnectedAtUtc = Connected,
            UpdatedAtUtc = Connected,
        };
        Vault().Store(connection, new StravaTokens("access", "refresh", expiresAtUtc ?? time.Now.AddDays(30), Athlete, null));
        context.StravaConnections.Add(connection);
        await context.SaveChangesAsync();
    }

    private static async Task<Guid> AddCardioAsync(string db, Guid user, DateTime endedAtUtc)
    {
        await using AppDbContext context = Fixture.CreateContext(db, user);
        var session = new CardioSession
        {
            Id = Guid.NewGuid(),
            StartedAtUtc = endedAtUtc.AddMinutes(-30),
            EndedAtUtc = endedAtUtc,
            SampleIntervalSeconds = 5,
            HeartRateBpm = [120, 130],
            CreatedAtUtc = endedAtUtc,
            UpdatedAtUtc = endedAtUtc,
            Version = 1,
        };
        context.CardioSessions.Add(session);
        await context.SaveChangesAsync();
        return session.Id;
    }

    private static async Task<Guid> AddWorkoutAsync(string db, Guid user, DateTime endedAtUtc)
    {
        await using AppDbContext context = Fixture.CreateContext(db, user);
        var exercise = new Exercise
        {
            Id = Guid.NewGuid(),
            OwnerUserId = user,
            Name = "Bankdrücken " + Guid.NewGuid().ToString("N")[..6],
            ExerciseType = ExerciseType.Strength,
            CreatedAtUtc = endedAtUtc,
            UpdatedAtUtc = endedAtUtc,
            Version = 1,
        };
        var workout = new Workout
        {
            Id = Guid.NewGuid(),
            Title = "Push",
            StartedAtUtc = endedAtUtc.AddHours(-1),
            EndedAtUtc = endedAtUtc,
            CreatedAtUtc = endedAtUtc,
            UpdatedAtUtc = endedAtUtc,
            Version = 1,
        };
        var workoutExercise = new WorkoutExercise
        {
            Id = Guid.NewGuid(),
            WorkoutId = workout.Id,
            SourceExerciseId = exercise.Id,
            ExerciseNameSnapshot = "Bankdrücken",
            ExerciseTypeSnapshot = ExerciseType.Strength,
        };
        context.Exercises.Add(exercise);
        context.Workouts.Add(workout);
        context.WorkoutExercises.Add(workoutExercise);
        for (int position = 0; position < 3; position++)
        {
            context.WorkoutSets.Add(new WorkoutSet
            {
                Id = Guid.NewGuid(),
                WorkoutId = workout.Id,
                WorkoutExerciseId = workoutExercise.Id,
                Position = position,
                WeightKg = 80m,
                Repetitions = 8,
            });
        }
        await context.SaveChangesAsync();
        return workout.Id;
    }

    private static async Task<StravaExport> SingleExportAsync(string db, Guid user)
    {
        await using AppDbContext context = Fixture.CreateContext(db, user);
        return await context.StravaExports.AsNoTracking().SingleAsync();
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

    private sealed record FixedUser(Guid Value) : IUserContext
    {
        Guid? IUserContext.UserId => Value;
    }

    private sealed class ScopedUserContext(BackgroundUserScope scope) : IUserContext
    {
        public Guid? UserId => scope.UserId;
    }

    private sealed class MutableTime(DateTime start) : TimeProvider
    {
        public DateTime Now { get; private set; } = start;

        public void Advance(TimeSpan by) => Now += by;

        public override DateTimeOffset GetUtcNow() => new(Now, TimeSpan.Zero);
    }

    private sealed record RecordedUpload(string AccessToken, string ExternalId, string? Description);

    private sealed class FakeStrava : IStravaApiClient
    {
        public Func<string, StravaTokens> Exchange { get; set; } = _ => throw new InvalidOperationException("Unexpected exchange.");
        public Func<string, StravaTokens> Refresh { get; set; } = _ => throw new InvalidOperationException("Unexpected refresh.");
        public Func<StravaUpload, StravaUploadState> Upload { get; set; } = _ => throw new InvalidOperationException("Unexpected upload.");
        public Func<long, StravaUploadState> Poll { get; set; } = id => new StravaUploadState(id, null, null, null);
        public List<RecordedUpload> Uploads { get; } = [];
        public List<(long ActivityId, string SportType)> SportTypes { get; } = [];
        public List<string> Deauthorized { get; } = [];

        public Task<StravaTokens> ExchangeCodeAsync(string code, CancellationToken cancellationToken = default) =>
            Task.FromResult(Exchange(code));

        public Task<StravaTokens> RefreshAsync(string refreshToken, CancellationToken cancellationToken = default) =>
            Task.FromResult(Refresh(refreshToken));

        public Task DeauthorizeAsync(string accessToken, CancellationToken cancellationToken = default)
        {
            Deauthorized.Add(accessToken);
            return Task.CompletedTask;
        }

        public Task<StravaUploadState> UploadAsync(string accessToken, StravaUpload upload, CancellationToken cancellationToken = default)
        {
            Uploads.Add(new RecordedUpload(accessToken, upload.ExternalId, upload.Description));
            return Task.FromResult(Upload(upload));
        }

        public Task<StravaUploadState> GetUploadAsync(string accessToken, long uploadId, CancellationToken cancellationToken = default) =>
            Task.FromResult(Poll(uploadId));

        public Task SetSportTypeAsync(string accessToken, long activityId, string sportType, CancellationToken cancellationToken = default)
        {
            SportTypes.Add((activityId, sportType));
            return Task.CompletedTask;
        }
    }
}
