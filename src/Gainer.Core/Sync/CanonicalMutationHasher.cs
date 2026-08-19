using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Gainer.Core.Sync;

public sealed record CanonicalResourceVersion(string ResourceType, Guid ResourceId, long BaseVersion);

public sealed record CanonicalMutationContent(
    int ProtocolVersion,
    Guid ClientId,
    long ClientSequence,
    string Operation,
    IReadOnlyList<CanonicalResourceVersion> Resources,
    Guid? DependsOnMutationId,
    JsonElement Payload);

public static class CanonicalMutationHasher
{
    public static byte[] Serialize(CanonicalMutationContent mutation)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        using var buffer = new MemoryStream();
        using (var writer = new Utf8JsonWriter(buffer, new JsonWriterOptions { Indented = false }))
        {
            writer.WriteStartObject();
            writer.WriteString("clientId", mutation.ClientId.ToString("D"));
            writer.WriteNumber("clientSequence", mutation.ClientSequence);
            if (mutation.DependsOnMutationId is { } dependency) writer.WriteString("dependsOnMutationId", dependency.ToString("D"));
            else writer.WriteNull("dependsOnMutationId");
            writer.WriteString("operation", mutation.Operation);
            writer.WritePropertyName("payload");
            WriteCanonicalElement(writer, mutation.Payload);
            writer.WriteNumber("protocolVersion", mutation.ProtocolVersion);
            writer.WritePropertyName("resources");
            writer.WriteStartArray();
            foreach (CanonicalResourceVersion resource in mutation.Resources)
            {
                writer.WriteStartObject();
                writer.WriteNumber("baseVersion", resource.BaseVersion);
                writer.WriteString("resourceId", resource.ResourceId.ToString("D"));
                writer.WriteString("resourceType", resource.ResourceType);
                writer.WriteEndObject();
            }
            writer.WriteEndArray();
            writer.WriteEndObject();
        }
        return buffer.ToArray();
    }

    public static byte[] Hash(CanonicalMutationContent mutation) => SHA256.HashData(Serialize(mutation));

    public static string HashHex(CanonicalMutationContent mutation) =>
        Convert.ToHexStringLower(Hash(mutation));

    private static void WriteCanonicalElement(Utf8JsonWriter writer, JsonElement element)
    {
        switch (element.ValueKind)
        {
            case JsonValueKind.Object:
                JsonProperty[] properties = element.EnumerateObject().OrderBy(item => item.Name, StringComparer.Ordinal).ToArray();
                if (properties.Select(item => item.Name).Distinct(StringComparer.Ordinal).Count() != properties.Length)
                {
                    throw new InvalidOperationException("Canonical JSON cannot contain duplicate object keys.");
                }
                writer.WriteStartObject();
                foreach (JsonProperty property in properties)
                {
                    writer.WritePropertyName(property.Name);
                    WriteCanonicalElement(writer, property.Value);
                }
                writer.WriteEndObject();
                break;
            case JsonValueKind.Array:
                writer.WriteStartArray();
                foreach (JsonElement item in element.EnumerateArray()) WriteCanonicalElement(writer, item);
                writer.WriteEndArray();
                break;
            case JsonValueKind.String:
                writer.WriteStringValue(element.GetString());
                break;
            case JsonValueKind.Number:
                string raw = element.GetRawText();
                if (!decimal.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out decimal number))
                {
                    throw new InvalidOperationException("Mutation numbers must fit the canonical decimal range.");
                }
                string normalized = number == 0
                    ? "0"
                    : number.ToString("0.############################", CultureInfo.InvariantCulture);
                writer.WriteRawValue(normalized, skipInputValidation: false);
                break;
            case JsonValueKind.True:
                writer.WriteBooleanValue(true);
                break;
            case JsonValueKind.False:
                writer.WriteBooleanValue(false);
                break;
            case JsonValueKind.Null:
                writer.WriteNullValue();
                break;
            default:
                throw new InvalidOperationException("The mutation payload contains an unsupported JSON token.");
        }
    }
}
