using Gainer.Api.Controllers;
using Gainer.Contracts.Integrations;
using Gainer.Core.Integrations;
using Gainer.Infrastructure.Integrations;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;

namespace Gainer.IntegrationTests;

[TestClass]
public sealed class StravaControllerTests
{
    private static readonly Guid Resource = Guid.Parse("11111111-2222-4333-8444-555555555555");

    [TestMethod]
    public void OnlyTheCallbackIsAnonymous()
    {
        Assert.IsNotNull(typeof(StravaController).GetCustomAttributes(typeof(AuthorizeAttribute), true).SingleOrDefault());
        Assert.IsNotNull(typeof(StravaController).GetMethod(nameof(StravaController.Callback))!
            .GetCustomAttributes(typeof(AllowAnonymousAttribute), true).SingleOrDefault());
        Assert.IsFalse(typeof(StravaController).GetMethods()
            .Where(method => method.Name != nameof(StravaController.Callback))
            .Any(method => method.GetCustomAttributes(typeof(AllowAnonymousAttribute), true).Length > 0));
    }

    [TestMethod]
    public async Task StatusSettingsAndDisconnectMapTheService()
    {
        var service = new StubService();
        StravaController controller = Controller(service);

        StravaStatusResponse status = Ok(await controller.GetStatus());
        Assert.IsTrue(status.Connected);
        Assert.AreEqual("Nic", status.AthleteName);

        StravaStatusResponse updated = Ok(await controller.UpdateSettings(new StravaSettingsRequest(false, true)));
        Assert.IsFalse(updated.ExportCardio);
        Assert.IsTrue(updated.ExportStrength);

        Assert.IsInstanceOfType<NoContentResult>(await controller.Disconnect());
        Assert.IsTrue(service.Disconnected);
    }

    [TestMethod]
    public void AuthorizationUsesTheConfiguredOrDerivedCallback()
    {
        var service = new StubService();
        Ok(Controller(service, callbackUrl: "https://configured.test/cb").BeginAuthorization());
        Assert.AreEqual("https://configured.test/cb", service.CallbackUrl);

        StravaAuthorizationResponse derived = Ok(Controller(service).BeginAuthorization());
        Assert.AreEqual("https://gainer.test/api/v1/integrations/strava/callback", service.CallbackUrl);
        Assert.AreEqual("https://strava.test/authorize", derived.AuthorizationUrl);

        service.Failure = new StravaIntegrationException(StravaIntegrationException.NotConfigured, "off", 503);
        ObjectResult problem = (ObjectResult)Controller(service).BeginAuthorization().Result!;
        Assert.AreEqual(StatusCodes.Status503ServiceUnavailable, problem.StatusCode);
        Assert.AreEqual(StravaIntegrationException.NotConfigured, ((ProblemDetails)problem.Value!).Extensions["code"]);
    }

    [TestMethod]
    [DataRow(StravaAuthorizationResult.Connected, "connected")]
    [DataRow(StravaAuthorizationResult.Denied, "denied")]
    [DataRow(StravaAuthorizationResult.Failed, "failed")]
    public async Task CallbackRedirectsBackToTheApp(StravaAuthorizationResult result, string expected)
    {
        var service = new StubService { AuthorizationResult = result };

        RedirectResult redirect = (RedirectResult)await Controller(service).Callback("state", "code", "activity:write", null);

        Assert.AreEqual($"gainer://strava?result={expected}", redirect.Url);
    }

    [TestMethod]
    public async Task ExportsMapKindsStatesAndProblems()
    {
        var service = new StubService();
        StravaController controller = Controller(service);

        Assert.IsInstanceOfType<NotFoundResult>((await controller.GetExport("cardio", Resource)).Result);
        Assert.IsInstanceOfType<NotFoundResult>((await controller.GetExport("yoga", Resource)).Result);
        Assert.IsInstanceOfType<NotFoundResult>((await controller.RequestExport("yoga", Resource)).Result);

        AcceptedResult accepted = (AcceptedResult)(await controller.RequestExport("strength", Resource)).Result!;
        StravaExportResponse queued = (StravaExportResponse)accepted.Value!;
        Assert.AreEqual("strength", queued.Kind);
        Assert.AreEqual("pending", queued.Status);

        service.Export = service.Export! with { Status = StravaExportStatus.Completed, ActivityId = 9 };
        StravaExportResponse completed = Ok(await controller.GetExport("strength", Resource));
        Assert.AreEqual("completed", completed.Status);
        Assert.AreEqual(9, completed.ActivityId);

        service.Failure = new StravaIntegrationException(StravaIntegrationException.ResourceNotFound, "missing", 404);
        ObjectResult problem = (ObjectResult)(await controller.RequestExport("cardio", Resource)).Result!;
        Assert.AreEqual(StatusCodes.Status404NotFound, problem.StatusCode);
    }

    [TestMethod]
    public void WireNamesCoverEveryValue()
    {
        Assert.AreEqual("processing", StravaExportNames.ToWire(StravaExportStatus.Processing));
        Assert.AreEqual("failed", StravaExportNames.ToWire(StravaExportStatus.Failed));
        Assert.AreEqual("cardio", StravaExportNames.ToWire(StravaExportKind.Cardio));
        Assert.IsTrue(StravaExportNames.TryParseKind("cardio", out StravaExportKind kind));
        Assert.AreEqual(StravaExportKind.Cardio, kind);
        Assert.ThrowsExactly<ArgumentOutOfRangeException>(() => StravaExportNames.ToWire((StravaExportStatus)99));
        Assert.ThrowsExactly<ArgumentOutOfRangeException>(() => StravaExportNames.ToWire((StravaExportKind)99));
    }

    [TestMethod]
    public async Task BackgroundScopeBindsOneUserAndSignalWakesEarly()
    {
        var scope = new BackgroundUserScope();
        Guid user = Guid.NewGuid();
        scope.Enter(user);
        scope.Enter(user);
        Assert.AreEqual(user, scope.UserId);
        Assert.ThrowsExactly<InvalidOperationException>(() => scope.Enter(Guid.NewGuid()));
        Assert.ThrowsExactly<ArgumentException>(() => new BackgroundUserScope().Enter(Guid.Empty));

        var signal = new StravaExportSignal();
        signal.Notify();
        signal.Notify();
        Task waited = signal.WaitAsync(TimeSpan.FromMinutes(5), CancellationToken.None);
        Assert.AreSame(waited, await Task.WhenAny(waited, Task.Delay(TimeSpan.FromSeconds(5))));
    }

    private static T Ok<T>(ActionResult<T> result) => (T)((ObjectResult)result.Result!).Value!;

    private static StravaController Controller(StubService service, string? callbackUrl = null)
    {
        var controller = new StravaController(service, Options.Create(new StravaOptions { CallbackUrl = callbackUrl }));
        var context = new DefaultHttpContext();
        context.Request.Scheme = "https";
        context.Request.Host = new HostString("gainer.test");
        controller.ControllerContext = new ControllerContext { HttpContext = context };
        return controller;
    }

    private sealed class StubService : IStravaIntegrationService
    {
        private StravaStatus status = new(true, true, false, "Nic", true, false);

        public StravaIntegrationException? Failure { get; set; }
        public StravaAuthorizationResult AuthorizationResult { get; set; }
        public StravaExportState? Export { get; set; }
        public string? CallbackUrl { get; private set; }
        public bool Disconnected { get; private set; }

        public Task<StravaStatus> GetStatusAsync(CancellationToken cancellationToken = default) => Task.FromResult(status);

        public string BeginAuthorization(string callbackUrl)
        {
            if (Failure is not null) throw Failure;
            CallbackUrl = callbackUrl;
            return "https://strava.test/authorize";
        }

        public Task<StravaAuthorizationResult> CompleteAuthorizationAsync(
            string? state, string? code, string? scope, string? error, string callbackUrl, CancellationToken cancellationToken = default) =>
            Task.FromResult(AuthorizationResult);

        public Task<StravaStatus> UpdateSettingsAsync(bool exportCardio, bool exportStrength, CancellationToken cancellationToken = default)
        {
            status = status with { ExportCardio = exportCardio, ExportStrength = exportStrength };
            return Task.FromResult(status);
        }

        public Task DisconnectAsync(CancellationToken cancellationToken = default)
        {
            Disconnected = true;
            return Task.CompletedTask;
        }

        public Task<StravaExportState?> GetExportAsync(StravaExportKind kind, Guid resourceId, CancellationToken cancellationToken = default) =>
            Task.FromResult(Export);

        public Task<StravaExportState> RequestExportAsync(StravaExportKind kind, Guid resourceId, CancellationToken cancellationToken = default)
        {
            if (Failure is not null) throw Failure;
            Export = new StravaExportState(kind, resourceId, StravaExportStatus.Pending, null, null, DateTime.UtcNow);
            return Task.FromResult(Export);
        }
    }
}
