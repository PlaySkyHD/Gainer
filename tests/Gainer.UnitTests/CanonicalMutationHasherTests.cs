using System.Text;
using System.Text.Json;
using System.Globalization;
using Gainer.Core.Sync;

namespace Gainer.UnitTests;

[TestClass]
public sealed class CanonicalMutationHasherTests
{
    private static readonly Guid ClientId = Guid.Parse("11111111-1111-4111-8111-111111111111");
    private static readonly Guid ResourceId = Guid.Parse("22222222-2222-4222-8222-222222222222");

    [TestMethod]
    public void GoldenVectorSortsKeysNormalizesDecimalsAndProducesStableSha256()
    {
        CanonicalMutationContent mutation = Mutation("{\"z\":\"last\",\"nested\":{\"b\":2.00,\"a\":-0.0},\"a\":1.2300}");
        string canonical = Encoding.UTF8.GetString(CanonicalMutationHasher.Serialize(mutation));
        Assert.AreEqual(
            "{\"clientId\":\"11111111-1111-4111-8111-111111111111\",\"clientSequence\":42,\"dependsOnMutationId\":null,\"operation\":\"updateCheckIn\",\"payload\":{\"a\":1.23,\"nested\":{\"a\":0,\"b\":2},\"z\":\"last\"},\"protocolVersion\":2,\"resources\":[{\"baseVersion\":3,\"resourceId\":\"22222222-2222-4222-8222-222222222222\",\"resourceType\":\"DailyCheckIn\"}]}",
            canonical);
        Assert.AreEqual("8b3af8545c8321d5ea39801942b572d1e47b911e0630e8026d9dc5bb51cb5cb3", CanonicalMutationHasher.HashHex(mutation));
    }

    [TestMethod]
    public void EquivalentObjectOrderAndDecimalSpellingHaveTheSameHash()
    {
        Assert.AreEqual(
            CanonicalMutationHasher.HashHex(Mutation("{\"a\":1.2300,\"b\":2}")),
            CanonicalMutationHasher.HashHex(Mutation("{\"b\":2.0,\"a\":1.23}")));
    }

    [TestMethod]
    public void ArrayOrderChangesHashAndUnsafeNumbersAreRejected()
    {
        Assert.AreNotEqual(
            CanonicalMutationHasher.HashHex(Mutation("{\"values\":[1,2]}")),
            CanonicalMutationHasher.HashHex(Mutation("{\"values\":[2,1]}")));
        Assert.ThrowsExactly<InvalidOperationException>(() =>
            CanonicalMutationHasher.Hash(Mutation("{\"unsafe\":1e100}")));
    }

    [TestMethod]
    public void DeterministicFuzzKeepsEquivalentDecimalAndObjectRepresentationsCanonical()
    {
        var random = new Random(20260818);
        for (int index = 0; index < 250; index++)
        {
            decimal first = random.Next(-100_000, 100_001) / 100m;
            decimal second = random.Next(-100_000, 100_001) / 100m;
            string a = first.ToString("0.00", CultureInfo.InvariantCulture);
            string b = second.ToString("0.0000", CultureInfo.InvariantCulture);
            string left = $"{{\"first\":{a},\"nested\":{{\"second\":{b},\"index\":{index}}}}}";
            string right = $"{{\"nested\":{{\"index\":{index}.0,\"second\":{second.ToString(CultureInfo.InvariantCulture)}}},\"first\":{first.ToString(CultureInfo.InvariantCulture)}}}";

            Assert.AreEqual(
                CanonicalMutationHasher.HashHex(Mutation(left)),
                CanonicalMutationHasher.HashHex(Mutation(right)),
                $"Canonical hash diverged for fuzz case {index}.");
        }
    }

    private static CanonicalMutationContent Mutation(string payload) => new(
        ProtocolVersion: 2,
        ClientId,
        ClientSequence: 42,
        Operation: "updateCheckIn",
        Resources: [new CanonicalResourceVersion("DailyCheckIn", ResourceId, 3)],
        DependsOnMutationId: null,
        Payload: JsonDocument.Parse(payload).RootElement.Clone());
}
