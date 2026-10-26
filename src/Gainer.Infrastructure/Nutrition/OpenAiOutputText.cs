using System.Text.Json;

namespace Gainer.Infrastructure.Nutrition;

/// <summary>Reads the structured output text of an OpenAI response without throwing on unexpected shapes.</summary>
internal static class OpenAiOutputText
{
    /// <exception cref="JsonException">The response has no <c>output</c> array or no non-empty output text.</exception>
    public static string Read(JsonElement response)
    {
        if (response.ValueKind != JsonValueKind.Object ||
            !response.TryGetProperty("output", out JsonElement output) ||
            output.ValueKind != JsonValueKind.Array)
            throw new JsonException("The response has no output array.");
        foreach (JsonElement message in output.EnumerateArray())
        {
            if (!IsType(message, "message") ||
                !message.TryGetProperty("content", out JsonElement content) ||
                content.ValueKind != JsonValueKind.Array)
                continue;
            foreach (JsonElement part in content.EnumerateArray())
            {
                if (IsType(part, "output_text") &&
                    part.TryGetProperty("text", out JsonElement text) &&
                    text.ValueKind == JsonValueKind.String &&
                    text.GetString() is { } value &&
                    !string.IsNullOrWhiteSpace(value))
                    return value;
            }
        }
        throw new JsonException("The response contains no output text.");
    }

    private static bool IsType(JsonElement item, string type) =>
        item.ValueKind == JsonValueKind.Object &&
        item.TryGetProperty("type", out JsonElement value) &&
        value.ValueKind == JsonValueKind.String &&
        value.GetString() == type;
}
