using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Gainer.Api.Composition;
using Gainer.Api.Security;
using Gainer.Contracts.Security;
using Gainer.Contracts.Sync;
using Gainer.Infrastructure.Persistence;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.TestHost;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Logging;

namespace Gainer.IntegrationTests;

[TestClass]
[DoNotParallelize]
public sealed class SyncHandoverApiTests
{
    private const string TestOrigin = "https://handover.gainer.test";
    private const string UserAEmail = "handover-a@example.test";
    private const string UserBEmail = "handover-b@example.test";
    private const string Password = "Handover-test-password-42!";
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private static PostgreSqlTestFixture? fixture;
    private readonly List<string> keyRingPaths = [];

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
        if (fixture is not null) await fixture.DisposeAsync();
    }

    [TestCleanup]
    public void DeleteKeyRings()
    {
        foreach (string path in keyRingPaths)
            if (Directory.Exists(path)) Directory.Delete(path, recursive: true);
        keyRingPaths.Clear();
    }

    [TestMethod]
    public async Task HandoverIsIdempotentAndSupportsRepeatedVerifiedSwitches()
    {
        await using WebApplication app = await CreateApplicationAsync();
        await CreateUserAsync(app, UserAEmail);
        using HttpClient client = app.GetTestClient();
        client.BaseAddress = new Uri(TestOrigin);
        CookieJar cookies = await LoginAsync(client, UserAEmail);

        Guid source = Guid.NewGuid();
        Guid target = Guid.NewGuid();
        await RegisterAsync(client, cookies, source, "iPhone", takeOverWriting: false, HttpStatusCode.OK);
        await RegisterAsync(client, cookies, target, "PWA", takeOverWriting: false, HttpStatusCode.OK);

        BeginSyncHandoverRequest firstRequest = new(Guid.NewGuid(), source, 0);
        BeginSyncHandoverResponse first = await BeginAsync(client, cookies, firstRequest);
        BeginSyncHandoverResponse concurrentRetry = await BeginAsync(client, cookies, firstRequest);
        Assert.AreEqual(first.HandoverId, concurrentRetry.HandoverId);
        Assert.AreEqual(first.OneTimeCode, concurrentRetry.OneTimeCode);
        Assert.AreEqual(0, first.FrozenRevision);
        Assert.IsTrue(first.ExpiresAtUtc > DateTime.UtcNow.AddMinutes(14));

        CompleteSyncHandoverRequest completeRequest = new(first.OneTimeCode, target, 0);
        CompleteSyncHandoverResponse completed = await CompleteAsync(client, cookies, first.HandoverId, completeRequest);
        CompleteSyncHandoverResponse completedRetry = await CompleteAsync(client, cookies, first.HandoverId, completeRequest);
        Assert.AreEqual(target, completed.TargetClientId);
        Assert.IsTrue(completed.IsActiveWriter);
        Assert.AreEqual(
            completed.CompletedAtUtc.Ticks / TimeSpan.TicksPerMillisecond,
            completedRetry.CompletedAtUtc.Ticks / TimeSpan.TicksPerMillisecond);

        await RegisterAsync(client, cookies, source, "iPhone", takeOverWriting: true, HttpStatusCode.Conflict, "handover_required");

        BeginSyncHandoverRequest returnRequest = new(Guid.NewGuid(), target, 0);
        BeginSyncHandoverResponse returnHandover = await BeginAsync(client, cookies, returnRequest);
        CompleteSyncHandoverRequest returnComplete = new(returnHandover.OneTimeCode, source, 0);
        CompleteSyncHandoverResponse returned = await CompleteAsync(client, cookies, returnHandover.HandoverId, returnComplete);
        Assert.AreEqual(source, returned.TargetClientId);
        CompleteSyncHandoverResponse oldReplay = await CompleteAsync(client, cookies, first.HandoverId, completeRequest);
        Assert.IsFalse(oldReplay.IsActiveWriter);

        BeginSyncHandoverRequest secondForwardRequest = new(Guid.NewGuid(), source, 0);
        BeginSyncHandoverResponse secondForward = await BeginAsync(client, cookies, secondForwardRequest);
        CompleteSyncHandoverResponse secondForwardResult = await CompleteAsync(
            client,
            cookies,
            secondForward.HandoverId,
            new CompleteSyncHandoverRequest(secondForward.OneTimeCode, target, 0));
        Assert.AreEqual(target, secondForwardResult.TargetClientId);
    }

    [TestMethod]
    public async Task SameRequestAccountHeaderBindsSyncReadsAndWritesAndPreservesLegacyRequests()
    {
        Guid userA = Guid.NewGuid();
        Guid userB = Guid.NewGuid();
        await using WebApplication app = await CreateApplicationAsync();
        await CreateUserAsync(app, UserAEmail, userA);
        await CreateUserAsync(app, UserBEmail, userB);
        using HttpClient clientA = app.GetTestClient();
        using HttpClient clientB = app.GetTestClient();
        clientA.BaseAddress = clientB.BaseAddress = new Uri(TestOrigin);
        CookieJar cookiesA = await LoginAsync(clientA, UserAEmail);
        CookieJar cookiesB = await LoginAsync(clientB, UserBEmail);

        using (var matchingPull = new HttpRequestMessage(HttpMethod.Get, "/api/v1/sync/changes?after=0&limit=200"))
        {
            matchingPull.Headers.Add("X-Gainer-Account-Id", userA.ToString("D"));
            cookiesA.Apply(matchingPull);
            using HttpResponseMessage response = await clientA.SendAsync(matchingPull);
            Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);
        }
        using (var mismatchedPull = new HttpRequestMessage(HttpMethod.Get, "/api/v1/sync/changes?after=0&limit=200"))
        {
            mismatchedPull.Headers.Add("X-Gainer-Account-Id", userA.ToString("D"));
            cookiesB.Apply(mismatchedPull);
            using HttpResponseMessage response = await clientB.SendAsync(mismatchedPull);
            Assert.AreEqual(HttpStatusCode.Conflict, response.StatusCode);
            Assert.AreEqual("account_changed", await ProblemCodeAsync(response));
        }
        using (var legacyPull = new HttpRequestMessage(HttpMethod.Get, "/api/v1/sync/changes?after=0&limit=200"))
        {
            cookiesB.Apply(legacyPull);
            using HttpResponseMessage response = await clientB.SendAsync(legacyPull);
            Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);
        }

        Guid source = Guid.NewGuid();
        Guid target = Guid.NewGuid();
        await RegisterAsync(clientA, cookiesA, source, "Source", false, HttpStatusCode.OK,
            expectedAccountId: userA);
        Guid rejectedClientId = Guid.NewGuid();
        using (HttpResponseMessage registrationMismatch = await SendMutationAsync(
            clientB,
            cookiesB,
            HttpMethod.Put,
            $"/api/v1/sync/clients/{rejectedClientId}",
            new RegisterSyncClientRequest(rejectedClientId, "Foreign", SyncProtocol.CurrentVersion, false),
            expectedAccountId: userA))
        {
            Assert.AreEqual(HttpStatusCode.Conflict, registrationMismatch.StatusCode);
            Assert.AreEqual("account_changed", await ProblemCodeAsync(registrationMismatch));
        }
        await RegisterAsync(clientA, cookiesA, rejectedClientId, "Legacy target", false, HttpStatusCode.OK);
        await RegisterAsync(clientA, cookiesA, target, "Target", false, HttpStatusCode.OK);

        Guid mutationId = Guid.NewGuid();
        Guid checkInId = Guid.NewGuid();
        var mutation = new PushMutationRequest(
            SyncProtocol.CurrentVersion,
            source,
            1,
            "createDailyCheckIn",
            [new ResourceVersionRequest("DailyCheckIn", checkInId, 0)],
            null,
            JsonSerializer.SerializeToElement(new
            {
                checkInId,
                localDate = new DateOnly(2026, 10, 12),
                values = new { weightKg = 72m },
            }, JsonOptions));
        using (HttpResponseMessage mutationMismatch = await SendMutationAsync(
            clientB,
            cookiesB,
            HttpMethod.Put,
            $"/api/v1/sync/mutations/{mutationId}",
            mutation,
            expectedAccountId: userA))
        {
            Assert.AreEqual(HttpStatusCode.Conflict, mutationMismatch.StatusCode);
            Assert.AreEqual("account_changed", await ProblemCodeAsync(mutationMismatch));
        }
        using (HttpResponseMessage legacyMutation = await SendMutationAsync(
            clientA,
            cookiesA,
            HttpMethod.Put,
            $"/api/v1/sync/mutations/{mutationId}",
            mutation))
        {
            Assert.AreEqual(HttpStatusCode.OK, legacyMutation.StatusCode, await legacyMutation.Content.ReadAsStringAsync());
        }

        BeginSyncHandoverRequest beginRequest = new(Guid.NewGuid(), source, 1);
        using (HttpResponseMessage beginMismatch = await SendMutationAsync(
            clientB,
            cookiesB,
            HttpMethod.Post,
            "/api/v1/sync/handovers",
            beginRequest,
            expectedAccountId: userA))
        {
            Assert.AreEqual(HttpStatusCode.Conflict, beginMismatch.StatusCode);
            Assert.AreEqual("account_changed", await ProblemCodeAsync(beginMismatch));
        }
        BeginSyncHandoverResponse begin = await BeginAsync(clientA, cookiesA, beginRequest);
        CompleteSyncHandoverRequest completeRequest = new(begin.OneTimeCode, target, 1);
        using (HttpResponseMessage completeMismatch = await SendMutationAsync(
            clientB,
            cookiesB,
            HttpMethod.Post,
            $"/api/v1/sync/handovers/{begin.HandoverId}/complete",
            completeRequest,
            expectedAccountId: userA))
        {
            Assert.AreEqual(HttpStatusCode.Conflict, completeMismatch.StatusCode);
            Assert.AreEqual("account_changed", await ProblemCodeAsync(completeMismatch));
        }
        await CompleteAsync(clientA, cookiesA, begin.HandoverId, completeRequest);

        BeginSyncHandoverResponse cancel = await BeginAsync(
            clientA, cookiesA, new BeginSyncHandoverRequest(Guid.NewGuid(), target, 1));
        using (HttpResponseMessage cancelMismatch = await SendMutationAsync(
            clientB,
            cookiesB,
            HttpMethod.Post,
            $"/api/v1/sync/handovers/{cancel.HandoverId}/cancel",
            new CancelSyncHandoverRequest(target),
            expectedAccountId: userA))
        {
            Assert.AreEqual(HttpStatusCode.Conflict, cancelMismatch.StatusCode);
            Assert.AreEqual("account_changed", await ProblemCodeAsync(cancelMismatch));
        }
        await CancelAsync(clientA, cookiesA, cancel.HandoverId, target);
    }

    [TestMethod]
    public async Task HandoverFencesLateWritesAndCompetingTakeoverUntilCancel()
    {
        await using WebApplication app = await CreateApplicationAsync();
        await CreateUserAsync(app, UserAEmail);
        using HttpClient client = app.GetTestClient();
        client.BaseAddress = new Uri(TestOrigin);
        CookieJar cookies = await LoginAsync(client, UserAEmail);

        Guid source = Guid.NewGuid();
        Guid target = Guid.NewGuid();
        await RegisterAsync(client, cookies, source, "Source", takeOverWriting: false, HttpStatusCode.OK);
        await RegisterAsync(client, cookies, target, "Target", takeOverWriting: false, HttpStatusCode.OK);
        BeginSyncHandoverResponse handover = await BeginAsync(
            client, cookies, new BeginSyncHandoverRequest(Guid.NewGuid(), source, 0));

        await RegisterAsync(client, cookies, target, "Target", takeOverWriting: true, HttpStatusCode.Conflict, "handover_in_progress");

        Guid mutationId = Guid.NewGuid();
        Guid checkInId = Guid.NewGuid();
        var mutation = new PushMutationRequest(
            SyncProtocol.CurrentVersion,
            source,
            1,
            "createDailyCheckIn",
            [new ResourceVersionRequest("DailyCheckIn", checkInId, 0)],
            null,
            JsonSerializer.SerializeToElement(new
            {
                checkInId,
                localDate = new DateOnly(2026, 10, 12),
                values = new { weightKg = 70m },
            }, JsonOptions));
        using HttpResponseMessage lateWrite = await SendMutationAsync(
            client,
            cookies,
            HttpMethod.Put,
            $"/api/v1/sync/mutations/{mutationId}",
            mutation);
        Assert.AreEqual(HttpStatusCode.Conflict, lateWrite.StatusCode, await lateWrite.Content.ReadAsStringAsync());
        Assert.AreEqual("handover_in_progress", await ProblemCodeAsync(lateWrite));

        await CancelAsync(client, cookies, handover.HandoverId, source);
        await CancelAsync(client, cookies, handover.HandoverId, source);
        using HttpResponseMessage retriedWrite = await SendMutationAsync(
            client,
            cookies,
            HttpMethod.Put,
            $"/api/v1/sync/mutations/{mutationId}",
            mutation);
        Assert.AreEqual(HttpStatusCode.OK, retriedWrite.StatusCode, await retriedWrite.Content.ReadAsStringAsync());
    }

    [TestMethod]
    public async Task HandoverRejectsInvalidTargetCodeAndCompletedReversal()
    {
        await using WebApplication app = await CreateApplicationAsync();
        await CreateUserAsync(app, UserAEmail);
        using HttpClient client = app.GetTestClient();
        client.BaseAddress = new Uri(TestOrigin);
        CookieJar cookies = await LoginAsync(client, UserAEmail);

        Guid source = Guid.NewGuid();
        Guid target = Guid.NewGuid();
        Guid otherTarget = Guid.NewGuid();
        Guid unregisteredTarget = Guid.NewGuid();
        await RegisterAsync(client, cookies, source, "Source", takeOverWriting: false, HttpStatusCode.OK);
        await RegisterAsync(client, cookies, target, "Target", takeOverWriting: false, HttpStatusCode.OK);
        await RegisterAsync(client, cookies, otherTarget, "Other target", takeOverWriting: false, HttpStatusCode.OK);

        var request = new BeginSyncHandoverRequest(Guid.NewGuid(), source, 0);
        BeginSyncHandoverResponse handover = await BeginAsync(client, cookies, request);
        using (HttpResponseMessage reusedRequest = await SendMutationAsync(
            client,
            cookies,
            HttpMethod.Post,
            "/api/v1/sync/handovers",
            request with { ExpectedRevision = 1 }))
        {
            Assert.AreEqual(HttpStatusCode.Conflict, reusedRequest.StatusCode);
            Assert.AreEqual("handover_request_reused", await ProblemCodeAsync(reusedRequest));
        }

        await AssertCompletionRejectedAsync(client, cookies, handover, "wrong-code", target, "invalid_handover_code");
        await AssertCompletionRejectedAsync(client, cookies, handover, handover.OneTimeCode, source, "invalid_handover_target");
        await AssertCompletionRejectedAsync(client, cookies, handover, handover.OneTimeCode, unregisteredTarget, "target_not_registered");
        Assert.IsTrue(await IsActiveWriterAsync(client, cookies, source));

        var validCompletion = new CompleteSyncHandoverRequest(handover.OneTimeCode, target, 0);
        await CompleteAsync(client, cookies, handover.HandoverId, validCompletion);
        await AssertCompletionRejectedAsync(client, cookies, handover, handover.OneTimeCode, otherTarget, "handover_already_consumed");
        using HttpResponseMessage completedCancel = await SendMutationAsync(
            client,
            cookies,
            HttpMethod.Post,
            $"/api/v1/sync/handovers/{handover.HandoverId}/cancel",
            new CancelSyncHandoverRequest(source));
        Assert.AreEqual(HttpStatusCode.Conflict, completedCancel.StatusCode);
        Assert.AreEqual("handover_already_completed", await ProblemCodeAsync(completedCancel));
    }

    [TestMethod]
    public async Task BeginRacingMutationHasOneSerializedOutcomeAndNoLostChange()
    {
        await using WebApplication app = await CreateApplicationAsync();
        await CreateUserAsync(app, UserAEmail);
        using HttpClient beginClient = app.GetTestClient();
        using HttpClient mutationClient = app.GetTestClient();
        beginClient.BaseAddress = mutationClient.BaseAddress = new Uri(TestOrigin);
        CookieJar beginCookies = await LoginAsync(beginClient, UserAEmail);
        CookieJar mutationCookies = beginCookies.Clone();

        Guid source = Guid.NewGuid();
        await RegisterAsync(beginClient, beginCookies, source, "Source", takeOverWriting: false, HttpStatusCode.OK);
        var beginRequest = new BeginSyncHandoverRequest(Guid.NewGuid(), source, 0);
        Guid mutationId = Guid.NewGuid();
        Guid checkInId = Guid.NewGuid();
        var mutation = new PushMutationRequest(
            SyncProtocol.CurrentVersion,
            source,
            1,
            "createDailyCheckIn",
            [new ResourceVersionRequest("DailyCheckIn", checkInId, 0)],
            null,
            JsonSerializer.SerializeToElement(new
            {
                checkInId,
                localDate = new DateOnly(2026, 10, 12),
                values = new { weightKg = 71m },
            }, JsonOptions));

        Task<HttpResponseMessage> beginTask = SendMutationAsync(
            beginClient, beginCookies, HttpMethod.Post, "/api/v1/sync/handovers", beginRequest);
        Task<HttpResponseMessage> mutationTask = SendMutationAsync(
            mutationClient,
            mutationCookies,
            HttpMethod.Put,
            $"/api/v1/sync/mutations/{mutationId}",
            mutation);
        using HttpResponseMessage beginResponse = await beginTask;
        using HttpResponseMessage mutationResponse = await mutationTask;

        Assert.IsTrue(
            beginResponse.StatusCode is HttpStatusCode.OK or HttpStatusCode.Conflict,
            await beginResponse.Content.ReadAsStringAsync());
        Assert.IsTrue(
            mutationResponse.StatusCode is HttpStatusCode.OK or HttpStatusCode.Conflict,
            await mutationResponse.Content.ReadAsStringAsync());
        Assert.IsFalse(
            beginResponse.StatusCode == HttpStatusCode.OK && mutationResponse.StatusCode == HttpStatusCode.OK,
            "A frozen revision and a mutation from that revision cannot both be accepted.");
        if (beginResponse.StatusCode == HttpStatusCode.Conflict)
        {
            string? code = await ProblemCodeAsync(beginResponse);
            Assert.IsTrue(new[] { "stale_revision", "concurrent_handover" }.Contains(code));
        }
        if (mutationResponse.StatusCode == HttpStatusCode.Conflict)
        {
            string? code = await ProblemCodeAsync(mutationResponse);
            Assert.IsTrue(new[] { "handover_in_progress", "concurrent_mutation" }.Contains(code));
        }

        using var feedRequest = new HttpRequestMessage(HttpMethod.Get, "/api/v1/sync/changes?after=0&limit=200");
        beginCookies.Apply(feedRequest);
        using HttpResponseMessage feedResponse = await beginClient.SendAsync(feedRequest);
        Assert.AreEqual(HttpStatusCode.OK, feedResponse.StatusCode, await feedResponse.Content.ReadAsStringAsync());
        PullChangesResponse feed = (await feedResponse.Content.ReadFromJsonAsync<PullChangesResponse>())!;
        Assert.AreEqual(mutationResponse.StatusCode == HttpStatusCode.OK ? 1 : 0, feed.NextCursor);
    }

    [TestMethod]
    public async Task HandoverIsAccountBoundExpiresAfterFifteenMinutesAndAllowsCompletedRetryAfterExpiry()
    {
        TestTimeProvider clock = new(DateTimeOffset.Parse("2026-10-12T10:00:00Z"));
        await using WebApplication app = await CreateApplicationAsync(clock);
        await CreateUserAsync(app, UserAEmail);
        await CreateUserAsync(app, UserBEmail);
        using HttpClient clientA = app.GetTestClient();
        using HttpClient clientB = app.GetTestClient();
        clientA.BaseAddress = clientB.BaseAddress = new Uri(TestOrigin);
        CookieJar cookiesA = await LoginAsync(clientA, UserAEmail);
        CookieJar cookiesB = await LoginAsync(clientB, UserBEmail);
        await RegisterAsync(clientB, cookiesB, Guid.NewGuid(), "Other account", takeOverWriting: false, HttpStatusCode.OK);

        Guid source = Guid.NewGuid();
        Guid target = Guid.NewGuid();
        await RegisterAsync(clientA, cookiesA, source, "Source", takeOverWriting: false, HttpStatusCode.OK);
        await RegisterAsync(clientA, cookiesA, target, "Target", takeOverWriting: false, HttpStatusCode.OK);
        BeginSyncHandoverResponse expired = await BeginAsync(
            clientA, cookiesA, new BeginSyncHandoverRequest(Guid.NewGuid(), source, 0));

        using HttpResponseMessage foreignAttempt = await SendMutationAsync(
            clientB,
            cookiesB,
            HttpMethod.Post,
            $"/api/v1/sync/handovers/{expired.HandoverId}/complete",
            new CompleteSyncHandoverRequest(expired.OneTimeCode, target, 0));
        Assert.AreEqual(HttpStatusCode.NotFound, foreignAttempt.StatusCode);

        clock.Advance(TimeSpan.FromMinutes(15).Add(TimeSpan.FromSeconds(1)));
        using HttpResponseMessage expiredAttempt = await SendMutationAsync(
            clientA,
            cookiesA,
            HttpMethod.Post,
            $"/api/v1/sync/handovers/{expired.HandoverId}/complete",
            new CompleteSyncHandoverRequest(expired.OneTimeCode, target, 0));
        Assert.AreEqual(HttpStatusCode.Conflict, expiredAttempt.StatusCode);
        Assert.AreEqual("handover_expired", await ProblemCodeAsync(expiredAttempt));

        BeginSyncHandoverResponse completed = await BeginAsync(
            clientA, cookiesA, new BeginSyncHandoverRequest(Guid.NewGuid(), source, 0));
        var completionRequest = new CompleteSyncHandoverRequest(completed.OneTimeCode, target, 0);
        await CompleteAsync(clientA, cookiesA, completed.HandoverId, completionRequest);
        clock.Advance(TimeSpan.FromMinutes(16));
        CompleteSyncHandoverResponse replay = await CompleteAsync(clientA, cookiesA, completed.HandoverId, completionRequest);
        Assert.AreEqual(target, replay.TargetClientId);
        Assert.IsTrue(replay.IsActiveWriter);
    }

    private async Task<WebApplication> CreateApplicationAsync(TestTimeProvider? clock = null)
    {
        string connectionString = await Fixture.CreateIsolatedDatabaseAsync();
        await using (AppDbContext context = Fixture.CreateContext(connectionString))
            await context.Database.MigrateAsync();

        string keyRingPath = Path.Combine(Path.GetTempPath(), $"gainer-sync-handover-api-{Guid.NewGuid():N}");
        keyRingPaths.Add(keyRingPath);
        var builder = WebApplication.CreateBuilder();
        builder.Logging.ClearProviders();
        builder.WebHost.UseTestServer();
        builder.Configuration["ConnectionStrings:gainer-db"] = connectionString;
        builder.Configuration[GainerIdentityOptions.DataProtectionKeysPathConfigurationKey] = keyRingPath;
        builder.Configuration[GainerRequestSecurityOptions.FrontendOriginConfigurationKey] = TestOrigin;
        builder.AddGainerApi();
        builder.AddGainerPersistence();
        builder.AddGainerIdentity();
        if (clock is not null)
        {
            builder.Services.RemoveAll<TimeProvider>();
            builder.Services.AddSingleton<TimeProvider>(clock);
        }

        WebApplication app = builder.Build();
        app.MapGainerApi();
        await app.StartAsync();
        return app;
    }

    private static async Task CreateUserAsync(WebApplication app, string email, Guid? userId = null)
    {
        await using AsyncServiceScope scope = app.Services.CreateAsyncScope();
        UserManager<AppUser> users = scope.ServiceProvider.GetRequiredService<UserManager<AppUser>>();
        IdentityResult result = await users.CreateAsync(new AppUser
        {
            Id = userId ?? Guid.NewGuid(),
            UserName = email,
            Email = email,
            EmailConfirmed = true,
            IsActive = true,
        }, Password);
        Assert.IsTrue(result.Succeeded, string.Join(", ", result.Errors.Select(error => error.Code)));
    }

    private static async Task<CookieJar> LoginAsync(HttpClient client, string email)
    {
        var cookies = new CookieJar();
        string token = await GetAntiforgeryTokenAsync(client, cookies);
        using HttpResponseMessage login = await SendMutationWithTokenAsync(
            client, cookies, HttpMethod.Post, "/api/v1/auth/login", new LoginRequest(email, Password), token);
        Assert.AreEqual(HttpStatusCode.NoContent, login.StatusCode, await login.Content.ReadAsStringAsync());
        _ = await GetAntiforgeryTokenAsync(client, cookies);
        return cookies;
    }

    private static async Task RegisterAsync(
        HttpClient client,
        CookieJar cookies,
        Guid clientId,
        string displayName,
        bool takeOverWriting,
        HttpStatusCode expectedStatus,
        string? expectedCode = null,
        Guid? expectedAccountId = null)
    {
        using HttpResponseMessage response = await SendMutationAsync(
            client,
            cookies,
            HttpMethod.Put,
            $"/api/v1/sync/clients/{clientId}",
            new RegisterSyncClientRequest(clientId, displayName, SyncProtocol.CurrentVersion, takeOverWriting),
            expectedAccountId);
        Assert.AreEqual(expectedStatus, response.StatusCode, await response.Content.ReadAsStringAsync());
        if (expectedCode is not null) Assert.AreEqual(expectedCode, await ProblemCodeAsync(response));
    }

    private static async Task<BeginSyncHandoverResponse> BeginAsync(
        HttpClient client,
        CookieJar cookies,
        BeginSyncHandoverRequest request)
    {
        using HttpResponseMessage response = await SendMutationAsync(
            client, cookies, HttpMethod.Post, "/api/v1/sync/handovers", request);
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode, await response.Content.ReadAsStringAsync());
        return (await response.Content.ReadFromJsonAsync<BeginSyncHandoverResponse>())!;
    }

    private static async Task AssertCompletionRejectedAsync(
        HttpClient client,
        CookieJar cookies,
        BeginSyncHandoverResponse handover,
        string code,
        Guid targetClientId,
        string expectedProblemCode)
    {
        using HttpResponseMessage response = await SendMutationAsync(
            client,
            cookies,
            HttpMethod.Post,
            $"/api/v1/sync/handovers/{handover.HandoverId}/complete",
            new CompleteSyncHandoverRequest(code, targetClientId, 0));
        Assert.AreEqual(HttpStatusCode.Conflict, response.StatusCode, await response.Content.ReadAsStringAsync());
        Assert.AreEqual(expectedProblemCode, await ProblemCodeAsync(response));
    }

    private static async Task<bool> IsActiveWriterAsync(HttpClient client, CookieJar cookies, Guid clientId)
    {
        using HttpResponseMessage response = await SendMutationAsync(
            client,
            cookies,
            HttpMethod.Put,
            $"/api/v1/sync/clients/{clientId}",
            new RegisterSyncClientRequest(clientId, "Source", SyncProtocol.CurrentVersion, false));
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode, await response.Content.ReadAsStringAsync());
        SyncClientResponse result = (await response.Content.ReadFromJsonAsync<SyncClientResponse>())!;
        return result.IsActiveWriter;
    }

    private static async Task<CompleteSyncHandoverResponse> CompleteAsync(
        HttpClient client,
        CookieJar cookies,
        Guid handoverId,
        CompleteSyncHandoverRequest request)
    {
        using HttpResponseMessage response = await SendMutationAsync(
            client, cookies, HttpMethod.Post, $"/api/v1/sync/handovers/{handoverId}/complete", request);
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode, await response.Content.ReadAsStringAsync());
        return (await response.Content.ReadFromJsonAsync<CompleteSyncHandoverResponse>())!;
    }

    private static async Task CancelAsync(HttpClient client, CookieJar cookies, Guid handoverId, Guid sourceClientId)
    {
        using HttpResponseMessage response = await SendMutationAsync(
            client,
            cookies,
            HttpMethod.Post,
            $"/api/v1/sync/handovers/{handoverId}/cancel",
            new CancelSyncHandoverRequest(sourceClientId));
        Assert.AreEqual(HttpStatusCode.NoContent, response.StatusCode, await response.Content.ReadAsStringAsync());
    }

    private static async Task<string> GetAntiforgeryTokenAsync(HttpClient client, CookieJar cookies)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, "/api/v1/auth/antiforgery");
        cookies.Apply(request);
        using HttpResponseMessage response = await client.SendAsync(request);
        cookies.Capture(response);
        response.EnsureSuccessStatusCode();
        AntiforgeryTokenResponse result = (await response.Content.ReadFromJsonAsync<AntiforgeryTokenResponse>())!;
        return result.RequestToken;
    }

    private static async Task<HttpResponseMessage> SendMutationAsync<TBody>(
        HttpClient client,
        CookieJar cookies,
        HttpMethod method,
        string path,
        TBody body,
        Guid? expectedAccountId = null)
    {
        string token = await GetAntiforgeryTokenAsync(client, cookies);
        return await SendMutationWithTokenAsync(client, cookies, method, path, body, token, expectedAccountId);
    }

    private static async Task<HttpResponseMessage> SendMutationWithTokenAsync<TBody>(
        HttpClient client,
        CookieJar cookies,
        HttpMethod method,
        string path,
        TBody body,
        string token,
        Guid? expectedAccountId = null)
    {
        using var request = new HttpRequestMessage(method, path) { Content = JsonContent.Create(body) };
        request.Headers.Add("Origin", TestOrigin);
        request.Headers.Add(GainerRequestSecurityOptions.AntiforgeryHeaderName, token);
        if (expectedAccountId is Guid accountId)
            request.Headers.Add("X-Gainer-Account-Id", accountId.ToString("D"));
        cookies.Apply(request);
        HttpResponseMessage response = await client.SendAsync(request);
        cookies.Capture(response);
        return response;
    }

    private static async Task<string?> ProblemCodeAsync(HttpResponseMessage response)
    {
        using JsonDocument problem = await JsonDocument.ParseAsync(await response.Content.ReadAsStreamAsync());
        return problem.RootElement.GetProperty("code").GetString();
    }

    private sealed class CookieJar
    {
        private readonly Dictionary<string, string> values = new(StringComparer.Ordinal);

        public CookieJar Clone()
        {
            var clone = new CookieJar();
            foreach ((string name, string value) in values) clone.values[name] = value;
            return clone;
        }

        public void Capture(HttpResponseMessage response)
        {
            if (!response.Headers.TryGetValues("Set-Cookie", out IEnumerable<string>? headers)) return;
            foreach (string header in headers)
            {
                string[] pair = header.Split(';', 2)[0].Split('=', 2);
                if (pair[1].Length == 0) values.Remove(pair[0]);
                else values[pair[0]] = pair[1];
            }
        }

        public void Apply(HttpRequestMessage request)
        {
            if (values.Count > 0)
                request.Headers.Add("Cookie", string.Join("; ", values.Select(pair => $"{pair.Key}={pair.Value}")));
        }
    }

    private sealed class TestTimeProvider(DateTimeOffset utcNow) : TimeProvider
    {
        private DateTimeOffset current = utcNow;
        public override DateTimeOffset GetUtcNow() => current;
        public void Advance(TimeSpan value) => current += value;
    }
}
