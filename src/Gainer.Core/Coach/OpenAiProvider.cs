using System.Text.Json;

namespace Gainer.Core.Coach;

public interface IOpenAiResponsesProvider
{
    Task<JsonElement> CreateResponseAsync(JsonElement request, CancellationToken cancellationToken = default);
}

public sealed class OpenAiProviderException(
    string code,
    string message,
    int? statusCode = null,
    Exception? innerException = null) : Exception(message, innerException)
{
    public string Code { get; } = code;
    public int? StatusCode { get; } = statusCode;
}
