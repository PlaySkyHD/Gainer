using System.Text.Json;
using Gainer.Core.Coach;

namespace Gainer.UnitTests;

[TestClass]
public sealed class CoachToolSchemaTests
{
    [TestMethod]
    public void ToolsAreStrictReadOnlyAndExposeNoIdentitySqlUrlOrMutationInputs()
    {
        string json = CoachToolCatalog.Definitions.GetRawText();
        foreach (string forbidden in new[] { "userId", "email", "sql", "url", "insert", "update", "delete", "mutation" })
            Assert.IsFalse(json.Contains(forbidden, StringComparison.OrdinalIgnoreCase), forbidden);
        foreach (JsonElement tool in CoachToolCatalog.Definitions.EnumerateArray())
        {
            Assert.AreEqual("function", tool.GetProperty("type").GetString());
            Assert.IsTrue(tool.GetProperty("strict").GetBoolean());
            Assert.IsFalse(tool.GetProperty("parameters").GetProperty("additionalProperties").GetBoolean());
        }
    }

    [TestMethod]
    public void StructuredAnswerSchemaRejectsAdditionalPropertiesAndBoundsEveryCollection()
    {
        JsonElement schema = CoachToolCatalog.OutputSchema;
        Assert.IsFalse(schema.GetProperty("additionalProperties").GetBoolean());
        Assert.AreEqual(8, schema.GetProperty("properties").GetProperty("observations").GetProperty("maxItems").GetInt32());
        Assert.AreEqual(6, schema.GetProperty("properties").GetProperty("suggestions").GetProperty("maxItems").GetInt32());
    }

    private static readonly string[] ExpectedFields = new[] { "category", "text" };

    [TestMethod]
    public void MemorySuggestionsAreARequiredBoundedListOfCategoryAndText()
    {
        JsonElement schema = CoachToolCatalog.OutputSchema;
        Assert.Contains(item => item.GetString() == "memorySuggestions", schema.GetProperty("required").EnumerateArray());
        JsonElement suggestions = schema.GetProperty("properties").GetProperty("memorySuggestions");
        Assert.AreEqual(CoachMemoryRules.MaxSuggestions, suggestions.GetProperty("maxItems").GetInt32());
        JsonElement item = suggestions.GetProperty("items");
        Assert.IsFalse(item.GetProperty("additionalProperties").GetBoolean());
        Assert.AreSequenceEqual(
            CoachMemoryRules.WireNames.ToArray(),
            item.GetProperty("properties").GetProperty("category").GetProperty("enum").EnumerateArray().Select(value => value.GetString()).ToArray());
        Assert.AreEqual(CoachMemoryRules.MaxTextLength, item.GetProperty("properties").GetProperty("text").GetProperty("maxLength").GetInt32());
        Assert.AreSequenceEqual(
            ExpectedFields,
            item.GetProperty("properties").EnumerateObject().Select(property => property.Name).ToArray(), SequenceOrder.InAnyOrder);
    }

    [TestMethod]
    public void MemoryRulesNormalizeTextAndRoundTripCategories()
    {
        Assert.AreEqual("Halbmarathon im Mai", CoachMemoryRules.Normalize(" Halbmarathon\r\n\tim \u0000 Mai  "));
        Assert.AreEqual(string.Empty, CoachMemoryRules.Normalize(null));
        Assert.AreEqual(CoachMemoryRules.DuplicateKey("laktose"), CoachMemoryRules.DuplicateKey(" LAKTOSE "));
        foreach (CoachMemoryCategory category in Enum.GetValues<CoachMemoryCategory>())
        {
            Assert.IsTrue(CoachMemoryRules.TryParse(CoachMemoryRules.ToWire(category), out CoachMemoryCategory parsed));
            Assert.AreEqual(category, parsed);
        }
        Assert.IsFalse(CoachMemoryRules.TryParse("Goal", out _));
        Assert.IsFalse(CoachMemoryRules.TryParse(null, out _));
        Assert.ThrowsExactly<ArgumentOutOfRangeException>(() => CoachMemoryRules.ToWire((CoachMemoryCategory)42));
    }
}
