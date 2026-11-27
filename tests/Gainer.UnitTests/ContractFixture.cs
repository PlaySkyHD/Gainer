using System.Globalization;
using System.Text.Json;
using Gainer.Core.Insights;

namespace Gainer.UnitTests;

/// <summary>
/// Reads the shared fixtures under contracts/fixtures (copied to the output directory) that the app tests too, so
/// server and app compute the same figures.
/// </summary>
internal static class ContractFixture
{
    public static IEnumerable<object[]> CaseNames(string fileName) =>
        Cases(fileName).Select(item => new object[] { item.GetProperty("name").GetString()! });

    public static JsonElement Case(string fileName, string caseName) =>
        Cases(fileName).Single(item => item.GetProperty("name").GetString() == caseName);

    public static DateOnly Date(JsonElement value) =>
        DateOnly.ParseExact(value.GetString()!, "yyyy-MM-dd", CultureInfo.InvariantCulture);

    public static DateTime Utc(JsonElement value) =>
        DateTimeOffset.Parse(value.GetString()!, CultureInfo.InvariantCulture).UtcDateTime;

    public static DateTime? OptionalUtc(JsonElement item, string name) =>
        item.TryGetProperty(name, out JsonElement value) && value.ValueKind == JsonValueKind.String ? Utc(value) : null;

    public static decimal? OptionalDecimal(JsonElement item, string name) =>
        item.TryGetProperty(name, out JsonElement value) && value.ValueKind == JsonValueKind.Number ? value.GetDecimal() : null;

    public static int? OptionalInt(JsonElement item, string name) =>
        item.TryGetProperty(name, out JsonElement value) && value.ValueKind == JsonValueKind.Number ? value.GetInt32() : null;

    /// <summary>Compares rounded to two decimals; null must match exactly.</summary>
    public static void AssertRounded(string label, JsonElement expected, decimal? actual)
    {
        if (expected.ValueKind == JsonValueKind.Null)
        {
            Assert.IsNull(actual, label);
            return;
        }

        Assert.IsNotNull(actual, label);
        Assert.AreEqual(expected.GetDecimal(), TrainingStatistics.RoundForOutput(actual.Value), label);
    }

    public static void AssertOptionalInt(string label, JsonElement expected, int? actual) =>
        Assert.AreEqual(expected.ValueKind == JsonValueKind.Null ? null : expected.GetInt32(), actual, label);

    private static JsonElement[] Cases(string fileName)
    {
        string path = Path.Combine(AppContext.BaseDirectory, "Fixtures", fileName);
        using JsonDocument document = JsonDocument.Parse(File.ReadAllText(path));
        return document.RootElement.GetProperty("cases").Clone().EnumerateArray().ToArray();
    }
}

/// <summary>Maps the readable fixture IDs to stable GUIDs and back.</summary>
internal sealed class FixtureNames
{
    private readonly Dictionary<string, Guid> byName = new(StringComparer.Ordinal);
    private readonly Dictionary<Guid, string> byId = [];

    public Guid Of(string name)
    {
        if (!byName.TryGetValue(name, out Guid id))
        {
            id = Guid.NewGuid();
            byName[name] = id;
            byId[id] = name;
        }
        return id;
    }

    public Guid Of(JsonElement value) => Of(value.GetString()!);

    public string NameOf(Guid id) => byId[id];
}
