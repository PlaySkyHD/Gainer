using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Gainer.Api.Composition;
using Gainer.Api.Security;
using Gainer.Contracts.Security;
using Gainer.Contracts.Sync;
using Gainer.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authentication.BearerToken;
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
        TestSession auth = await LoginAsync(client, UserAEmail);

        Guid source = Guid.NewGuid();
        Guid target = Guid.NewGuid();
        await RegisterAsync(client, auth, source, "iPhone", takeOverWriting: false, HttpStatusCode.OK);
        await RegisterAsync(client, auth, target, "PWA", takeOverWriting: false, HttpStatusCode.OK);

        BeginSyncHandoverRequest firstRequest = new(Guid.NewGuid(), source, 0);
        BeginSyncHandoverResponse first = await BeginAsync(client, auth, firstRequest);
        BeginSyncHandoverResponse concurrentRetry = await BeginAsync(client, auth, firstRequest);
        Assert.AreEqual(first.HandoverId, concurrentRetry.HandoverId);
        Assert.AreEqual(first.OneTimeCode, concurrentRetry.OneTimeCode);
        Assert.AreEqual(0, first.FrozenRevision);
        Assert.IsGreaterThan(DateTime.UtcNow.AddMinutes(14), first.ExpiresAtUtc);

        CompleteSyncHandoverRequest completeRequest = new(first.OneTimeCode, target, 0);
        CompleteSyncHandoverResponse completed = await CompleteAsync(client, auth, first.HandoverId, completeRequest);
        CompleteSyncHandoverResponse completedRetry = await CompleteAsync(client, auth, first.HandoverId, completeRequest);
        Assert.AreEqual(target, completed.TargetClientId);
        Assert.IsTrue(completed.IsActiveWriter);
        Assert.AreEqual(
            completed.CompletedAtUtc.Ticks / TimeSpan.TicksPerMillisecond,
            completedRetry.CompletedAtUtc.Ticks / TimeSpan.TicksPerMillisecond);

        await RegisterAsync(client, auth, source, "iPhone", takeOverWriting: true, HttpStatusCode.Conflict, "handover_required");

        BeginSyncHandoverRequest returnRequest = new(Guid.NewGuid(), target, 0);
        BeginSyncHandoverResponse returnHandover = await BeginAsync(client, auth, returnRequest);
        CompleteSyncHandoverRequest returnComplete = new(returnHandover.OneTimeCode, source, 0);
        CompleteSyncHandoverResponse returned = await CompleteAsync(client, auth, returnHandover.HandoverId, returnComplete);
        Assert.AreEqual(source, returned.TargetClientId);
        CompleteSyncHandoverResponse oldReplay = await CompleteAsync(client, auth, first.HandoverId, completeRequest);
        Assert.IsFalse(oldReplay.IsActiveWriter);

        BeginSyncHandoverRequest secondForwardRequest = new(Guid.NewGuid(), source, 0);
        BeginSyncHandoverResponse secondForward = await BeginAsync(client, auth, secondForwardRequest);
        CompleteSyncHandoverResponse secondForwardResult = await CompleteAsync(
            client,
            auth,
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
        TestSession authA = await LoginAsync(clientA, UserAEmail);
        TestSession authB = await LoginAsync(clientB, UserBEmail);

        using (var matchingPull = new HttpRequestMessage(HttpMethod.Get, "/api/v1/sync/changes?after=0&limit=200"))
        {
            matchingPull.Headers.Add("X-Gainer-Account-Id", userA.ToString("D"));
            authA.Apply(matchingPull);
            using HttpResponseMessage response = await clientA.SendAsync(matchingPull, TestContext.CancellationToken);
            Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);
        }
        using (var mismatchedPull = new HttpRequestMessage(HttpMethod.Get, "/api/v1/sync/changes?after=0&limit=200"))
        {
            mismatchedPull.Headers.Add("X-Gainer-Account-Id", userA.ToString("D"));
            authB.Apply(mismatchedPull);
            using HttpResponseMessage response = await clientB.SendAsync(mismatchedPull, TestContext.CancellationToken);
            Assert.AreEqual(HttpStatusCode.Conflict, response.StatusCode);
            Assert.AreEqual("account_changed", await ProblemCodeAsync(response));
        }
        using (var legacyPull = new HttpRequestMessage(HttpMethod.Get, "/api/v1/sync/changes?after=0&limit=200"))
        {
            authB.WithoutAccountHeader().Apply(legacyPull);
            using HttpResponseMessage response = await clientB.SendAsync(legacyPull, TestContext.CancellationToken);
            Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);
        }

        // From protocol 4 on, the account header is mandatory on pulls, registration and mutations.
        using (var headerlessPull = new HttpRequestMessage(
            HttpMethod.Get,
            $"/api/v1/sync/changes?after=0&limit=200&protocolVersion={SyncProtocol.CurrentVersion}"))
        {
            authB.WithoutAccountHeader().Apply(headerlessPull);
            using HttpResponseMessage response = await clientB.SendAsync(headerlessPull, TestContext.CancellationToken);
            Assert.AreEqual(HttpStatusCode.UnprocessableEntity, response.StatusCode);
            Assert.AreEqual("account_header_required", await ProblemCodeAsync(response));
        }
        Guid headerlessClientId = Guid.NewGuid();
        using (HttpResponseMessage headerlessRegistration = await SendMutationAsync(
            clientB,
            authB.WithoutAccountHeader(),
            HttpMethod.Put,
            $"/api/v1/sync/clients/{headerlessClientId}",
            new RegisterSyncClientRequest(headerlessClientId, "Headerless", SyncProtocol.CurrentVersion, false)))
        {
            Assert.AreEqual(HttpStatusCode.UnprocessableEntity, headerlessRegistration.StatusCode);
            Assert.AreEqual("account_header_required", await ProblemCodeAsync(headerlessRegistration));
        }
        using (HttpResponseMessage headerlessMutation = await SendMutationAsync(
            clientB,
            authB.WithoutAccountHeader(),
            HttpMethod.Put,
            $"/api/v1/sync/mutations/{Guid.NewGuid()}",
            new PushMutationRequest(
                SyncProtocol.CurrentVersion,
                headerlessClientId,
                1,
                "createDailyCheckIn",
                [new ResourceVersionRequest("DailyCheckIn", Guid.NewGuid(), 0)],
                null,
                JsonSerializer.SerializeToElement(new { }))))
        {
            Assert.AreEqual(HttpStatusCode.UnprocessableEntity, headerlessMutation.StatusCode);
            Assert.AreEqual("account_header_required", await ProblemCodeAsync(headerlessMutation));
        }

        Guid source = Guid.NewGuid();
        Guid target = Guid.NewGuid();
        await RegisterAsync(clientA, authA, source, "Source", false, HttpStatusCode.OK,
            expectedAccountId: userA);
        Guid rejectedClientId = Guid.NewGuid();
        using (HttpResponseMessage registrationMismatch = await SendMutationAsync(
            clientB,
            authB,
            HttpMethod.Put,
            $"/api/v1/sync/clients/{rejectedClientId}",
            new RegisterSyncClientRequest(rejectedClientId, "Foreign", SyncProtocol.CurrentVersion, false),
            expectedAccountId: userA))
        {
            Assert.AreEqual(HttpStatusCode.Conflict, registrationMismatch.StatusCode);
            Assert.AreEqual("account_changed", await ProblemCodeAsync(registrationMismatch));
        }
        await RegisterAsync(clientA, authA, rejectedClientId, "Legacy target", false, HttpStatusCode.OK);
        await RegisterAsync(clientA, authA, target, "Target", false, HttpStatusCode.OK);

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
            authB,
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
            authA,
            HttpMethod.Put,
            $"/api/v1/sync/mutations/{mutationId}",
            mutation))
        {
            Assert.AreEqual(HttpStatusCode.OK, legacyMutation.StatusCode, await legacyMutation.Content.ReadAsStringAsync(TestContext.CancellationToken));
        }

        BeginSyncHandoverRequest beginRequest = new(Guid.NewGuid(), source, 1);
        using (HttpResponseMessage beginMismatch = await SendMutationAsync(
            clientB,
            authB,
            HttpMethod.Post,
            "/api/v1/sync/handovers",
            beginRequest,
            expectedAccountId: userA))
        {
            Assert.AreEqual(HttpStatusCode.Conflict, beginMismatch.StatusCode);
            Assert.AreEqual("account_changed", await ProblemCodeAsync(beginMismatch));
        }
        BeginSyncHandoverResponse begin = await BeginAsync(clientA, authA, beginRequest);
        CompleteSyncHandoverRequest completeRequest = new(begin.OneTimeCode, target, 1);
        using (HttpResponseMessage completeMismatch = await SendMutationAsync(
            clientB,
            authB,
            HttpMethod.Post,
            $"/api/v1/sync/handovers/{begin.HandoverId}/complete",
            completeRequest,
            expectedAccountId: userA))
        {
            Assert.AreEqual(HttpStatusCode.Conflict, completeMismatch.StatusCode);
            Assert.AreEqual("account_changed", await ProblemCodeAsync(completeMismatch));
        }
        await CompleteAsync(clientA, authA, begin.HandoverId, completeRequest);

        BeginSyncHandoverResponse cancel = await BeginAsync(
            clientA, authA, new BeginSyncHandoverRequest(Guid.NewGuid(), target, 1));
        using (HttpResponseMessage cancelMismatch = await SendMutationAsync(
            clientB,
            authB,
            HttpMethod.Post,
            $"/api/v1/sync/handovers/{cancel.HandoverId}/cancel",
            new CancelSyncHandoverRequest(target),
            expectedAccountId: userA))
        {
            Assert.AreEqual(HttpStatusCode.Conflict, cancelMismatch.StatusCode);
            Assert.AreEqual("account_changed", await ProblemCodeAsync(cancelMismatch));
        }
        await CancelAsync(clientA, authA, cancel.HandoverId, target);
    }

    [TestMethod]
    public async Task DeviceHandoverWorksAfterWaterWasRecorded()
    {
        await using WebApplication app = await CreateApplicationAsync();
        await CreateUserAsync(app, UserAEmail);
        using HttpClient client = app.GetTestClient();
        client.BaseAddress = new Uri(TestOrigin);
        TestSession auth = await LoginAsync(client, UserAEmail);
        Guid source = Guid.NewGuid();
        Guid target = Guid.NewGuid();
        await RegisterAsync(client, auth, source, "Source", takeOverWriting: false, HttpStatusCode.OK);

        Guid dayId = Guid.NewGuid();
        using (HttpResponseMessage water = await SendMutationAsync(
            client,
            auth,
            HttpMethod.Put,
            $"/api/v1/sync/mutations/{Guid.NewGuid()}",
            new PushMutationRequest(
                SyncProtocol.CurrentVersion,
                source,
                1,
                "setWaterIntake",
                [new ResourceVersionRequest("WaterIntakeDay", dayId, 0)],
                null,
                JsonSerializer.SerializeToElement(new
                {
                    waterIntakeDayId = dayId,
                    localDate = new DateOnly(2026, 10, 25),
                    baseVersion = 0,
                    amountMl = 1250,
                }, JsonOptions))))
        {
            Assert.AreEqual(HttpStatusCode.OK, water.StatusCode, await water.Content.ReadAsStringAsync(TestContext.CancellationToken));
        }

        // A target that registers with the old protocol is told to update; the current app passes.
        using (HttpResponseMessage oldTarget = await SendMutationAsync(
            client,
            auth,
            HttpMethod.Put,
            $"/api/v1/sync/clients/{target}",
            new RegisterSyncClientRequest(target, "Target", SyncProtocol.UnversionedPullVersion, false)))
        {
            Assert.AreEqual(HttpStatusCode.Conflict, oldTarget.StatusCode);
            Assert.AreEqual("upgrade_required", await ProblemCodeAsync(oldTarget));
        }
        await RegisterAsync(client, auth, target, "Target", takeOverWriting: false, HttpStatusCode.OK);

        BeginSyncHandoverResponse begin = await BeginAsync(
            client, auth, new BeginSyncHandoverRequest(Guid.NewGuid(), source, 1));
        CompleteSyncHandoverResponse completed = await CompleteAsync(
            client, auth, begin.HandoverId, new CompleteSyncHandoverRequest(begin.OneTimeCode, target, 1));

        Assert.IsTrue(completed.IsActiveWriter);
        Assert.IsTrue(await IsActiveWriterAsync(client, auth, target));
        using var pull = new HttpRequestMessage(
            HttpMethod.Get,
            $"/api/v1/sync/changes?after=0&limit=200&protocolVersion={SyncProtocol.CurrentVersion}");
        auth.Apply(pull);
        using HttpResponseMessage pulled = await client.SendAsync(pull, TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.OK, pulled.StatusCode);
        PullChangesResponse page = (await pulled.Content.ReadFromJsonAsync<PullChangesResponse>(TestContext.CancellationToken))!;
        Assert.AreEqual(dayId, page.Batches.Single().Changes.Single().ResourceId);
    }

    [TestMethod]
    public async Task HandoverFencesLateWritesAndCompetingTakeoverUntilCancel()
    {
        await using WebApplication app = await CreateApplicationAsync();
        await CreateUserAsync(app, UserAEmail);
        using HttpClient client = app.GetTestClient();
        client.BaseAddress = new Uri(TestOrigin);
        TestSession auth = await LoginAsync(client, UserAEmail);

        Guid source = Guid.NewGuid();
        Guid target = Guid.NewGuid();
        await RegisterAsync(client, auth, source, "Source", takeOverWriting: false, HttpStatusCode.OK);
        await RegisterAsync(client, auth, target, "Target", takeOverWriting: false, HttpStatusCode.OK);
        BeginSyncHandoverResponse handover = await BeginAsync(
            client, auth, new BeginSyncHandoverRequest(Guid.NewGuid(), source, 0));

        await RegisterAsync(client, auth, target, "Target", takeOverWriting: true, HttpStatusCode.Conflict, "handover_in_progress");

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
            auth,
            HttpMethod.Put,
            $"/api/v1/sync/mutations/{mutationId}",
            mutation);
        Assert.AreEqual(HttpStatusCode.Conflict, lateWrite.StatusCode, await lateWrite.Content.ReadAsStringAsync(TestContext.CancellationToken));
        Assert.AreEqual("handover_in_progress", await ProblemCodeAsync(lateWrite));

        await CancelAsync(client, auth, handover.HandoverId, source);
        await CancelAsync(client, auth, handover.HandoverId, source);
        using HttpResponseMessage retriedWrite = await SendMutationAsync(
            client,
            auth,
            HttpMethod.Put,
            $"/api/v1/sync/mutations/{mutationId}",
            mutation);
        Assert.AreEqual(HttpStatusCode.OK, retriedWrite.StatusCode, await retriedWrite.Content.ReadAsStringAsync(TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task HandoverRejectsInvalidTargetCodeAndCompletedReversal()
    {
        await using WebApplication app = await CreateApplicationAsync();
        await CreateUserAsync(app, UserAEmail);
        using HttpClient client = app.GetTestClient();
        client.BaseAddress = new Uri(TestOrigin);
        TestSession auth = await LoginAsync(client, UserAEmail);

        Guid source = Guid.NewGuid();
        Guid target = Guid.NewGuid();
        Guid otherTarget = Guid.NewGuid();
        Guid unregisteredTarget = Guid.NewGuid();
        await RegisterAsync(client, auth, source, "Source", takeOverWriting: false, HttpStatusCode.OK);
        await RegisterAsync(client, auth, target, "Target", takeOverWriting: false, HttpStatusCode.OK);
        await RegisterAsync(client, auth, otherTarget, "Other target", takeOverWriting: false, HttpStatusCode.OK);

        var request = new BeginSyncHandoverRequest(Guid.NewGuid(), source, 0);
        BeginSyncHandoverResponse handover = await BeginAsync(client, auth, request);
        using (HttpResponseMessage reusedRequest = await SendMutationAsync(
            client,
            auth,
            HttpMethod.Post,
            "/api/v1/sync/handovers",
            request with { ExpectedRevision = 1 }))
        {
            Assert.AreEqual(HttpStatusCode.Conflict, reusedRequest.StatusCode);
            Assert.AreEqual("handover_request_reused", await ProblemCodeAsync(reusedRequest));
        }

        await AssertCompletionRejectedAsync(client, auth, handover, "wrong-code", target, "invalid_handover_code");
        await AssertCompletionRejectedAsync(client, auth, handover, handover.OneTimeCode, source, "invalid_handover_target");
        await AssertCompletionRejectedAsync(client, auth, handover, handover.OneTimeCode, unregisteredTarget, "target_not_registered");
        Assert.IsTrue(await IsActiveWriterAsync(client, auth, source));

        var validCompletion = new CompleteSyncHandoverRequest(handover.OneTimeCode, target, 0);
        await CompleteAsync(client, auth, handover.HandoverId, validCompletion);
        await AssertCompletionRejectedAsync(client, auth, handover, handover.OneTimeCode, otherTarget, "handover_already_consumed");
        using HttpResponseMessage completedCancel = await SendMutationAsync(
            client,
            auth,
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
        TestSession beginAuth = await LoginAsync(beginClient, UserAEmail);
        TestSession mutationAuth = beginAuth.Clone();

        Guid source = Guid.NewGuid();
        await RegisterAsync(beginClient, beginAuth, source, "Source", takeOverWriting: false, HttpStatusCode.OK);
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
            beginClient, beginAuth, HttpMethod.Post, "/api/v1/sync/handovers", beginRequest);
        Task<HttpResponseMessage> mutationTask = SendMutationAsync(
            mutationClient,
            mutationAuth,
            HttpMethod.Put,
            $"/api/v1/sync/mutations/{mutationId}",
            mutation);
        using HttpResponseMessage beginResponse = await beginTask;
        using HttpResponseMessage mutationResponse = await mutationTask;

        Assert.IsTrue(
            beginResponse.StatusCode is HttpStatusCode.OK or HttpStatusCode.Conflict,
            await beginResponse.Content.ReadAsStringAsync(TestContext.CancellationToken));
        Assert.IsTrue(
            mutationResponse.StatusCode is HttpStatusCode.OK or HttpStatusCode.Conflict,
            await mutationResponse.Content.ReadAsStringAsync(TestContext.CancellationToken));
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
        beginAuth.Apply(feedRequest);
        using HttpResponseMessage feedResponse = await beginClient.SendAsync(feedRequest, TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.OK, feedResponse.StatusCode, await feedResponse.Content.ReadAsStringAsync(TestContext.CancellationToken));
        PullChangesResponse feed = (await feedResponse.Content.ReadFromJsonAsync<PullChangesResponse>(TestContext.CancellationToken))!;
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
        TestSession authA = await LoginAsync(clientA, UserAEmail);
        TestSession authB = await LoginAsync(clientB, UserBEmail);
        await RegisterAsync(clientB, authB, Guid.NewGuid(), "Other account", takeOverWriting: false, HttpStatusCode.OK);

        Guid source = Guid.NewGuid();
        Guid target = Guid.NewGuid();
        await RegisterAsync(clientA, authA, source, "Source", takeOverWriting: false, HttpStatusCode.OK);
        await RegisterAsync(clientA, authA, target, "Target", takeOverWriting: false, HttpStatusCode.OK);
        BeginSyncHandoverResponse expired = await BeginAsync(
            clientA, authA, new BeginSyncHandoverRequest(Guid.NewGuid(), source, 0));

        using HttpResponseMessage foreignAttempt = await SendMutationAsync(
            clientB,
            authB,
            HttpMethod.Post,
            $"/api/v1/sync/handovers/{expired.HandoverId}/complete",
            new CompleteSyncHandoverRequest(expired.OneTimeCode, target, 0));
        Assert.AreEqual(HttpStatusCode.NotFound, foreignAttempt.StatusCode);

        clock.Advance(TimeSpan.FromMinutes(15).Add(TimeSpan.FromSeconds(1)));
        using HttpResponseMessage expiredAttempt = await SendMutationAsync(
            clientA,
            authA,
            HttpMethod.Post,
            $"/api/v1/sync/handovers/{expired.HandoverId}/complete",
            new CompleteSyncHandoverRequest(expired.OneTimeCode, target, 0));
        Assert.AreEqual(HttpStatusCode.Conflict, expiredAttempt.StatusCode);
        Assert.AreEqual("handover_expired", await ProblemCodeAsync(expiredAttempt));

        BeginSyncHandoverResponse completed = await BeginAsync(
            clientA, authA, new BeginSyncHandoverRequest(Guid.NewGuid(), source, 0));
        var completionRequest = new CompleteSyncHandoverRequest(completed.OneTimeCode, target, 0);
        await CompleteAsync(clientA, authA, completed.HandoverId, completionRequest);
        clock.Advance(TimeSpan.FromMinutes(16));
        CompleteSyncHandoverResponse replay = await CompleteAsync(clientA, authA, completed.HandoverId, completionRequest);
        Assert.AreEqual(target, replay.TargetClientId);
        Assert.IsTrue(replay.IsActiveWriter);
    }

    [TestMethod]
    public async Task NullResourceExpectationIsUnprocessable()
    {
        await using WebApplication app = await CreateApplicationAsync();
        await CreateUserAsync(app, UserAEmail);
        using HttpClient client = app.GetTestClient();
        client.BaseAddress = new Uri(TestOrigin);
        TestSession auth = await LoginAsync(client, UserAEmail);
        Guid source = Guid.NewGuid();
        await RegisterAsync(client, auth, source, "Source", takeOverWriting: false, HttpStatusCode.OK);

        using HttpResponseMessage response = await SendMutationAsync(
            client,
            auth,
            HttpMethod.Put,
            $"/api/v1/sync/mutations/{Guid.NewGuid()}",
            new
            {
                protocolVersion = SyncProtocol.CurrentVersion,
                clientId = source,
                clientSequence = 1,
                operation = "setWaterIntake",
                resources = new object?[] { null },
                dependsOnMutationId = (Guid?)null,
                payload = new { waterIntakeDayId = Guid.NewGuid(), localDate = new DateOnly(2026, 10, 25), baseVersion = 0, amountMl = 250 },
            });

        Assert.AreEqual(HttpStatusCode.UnprocessableEntity, response.StatusCode, await response.Content.ReadAsStringAsync(TestContext.CancellationToken));
        Assert.AreEqual("invalid_resources", await ProblemCodeAsync(response));
    }

    private async Task<WebApplication> CreateApplicationAsync(TestTimeProvider? clock = null)
    {
        string connectionString = await Fixture.CreateIsolatedDatabaseAsync();
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString))
            await context.Database.MigrateAsync(TestContext.CancellationToken);

        string keyRingPath = Path.Combine(Path.GetTempPath(), $"gainer-sync-handover-api-{Guid.NewGuid():N}");
        keyRingPaths.Add(keyRingPath);
        var builder = WebApplication.CreateBuilder();
        builder.Logging.ClearProviders();
        builder.WebHost.UseTestServer();
        builder.Configuration["ConnectionStrings:gainer-db"] = connectionString;
        builder.Configuration[GainerIdentityOptions.DataProtectionKeysPathConfigurationKey] = keyRingPath;
        builder.AddGainerApi();
        builder.AddGainerPersistence();
        builder.AddGainerIdentity();
        if (clock is not null)
        {
            builder.Services.RemoveAll<TimeProvider>();
            builder.Services.AddSingleton<TimeProvider>(clock);
            // Handover expiry tests advance the clock past the access-token lifetime.
            builder.Services.PostConfigure<BearerTokenOptions>(
                GainerIdentityOptions.AuthenticationScheme,
                options => options.BearerTokenExpiration = TimeSpan.FromDays(1));
        }

        WebApplication app = builder.Build();
        app.MapGainerApi();
        await app.StartAsync(TestContext.CancellationToken);
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

    private static Task<TestSession> LoginAsync(HttpClient client, string email) =>
        TestSession.SignInAsync(client, email, Password);

    private static async Task RegisterAsync(
        HttpClient client,
        TestSession auth,
        Guid clientId,
        string displayName,
        bool takeOverWriting,
        HttpStatusCode expectedStatus,
        string? expectedCode = null,
        Guid? expectedAccountId = null)
    {
        using HttpResponseMessage response = await SendMutationAsync(
            client,
            auth,
            HttpMethod.Put,
            $"/api/v1/sync/clients/{clientId}",
            new RegisterSyncClientRequest(clientId, displayName, SyncProtocol.CurrentVersion, takeOverWriting),
            expectedAccountId);
        Assert.AreEqual(expectedStatus, response.StatusCode, await response.Content.ReadAsStringAsync());
        if (expectedCode is not null) Assert.AreEqual(expectedCode, await ProblemCodeAsync(response));
    }

    private static async Task<BeginSyncHandoverResponse> BeginAsync(
        HttpClient client,
        TestSession auth,
        BeginSyncHandoverRequest request)
    {
        using HttpResponseMessage response = await SendMutationAsync(
            client, auth, HttpMethod.Post, "/api/v1/sync/handovers", request);
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode, await response.Content.ReadAsStringAsync());
        return (await response.Content.ReadFromJsonAsync<BeginSyncHandoverResponse>())!;
    }

    private static async Task AssertCompletionRejectedAsync(
        HttpClient client,
        TestSession auth,
        BeginSyncHandoverResponse handover,
        string code,
        Guid targetClientId,
        string expectedProblemCode)
    {
        using HttpResponseMessage response = await SendMutationAsync(
            client,
            auth,
            HttpMethod.Post,
            $"/api/v1/sync/handovers/{handover.HandoverId}/complete",
            new CompleteSyncHandoverRequest(code, targetClientId, 0));
        Assert.AreEqual(HttpStatusCode.Conflict, response.StatusCode, await response.Content.ReadAsStringAsync());
        Assert.AreEqual(expectedProblemCode, await ProblemCodeAsync(response));
    }

    private static async Task<bool> IsActiveWriterAsync(HttpClient client, TestSession auth, Guid clientId)
    {
        using HttpResponseMessage response = await SendMutationAsync(
            client,
            auth,
            HttpMethod.Put,
            $"/api/v1/sync/clients/{clientId}",
            new RegisterSyncClientRequest(clientId, "Source", SyncProtocol.CurrentVersion, false));
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode, await response.Content.ReadAsStringAsync());
        SyncClientResponse result = (await response.Content.ReadFromJsonAsync<SyncClientResponse>())!;
        return result.IsActiveWriter;
    }

    private static async Task<CompleteSyncHandoverResponse> CompleteAsync(
        HttpClient client,
        TestSession auth,
        Guid handoverId,
        CompleteSyncHandoverRequest request)
    {
        using HttpResponseMessage response = await SendMutationAsync(
            client, auth, HttpMethod.Post, $"/api/v1/sync/handovers/{handoverId}/complete", request);
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode, await response.Content.ReadAsStringAsync());
        return (await response.Content.ReadFromJsonAsync<CompleteSyncHandoverResponse>())!;
    }

    private static async Task CancelAsync(HttpClient client, TestSession auth, Guid handoverId, Guid sourceClientId)
    {
        using HttpResponseMessage response = await SendMutationAsync(
            client,
            auth,
            HttpMethod.Post,
            $"/api/v1/sync/handovers/{handoverId}/cancel",
            new CancelSyncHandoverRequest(sourceClientId));
        Assert.AreEqual(HttpStatusCode.NoContent, response.StatusCode, await response.Content.ReadAsStringAsync());
    }

    private static async Task<HttpResponseMessage> SendMutationAsync<TBody>(
        HttpClient client,
        TestSession auth,
        HttpMethod method,
        string path,
        TBody body,
        Guid? expectedAccountId = null)
    {
        using var request = new HttpRequestMessage(method, path) { Content = JsonContent.Create(body) };
        if (expectedAccountId is Guid accountId)
            request.Headers.Add("X-Gainer-Account-Id", accountId.ToString("D"));
        auth.Apply(request);
        return await client.SendAsync(request);
    }

    private static async Task<string?> ProblemCodeAsync(HttpResponseMessage response)
    {
        using JsonDocument problem = await JsonDocument.ParseAsync(await response.Content.ReadAsStreamAsync());
        // Every problem carries the ids a support request needs.
        Assert.AreEqual(
            response.Headers.GetValues("X-Correlation-ID").Single(),
            problem.RootElement.GetProperty("correlationId").GetString());
        Assert.IsFalse(string.IsNullOrWhiteSpace(problem.RootElement.GetProperty("traceId").GetString()));
        return problem.RootElement.GetProperty("code").GetString();
    }

    private sealed class TestTimeProvider(DateTimeOffset utcNow) : TimeProvider
    {
        private DateTimeOffset current = utcNow;
        public override DateTimeOffset GetUtcNow() => current;
        public void Advance(TimeSpan value) => current += value;
    }

    public TestContext TestContext { get; set; } = null!;
}
