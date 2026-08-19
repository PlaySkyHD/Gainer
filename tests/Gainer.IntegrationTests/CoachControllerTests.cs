using Gainer.Api.Controllers;
using Gainer.Contracts.Coach;
using Gainer.Core.Coach;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

namespace Gainer.IntegrationTests;

[TestClass]
public sealed class CoachControllerTests
{
    [TestMethod]
    public async Task SuccessReturnsOnlyStructuredFactsAndEvidence()
    {
        var answer = new CoachAnswer(
            "Summary",
            [new CoachObservation("Observed", ["fact-1"])],
            [new CoachFact("fact-1", "weight", "Average", 80m, null, "kg", "30 days", "weight-average-v1")],
            ["gap"], ["continue observing"], 3);
        ActionResult<CoachResponse> action = await new CoachController(new StubCoach(answer)).Create(
            new CoachResponseRequest("question"), CancellationToken.None);
        CoachResponse response = (CoachResponse)((OkObjectResult)action.Result!).Value!;
        Assert.AreEqual(3, response.AsOfRevision);
        Assert.AreEqual("fact-1", response.Facts.Single().FactId);
    }

    [TestMethod]
    public async Task ProviderFailuresMapToRetryableStableStatusCodes()
    {
        ObjectResult limited = await Failure(new OpenAiProviderException("provider_rate_limited", "later", 429));
        Assert.AreEqual(StatusCodes.Status429TooManyRequests, limited.StatusCode);
        ObjectResult timeout = await Failure(new OpenAiProviderException("provider_timeout", "timeout"));
        Assert.AreEqual(StatusCodes.Status503ServiceUnavailable, timeout.StatusCode);
        ObjectResult invalid = await Failure(new CoachResponseValidationException("invalid"));
        Assert.AreEqual(StatusCodes.Status502BadGateway, invalid.StatusCode);
    }

    [TestMethod]
    public void EndpointRequiresAuthenticationRateLimitAndUnsafePost()
    {
        Assert.IsNotNull(typeof(CoachController).GetCustomAttributes(typeof(AuthorizeAttribute), true).SingleOrDefault());
        EnableRateLimitingAttribute rate = (EnableRateLimitingAttribute)typeof(CoachController)
            .GetCustomAttributes(typeof(EnableRateLimitingAttribute), true).Single();
        Assert.AreEqual("coach", rate.PolicyName);
        Assert.IsNotNull(typeof(CoachController).GetMethod(nameof(CoachController.Create))!
            .GetCustomAttributes(typeof(HttpPostAttribute), true).SingleOrDefault());
    }

    private static async Task<ObjectResult> Failure(Exception exception)
    {
        ActionResult<CoachResponse> action = await new CoachController(new StubCoach(exception)).Create(
            new CoachResponseRequest("question"), CancellationToken.None);
        return (ObjectResult)action.Result!;
    }

    private sealed class StubCoach : ICoachService
    {
        private readonly CoachAnswer? answer;
        private readonly Exception? exception;
        public StubCoach(CoachAnswer answer) => this.answer = answer;
        public StubCoach(Exception exception) => this.exception = exception;
        public Task<CoachAnswer> AnswerAsync(string question, CancellationToken cancellationToken = default) =>
            exception is null ? Task.FromResult(answer!) : Task.FromException<CoachAnswer>(exception);
    }
}
