using System.Text.Json;
using Gainer.Core.Training;
using static Gainer.UnitTests.ContractFixture;

namespace Gainer.UnitTests;

/// <summary>The cardio key figures compute as in the app (contracts/fixtures/cardio-analysis.json).</summary>
[TestClass]
public sealed class CardioAnalysisFixtureTests
{
    private const string FileName = "cardio-analysis.json";

    public static IEnumerable<object[]> Names => CaseNames(FileName);

    [TestMethod]
    [DynamicData(nameof(Names))]
    public void FixtureCaseMatchesCalculation(string caseName)
    {
        JsonElement item = Case(FileName, caseName);
        JsonElement zone = item.GetProperty("targetZone");
        var session = new CardioSessionSnapshot(
            Guid.NewGuid(),
            CardioActivityTypes.IndoorCycling,
            Utc(item.GetProperty("startedAtUtc")),
            Utc(item.GetProperty("endedAtUtc")),
            zone.ValueKind == JsonValueKind.Null
                ? null
                : new CardioTargetZone(zone.GetProperty("lowBpm").GetInt32(), zone.GetProperty("highBpm").GetInt32()),
            item.GetProperty("sampleIntervalSeconds").GetInt32(),
            Ints(item.GetProperty("heartRateBpm")),
            Ints(item.GetProperty("rrIntervalsMs")),
            null,
            null,
            null,
            null,
            null,
            DateTime.UtcNow,
            DateTime.UtcNow,
            1,
            OptionalInt(item, "recoveryStartBpm"),
            OptionalInt(item, "recoveryEndBpm"),
            null,
            item.GetProperty("phases").EnumerateArray()
                .Select(phase => new CardioPhaseValues(
                    phase.GetProperty("startOffsetSeconds").GetInt32(),
                    phase.GetProperty("durationSeconds").GetInt32(),
                    phase.GetProperty("name").GetString()!,
                    OptionalInt(phase, "lowBpm"),
                    OptionalInt(phase, "highBpm")))
                .ToArray());

        CardioAnalysis analysis = CardioAnalysis.Of(session);

        JsonElement expected = item.GetProperty("expected");
        Assert.AreEqual(expected.GetProperty("activeDurationSeconds").GetInt32(), (int)analysis.ActiveDuration.TotalSeconds);
        AssertRounded("averageBpm", expected.GetProperty("averageBpm"), analysis.AverageBpm);
        AssertOptionalInt("maxBpm", expected.GetProperty("maxBpm"), analysis.MaxBpm);
        Assert.AreEqual(expected.GetProperty("timeInZoneSeconds").GetInt32(), (int)analysis.TimeInZone.TotalSeconds);
        JsonElement share = expected.GetProperty("zoneShare");
        decimal? expectedShare = share.ValueKind == JsonValueKind.Null ? null : share.GetDecimal();
        decimal? actualShare = analysis.ZoneShare is { } value ? decimal.Round(value, 4, MidpointRounding.AwayFromZero) : null;
        Assert.AreEqual(expectedShare, actualShare, "zoneShare");
        AssertOptionalInt("rmssdMs", expected.GetProperty("rmssdMs"), analysis.RmssdMs);
        AssertOptionalInt("recoveryDropBpm", expected.GetProperty("recoveryDropBpm"), analysis.RecoveryDropBpm);
    }

    private static int[] Ints(JsonElement array) => array.EnumerateArray().Select(value => value.GetInt32()).ToArray();
}
