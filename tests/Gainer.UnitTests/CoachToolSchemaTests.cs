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
}
