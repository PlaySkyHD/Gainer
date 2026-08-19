using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Gainer.Core.Coach;
using Microsoft.Extensions.Options;
using Microsoft.Extensions.Logging;

namespace Gainer.Infrastructure.Coach;

public sealed class OpenAiProviderOptions
{
    public const string SectionName = "OpenAI";
    public string ApiKey { get; set; } = string.Empty;
    public string? ApiKeyFile { get; set; }
    public string Model { get; set; } = "gpt-5.4-mini";
    public int TimeoutSeconds { get; set; } = 30;
    public int MaxOutputTokens { get; set; } = 1200;
}

public sealed class OpenAiResponsesProvider(
    HttpClient httpClient,
    IOptions<OpenAiProviderOptions> options,
    ILogger<OpenAiResponsesProvider> logger) : IOpenAiResponsesProvider
{
    private readonly OpenAiProviderOptions settings = Validate(options.Value);

    public async Task<JsonElement> CreateResponseAsync(
        JsonElement request,
        CancellationToken cancellationToken = default)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(settings.TimeoutSeconds));
        using var message = new HttpRequestMessage(HttpMethod.Post, "v1/responses")
        {
            Content = JsonContent.Create(ForceSafeEnvelope(request)),
        };
        message.Headers.Authorization = new AuthenticationHeaderValue("Bearer", settings.ApiKey);
        try
        {
            using HttpResponseMessage response = await httpClient.SendAsync(message, HttpCompletionOption.ResponseHeadersRead, timeout.Token);
            if (!response.IsSuccessStatusCode)
            {
                throw new OpenAiProviderException(
                    response.StatusCode == System.Net.HttpStatusCode.TooManyRequests ? "provider_rate_limited" : "provider_error",
                    "The AI provider request failed.",
                    (int)response.StatusCode);
            }
            using Stream stream = await response.Content.ReadAsStreamAsync(timeout.Token);
            using JsonDocument document = await JsonDocument.ParseAsync(stream, cancellationToken: timeout.Token);
            LogUsage(document.RootElement);
            return document.RootElement.Clone();
        }
        catch (OperationCanceledException exception) when (!cancellationToken.IsCancellationRequested)
        {
            throw new OpenAiProviderException("provider_timeout", "The AI provider timed out.", innerException: exception);
        }
        catch (HttpRequestException exception)
        {
            throw new OpenAiProviderException("provider_unavailable", "The AI provider is unavailable.", innerException: exception);
        }
        catch (JsonException exception)
        {
            throw new OpenAiProviderException("invalid_provider_response", "The AI provider returned invalid JSON.", innerException: exception);
        }
    }

    private void LogUsage(JsonElement response)
    {
        int? inputTokens = response.TryGetProperty("usage", out JsonElement usage) &&
            usage.TryGetProperty("input_tokens", out JsonElement input) ? input.GetInt32() : null;
        int? outputTokens = response.TryGetProperty("usage", out usage) &&
            usage.TryGetProperty("output_tokens", out JsonElement output) ? output.GetInt32() : null;
        logger.LogInformation(
            "OpenAI Responses call completed for model {Model}; input tokens {InputTokens}; output tokens {OutputTokens}",
            settings.Model,
            inputTokens,
            outputTokens);
    }

    private JsonElement ForceSafeEnvelope(JsonElement request)
    {
        var envelope = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(request.GetRawText())
            ?? throw new ArgumentException("The provider request is invalid.", nameof(request));
        envelope["model"] = JsonSerializer.SerializeToElement(settings.Model);
        envelope["store"] = JsonSerializer.SerializeToElement(false);
        envelope["background"] = JsonSerializer.SerializeToElement(false);
        envelope["max_output_tokens"] = JsonSerializer.SerializeToElement(settings.MaxOutputTokens);
        envelope.Remove("previous_response_id");
        envelope.Remove("conversation");
        envelope.Remove("include");
        return JsonSerializer.SerializeToElement(envelope);
    }

    private static OpenAiProviderOptions Validate(OpenAiProviderOptions value)
    {
        if (string.IsNullOrWhiteSpace(value.ApiKey) && !string.IsNullOrWhiteSpace(value.ApiKeyFile))
        {
            if (!File.Exists(value.ApiKeyFile)) throw new InvalidOperationException("The configured OpenAI key file does not exist.");
            value.ApiKey = File.ReadAllText(value.ApiKeyFile).Trim();
        }
        if (string.IsNullOrWhiteSpace(value.ApiKey)) throw new InvalidOperationException("OpenAI:ApiKey is required.");
        if (string.IsNullOrWhiteSpace(value.Model)) throw new InvalidOperationException("OpenAI:Model is required.");
        if (value.TimeoutSeconds is < 1 or > 120) throw new InvalidOperationException("OpenAI timeout is invalid.");
        if (value.MaxOutputTokens is < 128 or > 8_000) throw new InvalidOperationException("OpenAI output token limit is invalid.");
        return value;
    }
}
