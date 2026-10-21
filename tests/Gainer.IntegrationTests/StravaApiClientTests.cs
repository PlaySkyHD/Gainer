using System.Net;
using System.Text;
using Gainer.Core.Integrations;
using Gainer.Infrastructure.Integrations;
using Microsoft.Extensions.Options;

namespace Gainer.IntegrationTests;

[TestClass]
public sealed class StravaApiClientTests
{
    [TestMethod]
    public async Task CodeExchangeSendsClientCredentialsAndReadsAthlete()
    {
        var handler = new RecordingHandler(_ => Json(HttpStatusCode.OK,
            """{"access_token":"a","refresh_token":"r","expires_at":1893456000,"athlete":{"id":7,"firstname":"Nic","lastname":"M"}}"""));
        StravaApiClient client = Client(handler);

        StravaTokens tokens = await client.ExchangeCodeAsync("the-code");

        Assert.AreEqual("a", tokens.AccessToken);
        Assert.AreEqual("r", tokens.RefreshToken);
        Assert.AreEqual(7, tokens.AthleteId);
        Assert.AreEqual("Nic M", tokens.AthleteName);
        Assert.AreEqual(new DateTime(2030, 1, 1, 0, 0, 0, DateTimeKind.Utc), tokens.ExpiresAtUtc);
        Assert.AreEqual("https://strava.test/oauth/token", handler.Requests[0].Uri);
        StringAssert.Contains(handler.Requests[0].Body, "grant_type=authorization_code");
        StringAssert.Contains(handler.Requests[0].Body, "client_id=123");
        StringAssert.Contains(handler.Requests[0].Body, "client_secret=secret");
        StringAssert.Contains(handler.Requests[0].Body, "code=the-code");
    }

    [TestMethod]
    public async Task RefreshWithoutAthleteAndRejectedRefreshAreDistinguished()
    {
        StravaTokens refreshed = await Client(new RecordingHandler(_ => Json(HttpStatusCode.OK,
            """{"access_token":"a2","refresh_token":"r2","expires_at":1893456000}"""))).RefreshAsync("r");
        Assert.AreEqual("a2", refreshed.AccessToken);
        Assert.IsNull(refreshed.AthleteId);

        StravaApiException rejected = await Assert.ThrowsExactlyAsync<StravaApiException>(() =>
            Client(new RecordingHandler(_ => Json(HttpStatusCode.BadRequest, "{}"))).RefreshAsync("r"));
        Assert.AreEqual(StravaFailure.Unauthorized, rejected.Failure);

        StravaApiException incomplete = await Assert.ThrowsExactlyAsync<StravaApiException>(() =>
            Client(new RecordingHandler(_ => Json(HttpStatusCode.OK, """{"access_token":"","refresh_token":"","expires_at":0}""")))
                .RefreshAsync("r"));
        Assert.AreEqual(StravaFailure.Transient, incomplete.Failure);
    }

    [TestMethod]
    public async Task UploadSendsMultipartTcxAndReadsTheUpload()
    {
        var handler = new RecordingHandler(_ => Json(HttpStatusCode.Created, """{"id":55,"error":null,"activity_id":null}"""));
        StravaUpload upload = new("gainer-cardio-x", "Ride", "Notes", Trainer: true, Encoding.UTF8.GetBytes("<tcx/>"), null);

        StravaUploadState state = await Client(handler).UploadAsync("token", upload);

        Assert.AreEqual(55, state.UploadId);
        Assert.IsTrue(state.IsProcessing);
        RecordedRequest request = handler.Requests.Single();
        Assert.AreEqual("https://strava.test/api/v3/uploads", request.Uri);
        Assert.AreEqual("Bearer token", request.Authorization);
        foreach (string part in new[] { "name=data_type", "tcx", "name=external_id", "gainer-cardio-x", "name=trainer", "name=description", "<tcx/>" })
        {
            StringAssert.Contains(request.Body, part);
        }
    }

    [TestMethod]
    public async Task UploadRejectedAsDuplicateReturnsTheExistingActivity()
    {
        var handler = new RecordingHandler(_ => Json(HttpStatusCode.BadRequest,
            """{"id":56,"error":"gainer-cardio-x.tcx duplicate of activity 4242","activity_id":null}"""));
        StravaUpload upload = new("gainer-cardio-x", "Ride", null, Trainer: false, [1], null);

        StravaUploadState state = await Client(handler).UploadAsync("token", upload);

        Assert.AreEqual(4242, state.DuplicateOfActivityId);
        Assert.IsFalse(state.IsProcessing);
    }

    [TestMethod]
    public async Task PollingSportTypeAndDeauthorizationUseTheirEndpoints()
    {
        var handler = new RecordingHandler(request => request.RequestUri!.AbsolutePath.EndsWith("/uploads/9", StringComparison.Ordinal)
            ? Json(HttpStatusCode.OK, """{"id":9,"error":null,"activity_id":77}""")
            : Json(HttpStatusCode.OK, "{}"));
        StravaApiClient client = Client(handler);

        StravaUploadState state = await client.GetUploadAsync("token", 9);
        await client.SetSportTypeAsync("token", 77, "WeightTraining");
        await client.DeauthorizeAsync("token");

        Assert.AreEqual(77, state.ActivityId);
        Assert.AreEqual("PUT https://strava.test/api/v3/activities/77", $"{handler.Requests[1].Method} {handler.Requests[1].Uri}");
        StringAssert.Contains(handler.Requests[1].Body, "\"sport_type\":\"WeightTraining\"");
        Assert.AreEqual("https://strava.test/oauth/deauthorize", handler.Requests[2].Uri);
    }

    [TestMethod]
    [DataRow(HttpStatusCode.Unauthorized, StravaFailure.Unauthorized)]
    [DataRow(HttpStatusCode.Forbidden, StravaFailure.Rejected)]
    [DataRow(HttpStatusCode.TooManyRequests, StravaFailure.RateLimited)]
    [DataRow(HttpStatusCode.ServiceUnavailable, StravaFailure.Transient)]
    [DataRow(HttpStatusCode.NotFound, StravaFailure.Rejected)]
    public async Task StatusCodesMapToFailures(HttpStatusCode status, StravaFailure expected)
    {
        StravaApiException exception = await Assert.ThrowsExactlyAsync<StravaApiException>(() =>
            Client(new RecordingHandler(_ => Json(status, "{}"))).GetUploadAsync("token", 1));
        Assert.AreEqual(expected, exception.Failure);
        Assert.AreEqual((int)status, exception.StatusCode);
    }

    [TestMethod]
    public async Task NetworkErrorsAndUnreadableBodiesAreTransient()
    {
        StravaApiException network = await Assert.ThrowsExactlyAsync<StravaApiException>(() =>
            Client(new RecordingHandler(_ => throw new HttpRequestException("down"))).GetUploadAsync("token", 1));
        Assert.AreEqual(StravaFailure.Transient, network.Failure);

        StravaApiException unreadable = await Assert.ThrowsExactlyAsync<StravaApiException>(() =>
            Client(new RecordingHandler(_ => Json(HttpStatusCode.OK, "not json"))).GetUploadAsync("token", 1));
        Assert.AreEqual(StravaFailure.Transient, unreadable.Failure);
    }

    [TestMethod]
    public void OptionsReadTheSecretFileAndDuplicateParserIgnoresOtherErrors()
    {
        string path = Path.GetTempFileName();
        try
        {
            File.WriteAllText(path, " from-file \n");
            var options = new StravaOptions { ClientId = "1", ClientSecretFile = path };
            Assert.IsTrue(options.IsConfigured);
            Assert.AreEqual("from-file", options.ResolveClientSecret());
            File.WriteAllText(path, string.Empty);
            Assert.IsFalse(options.IsConfigured);
            Assert.IsFalse(new StravaOptions { ClientId = "1", ClientSecretFile = path + ".missing" }.IsConfigured);
        }
        finally
        {
            File.Delete(path);
        }
        Assert.IsNull(StravaApiClient.ParseDuplicateActivityId("Improperly formatted data."));
        Assert.IsNull(StravaApiClient.ParseDuplicateActivityId(null));
    }

    private static StravaApiClient Client(RecordingHandler handler) => new(
        new HttpClient(handler),
        Options.Create(new StravaOptions
        {
            ClientId = "123",
            ClientSecret = "secret",
            OAuthBaseUrl = "https://strava.test/",
            ApiBaseUrl = "https://strava.test/api/v3/",
        }));

    private static HttpResponseMessage Json(HttpStatusCode status, string body) => new(status)
    {
        Content = new StringContent(body, Encoding.UTF8, "application/json"),
    };

    private sealed record RecordedRequest(string Method, string Uri, string? Authorization, string Body);

    private sealed class RecordingHandler(Func<HttpRequestMessage, HttpResponseMessage> respond) : HttpMessageHandler
    {
        public List<RecordedRequest> Requests { get; } = [];

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            string body = request.Content is null ? string.Empty : await request.Content.ReadAsStringAsync(cancellationToken);
            Requests.Add(new RecordedRequest(
                request.Method.Method,
                request.RequestUri!.AbsoluteUri,
                request.Headers.Authorization?.ToString(),
                body));
            return respond(request);
        }
    }
}
