using System.Text.Json;
using Gainer.Api.Controllers;
using Gainer.Contracts.Sync;
using Gainer.Core.Mutations;
using Gainer.Core.Sync;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace Gainer.IntegrationTests;

[TestClass]
public sealed class SyncMutationsControllerTests
{
    [TestMethod]
    public async Task AppliedAndReplayResponsesAreStable200Results()
    {
        Guid mutationId = Guid.NewGuid();
        Guid resourceId = Guid.NewGuid();
        var processor = new StubProcessor(new ProcessedSyncMutationResult(
            mutationId,
            true,
            7,
            [new ExecutedSyncChange(ResourceKey.Create(ResourceKind.DailyCheckIn, resourceId), 2, new { version = 2 })]));
        SyncMutationsController controller = Controller(processor);
        ActionResult<PushMutationResponse> action = await controller.Push(
            mutationId, Request(resourceId), CancellationToken.None);

        OkObjectResult ok = (OkObjectResult)action.Result!;
        PushMutationResponse response = (PushMutationResponse)ok.Value!;
        Assert.AreEqual(StatusCodes.Status200OK, ok.StatusCode);
        Assert.IsTrue(response.Replayed);
        Assert.AreEqual(7, response.Revision);
        Assert.AreEqual(2, response.Resources[0].Version);
    }

    [TestMethod]
    public async Task ConflictUpgradeAndValidationMapToStableProblemCodes()
    {
        await AssertProblemAsync(new SyncMutationConflictException("stale_base_version", "conflict"), 409, "stale_base_version");
        await AssertProblemAsync(new SyncUpgradeRequiredException(), 409, "upgrade_required");
        await AssertProblemAsync(new SyncMutationValidationException("invalid_payload", "invalid"), 422, "invalid_payload");
    }

    [TestMethod]
    public void EndpointRequiresAuthorizationAndUnsafeRequestsRemainUnderGlobalCsrfFilter()
    {
        Assert.IsNotNull(typeof(SyncMutationsController).GetCustomAttributes(typeof(AuthorizeAttribute), inherit: true).SingleOrDefault());
        HttpPutAttribute route = typeof(SyncMutationsController).GetMethod(nameof(SyncMutationsController.Push))!
            .GetCustomAttributes(typeof(HttpPutAttribute), inherit: true).Cast<HttpPutAttribute>().Single();
        Assert.AreEqual("{mutationId:guid}", route.Template);
    }

    private static async Task AssertProblemAsync(Exception exception, int status, string code)
    {
        SyncMutationsController controller = Controller(new StubProcessor(exception));
        ActionResult<PushMutationResponse> action = await controller.Push(
            Guid.NewGuid(), Request(Guid.NewGuid()), CancellationToken.None);
        ObjectResult result = (ObjectResult)action.Result!;
        ProblemDetails problem = (ProblemDetails)result.Value!;
        Assert.AreEqual(status, result.StatusCode);
        Assert.AreEqual(code, problem.Extensions["code"]);
    }

    private static SyncMutationsController Controller(ISyncMutationProcessor processor) => new(processor)
    {
        ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
    };

    private static PushMutationRequest Request(Guid resourceId) => new(
        2,
        Guid.NewGuid(),
        1,
        "createDailyCheckIn",
        [new ResourceVersionRequest("DailyCheckIn", resourceId, 0)],
        null,
        JsonDocument.Parse("{}").RootElement.Clone());

    private sealed class StubProcessor : ISyncMutationProcessor
    {
        private readonly ProcessedSyncMutationResult? result;
        private readonly Exception? exception;
        public StubProcessor(ProcessedSyncMutationResult result) => this.result = result;
        public StubProcessor(Exception exception) => this.exception = exception;
        public Task<ProcessedSyncMutationResult> ProcessAsync(ProcessSyncMutationCommand command, CancellationToken cancellationToken = default)
        {
            _ = command; _ = cancellationToken;
            return exception is not null
                ? Task.FromException<ProcessedSyncMutationResult>(exception)
                : Task.FromResult(result!);
        }
    }
}
