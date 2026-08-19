using System.Net;
using System.Text;
using System.Text.Json;
using Gainer.Infrastructure.Coach;
using Gainer.Core.Coach;
using Microsoft.Extensions.Options;
using Microsoft.Extensions.Logging.Abstractions;

namespace Gainer.IntegrationTests;

[TestClass]
public sealed class OpenAiResponsesProviderTests
{
    [TestMethod]
    public async Task AdapterForcesStatelessBoundedResponsesRequestWithoutHostedTools()
    {
        var handler = new CaptureHandler();
        using var client = new HttpClient(handler) { BaseAddress = new Uri("https://api.openai.test/") };
        var provider = new OpenAiResponsesProvider(client, Options.Create(new OpenAiProviderOptions
        {
            ApiKey = "secret-test-key",
            Model = "configured-model",
            TimeoutSeconds = 1,
            MaxOutputTokens = 700,
        }), NullLogger<OpenAiResponsesProvider>.Instance);
        JsonElement request = JsonSerializer.SerializeToElement(new
        {
            model = "untrusted-model",
            store = true,
            background = true,
            previous_response_id = "must-be-removed",
            conversation = "must-be-removed",
            input = new[] { new { role = "user", content = "question" } },
            tools = new[] { new { type = "function", name = "get_progress" } },
        });
        _ = await provider.CreateResponseAsync(request);

        using JsonDocument sent = JsonDocument.Parse(handler.Body!);
        JsonElement root = sent.RootElement;
        Assert.AreEqual("configured-model", root.GetProperty("model").GetString());
        Assert.IsFalse(root.GetProperty("store").GetBoolean());
        Assert.IsFalse(root.GetProperty("background").GetBoolean());
        Assert.AreEqual(700, root.GetProperty("max_output_tokens").GetInt32());
        Assert.IsFalse(root.TryGetProperty("previous_response_id", out _));
        Assert.IsFalse(root.TryGetProperty("conversation", out _));
        Assert.AreEqual("Bearer", handler.AuthorizationScheme);
        Assert.AreEqual("secret-test-key", handler.AuthorizationParameter);
        Assert.AreEqual("function", root.GetProperty("tools")[0].GetProperty("type").GetString());
    }

    [TestMethod]
    public async Task ProviderRateLimitAndInvalidJsonMapToStableFailures()
    {
        var limited = new CaptureHandler(HttpStatusCode.TooManyRequests, "{}");
        OpenAiProviderException rate = await Assert.ThrowsAsync<OpenAiProviderException>(() => Provider(limited).CreateResponseAsync(
            JsonSerializer.SerializeToElement(new { input = Array.Empty<object>() })));
        Assert.AreEqual("provider_rate_limited", rate.Code);
        Assert.AreEqual(429, rate.StatusCode);

        var invalid = new CaptureHandler(HttpStatusCode.OK, "not-json");
        OpenAiProviderException json = await Assert.ThrowsAsync<OpenAiProviderException>(() => Provider(invalid).CreateResponseAsync(
            JsonSerializer.SerializeToElement(new { input = Array.Empty<object>() })));
        Assert.AreEqual("invalid_provider_response", json.Code);
    }

    [TestMethod]
    public async Task ProviderTimeoutAndServerFailureMapToRetryableFailures()
    {
        OpenAiProviderException timeout = await Assert.ThrowsAsync<OpenAiProviderException>(() =>
            Provider(new DelayedHandler()).CreateResponseAsync(
                JsonSerializer.SerializeToElement(new { input = Array.Empty<object>() })));
        Assert.AreEqual("provider_timeout", timeout.Code);

        OpenAiProviderException server = await Assert.ThrowsAsync<OpenAiProviderException>(() =>
            Provider(new CaptureHandler(HttpStatusCode.BadGateway, "{}"))
                .CreateResponseAsync(JsonSerializer.SerializeToElement(new { input = Array.Empty<object>() })));
        Assert.AreEqual("provider_error", server.Code);
        Assert.AreEqual(502, server.StatusCode);
    }

    private static OpenAiResponsesProvider Provider(HttpMessageHandler handler)
    {
        var client = new HttpClient(handler) { BaseAddress = new Uri("https://api.openai.test/") };
        return new OpenAiResponsesProvider(client, Options.Create(new OpenAiProviderOptions
        {
            ApiKey = "secret-test-key",
            Model = "configured-model",
            TimeoutSeconds = 1,
            MaxOutputTokens = 700,
        }), NullLogger<OpenAiResponsesProvider>.Instance);
    }

    private sealed class CaptureHandler(
        HttpStatusCode statusCode = HttpStatusCode.OK,
        string responseBody = "{\"id\":\"resp_test\",\"output\":[]}") : HttpMessageHandler
    {
        public string? Body { get; private set; }
        public string? AuthorizationScheme { get; private set; }
        public string? AuthorizationParameter { get; private set; }

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Body = await request.Content!.ReadAsStringAsync(cancellationToken);
            AuthorizationScheme = request.Headers.Authorization?.Scheme;
            AuthorizationParameter = request.Headers.Authorization?.Parameter;
            return new HttpResponseMessage(statusCode)
            {
                Content = new StringContent(responseBody, Encoding.UTF8, "application/json"),
            };
        }
    }

    private sealed class DelayedHandler : HttpMessageHandler
    {
        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            _ = request;
            await Task.Delay(TimeSpan.FromSeconds(10), cancellationToken);
            return new HttpResponseMessage(HttpStatusCode.OK);
        }
    }
}
