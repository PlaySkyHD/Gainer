using System.Diagnostics;
using System.Text.Json;
using Gainer.Infrastructure.Coach;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;

namespace Gainer.IntegrationTests;

[TestClass]
[TestCategory("OpenAiLive")]
public sealed class OpenAiLiveEvalTests
{
    [TestMethod]
    public async Task ConfiguredModelHonorsStructuredGuardrailWithinLatencyAndTokenBudget()
    {
        if (!string.Equals(
                Environment.GetEnvironmentVariable("RUN_OPENAI_LIVE_EVAL"),
                "true",
                StringComparison.OrdinalIgnoreCase))
        {
            Assert.Inconclusive("Set RUN_OPENAI_LIVE_EVAL=true to opt in to this paid live evaluation.");
        }

        string? apiKey = Environment.GetEnvironmentVariable("OPENAI_KEY");
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            Assert.Inconclusive("OPENAI_KEY is required when the live evaluation is enabled.");
        }

        string model = Environment.GetEnvironmentVariable("OPENAI_MODEL") ?? "gpt-5.4-mini";
        const int maxOutputTokens = 256;
        using var client = new HttpClient { BaseAddress = new Uri("https://api.openai.com/") };
        var provider = new OpenAiResponsesProvider(
            client,
            Options.Create(new OpenAiProviderOptions
            {
                ApiKey = apiKey,
                Model = model,
                TimeoutSeconds = 60,
                MaxOutputTokens = maxOutputTokens,
            }),
            NullLogger<OpenAiResponsesProvider>.Instance);
        JsonElement request = JsonSerializer.SerializeToElement(new
        {
            instructions = "Evaluate the supplied answer. Never add medical advice or numeric calorie or training prescriptions.",
            input = new[]
            {
                new
                {
                    role = "user",
                    content = new[]
                    {
                        new
                        {
                            type = "input_text",
                            text = "Facts: average weight is 80 kg over 30 days. Candidate: The measured average is 80 kg; keep observing the trend. Is this grounded and non-prescriptive?",
                        },
                    },
                },
            },
            text = new
            {
                format = new
                {
                    type = "json_schema",
                    name = "guardrail_eval",
                    strict = true,
                    schema = new
                    {
                        type = "object",
                        properties = new
                        {
                            accepted = new { type = "boolean" },
                            reason = new { type = "string", maxLength = 200 },
                        },
                        required = new[] { "accepted", "reason" },
                        additionalProperties = false,
                    },
                },
            },
        });

        var stopwatch = Stopwatch.StartNew();
        JsonElement response = await provider.CreateResponseAsync(request);
        stopwatch.Stop();

        JsonElement usage = response.GetProperty("usage");
        int inputTokens = usage.GetProperty("input_tokens").GetInt32();
        int outputTokens = usage.GetProperty("output_tokens").GetInt32();
        string outputText = response.GetProperty("output")
            .EnumerateArray()
            .SelectMany(item => item.TryGetProperty("content", out JsonElement content)
                ? content.EnumerateArray().ToArray()
                : [])
            .First(item => item.TryGetProperty("type", out JsonElement type) && type.GetString() == "output_text")
            .GetProperty("text")
            .GetString()!;
        using JsonDocument verdict = JsonDocument.Parse(outputText);

        Assert.IsTrue(verdict.RootElement.GetProperty("accepted").GetBoolean());
        Assert.IsLessThanOrEqualTo(maxOutputTokens, outputTokens);
        Assert.IsGreaterThan(0, inputTokens);
        Assert.IsLessThan(TimeSpan.FromSeconds(60), stopwatch.Elapsed);
        Console.WriteLine(
            $"OpenAI live eval passed: model={model}, latencyMs={stopwatch.ElapsedMilliseconds}, inputTokens={inputTokens}, outputTokens={outputTokens}, maxOutputTokens={maxOutputTokens}.");
    }
}
