using Gainer.Core.Mutations;
using Gainer.Core.Training;

namespace Gainer.UnitTests;

[TestClass]
public sealed class CardioSessionTests
{
    private static readonly DateTime Start = new(2026, 10, 18, 8, 0, 0, DateTimeKind.Utc);

    [TestMethod]
    public void ValidSessionIsNormalizedAndKeepsSeries()
    {
        CardioSessionValues values = Valid() with
        {
            SensorName = "  Polar H10  ",
            Notes = "   ",
            HeartRateBpm = [0, 25, 120, 250],
            RrIntervalsMs = [200, 800, 3000],
            StartedAtUtc = DateTime.SpecifyKind(Start, DateTimeKind.Unspecified),
        };

        CardioSessionValues normalized = CardioSessionValidation.Normalize(values);

        Assert.AreEqual("Polar H10", normalized.SensorName);
        Assert.IsNull(normalized.Notes);
        Assert.AreEqual(DateTimeKind.Utc, normalized.StartedAtUtc.Kind);
        CollectionAssert.AreEqual(new[] { 0, 25, 120, 250 }, normalized.HeartRateBpm.ToArray());
        CollectionAssert.AreEqual(new[] { 200, 800, 3000 }, normalized.RrIntervalsMs.ToArray());
    }

    [TestMethod]
    public void UnknownActivityAndTimeRangeAreRejected()
    {
        AssertInvalid(Valid() with { ActivityType = "Swimming" }, nameof(CardioSessionValues.ActivityType));
        AssertInvalid(Valid() with { EndedAtUtc = Start }, nameof(CardioSessionValues.EndedAtUtc));
        AssertInvalid(Valid() with { EndedAtUtc = Start.AddHours(24).AddSeconds(1), HeartRateBpm = [] }, nameof(CardioSessionValues.EndedAtUtc));
        CardioSessionValidation.Normalize(Valid() with { EndedAtUtc = Start.AddHours(24), HeartRateBpm = [] });
    }

    [TestMethod]
    public void TargetZoneBoundariesAreEnforced()
    {
        CardioSessionValidation.Normalize(Valid() with { TargetZone = new CardioTargetZone(40, 230) });
        AssertInvalid(Valid() with { TargetZone = new CardioTargetZone(39, 140) }, nameof(CardioSessionValues.TargetZone));
        AssertInvalid(Valid() with { TargetZone = new CardioTargetZone(120, 231) }, nameof(CardioSessionValues.TargetZone));
        AssertInvalid(Valid() with { TargetZone = new CardioTargetZone(140, 140) }, nameof(CardioSessionValues.TargetZone));
    }

    [TestMethod]
    public void SampleIntervalBoundariesAreEnforced()
    {
        CardioSessionValidation.Normalize(Valid() with { SampleIntervalSeconds = 1, HeartRateBpm = [] });
        CardioSessionValidation.Normalize(Valid() with { SampleIntervalSeconds = 60 });
        AssertInvalid(Valid() with { SampleIntervalSeconds = 0 }, nameof(CardioSessionValues.SampleIntervalSeconds));
        AssertInvalid(Valid() with { SampleIntervalSeconds = 61 }, nameof(CardioSessionValues.SampleIntervalSeconds));
    }

    [TestMethod]
    public void HeartRateValuesAndCountAreBounded()
    {
        AssertInvalid(Valid() with { HeartRateBpm = [400] }, nameof(CardioSessionValues.HeartRateBpm));
        AssertInvalid(Valid() with { HeartRateBpm = [24] }, nameof(CardioSessionValues.HeartRateBpm));
        AssertInvalid(Valid() with { HeartRateBpm = [251] }, nameof(CardioSessionValues.HeartRateBpm));
        AssertInvalid(Valid() with { HeartRateBpm = [-1] }, nameof(CardioSessionValues.HeartRateBpm));

        // 60 s at a 5 s interval allows ceil(12) + 1 = 13 values.
        CardioSessionValues oneMinute = Valid() with { EndedAtUtc = Start.AddMinutes(1) };
        CardioSessionValidation.Normalize(oneMinute with { HeartRateBpm = Enumerable.Repeat(100, 13).ToArray() });
        AssertInvalid(oneMinute with { HeartRateBpm = Enumerable.Repeat(100, 14).ToArray() }, nameof(CardioSessionValues.HeartRateBpm));
    }

    [TestMethod]
    public void RrIntervalsAreBounded()
    {
        AssertInvalid(Valid() with { RrIntervalsMs = [199] }, nameof(CardioSessionValues.RrIntervalsMs));
        AssertInvalid(Valid() with { RrIntervalsMs = [3001] }, nameof(CardioSessionValues.RrIntervalsMs));
        CardioSessionValidation.Normalize(Valid() with { RrIntervalsMs = Enumerable.Repeat(800, 40_000).ToArray() });
        AssertInvalid(Valid() with { RrIntervalsMs = Enumerable.Repeat(800, 40_001).ToArray() }, nameof(CardioSessionValues.RrIntervalsMs));
    }

    [TestMethod]
    public void TextAndManualValuesAreBounded()
    {
        AssertInvalid(Valid() with { SensorName = new string('x', 101) }, nameof(CardioSessionValues.SensorName));
        AssertInvalid(Valid() with { Notes = new string('x', 2_001) }, nameof(CardioSessionValues.Notes));
        AssertInvalid(Valid() with { DistanceKm = -0.1m }, nameof(CardioSessionValues.DistanceKm));
        AssertInvalid(Valid() with { DistanceKm = 1_000.1m }, nameof(CardioSessionValues.DistanceKm));
        AssertInvalid(Valid() with { AveragePowerWatts = -1m }, nameof(CardioSessionValues.AveragePowerWatts));
        AssertInvalid(Valid() with { AveragePowerWatts = 3_001m }, nameof(CardioSessionValues.AveragePowerWatts));
        AssertInvalid(Valid() with { EnergyKcal = -1m }, nameof(CardioSessionValues.EnergyKcal));
        AssertInvalid(Valid() with { EnergyKcal = 20_001m }, nameof(CardioSessionValues.EnergyKcal));
        CardioSessionValidation.Normalize(Valid() with { DistanceKm = 0m, AveragePowerWatts = 3_000m, EnergyKcal = 20_000m });
    }

    [TestMethod]
    public void MutationsCarryTheCardioSessionResourceAndVersionRules()
    {
        MutationMetadata metadata = MutationMetadata.Create(Guid.NewGuid(), Guid.NewGuid(), clientSequence: 1);
        CardioSessionValues values = Valid();

        SaveCardioSessionMutation create = SaveCardioSessionMutation.Create(metadata, 0, values);
        SaveCardioSessionMutation update = SaveCardioSessionMutation.Create(metadata, 3, values);
        DeleteCardioSessionMutation delete = DeleteCardioSessionMutation.Create(metadata, values.SessionId, 3);

        Assert.AreEqual(ResourceKind.CardioSession, create.Scope.Resources[0].Resource.Kind);
        Assert.AreEqual(values.SessionId, create.Scope.Resources[0].Resource.ResourceId);
        Assert.AreEqual(3, update.Scope.Resources[0].BaseVersion);
        Assert.AreEqual(ResourceKind.CardioSession, delete.Scope.Resources[0].Resource.Kind);
        Assert.Throws<ArgumentOutOfRangeException>(() => SaveCardioSessionMutation.Create(metadata, -1, values));
        Assert.Throws<ArgumentOutOfRangeException>(() => DeleteCardioSessionMutation.Create(metadata, values.SessionId, 0));
        Assert.Throws<ArgumentException>(() => SaveCardioSessionMutation.Create(metadata, 0, values with { SessionId = Guid.Empty }));
        Assert.Throws<ArgumentException>(() => DeleteCardioSessionMutation.Create(metadata, Guid.Empty, 1));
    }

    [TestMethod]
    public void SnapshotExposesTheCardioSessionResource()
    {
        Guid id = Guid.NewGuid();
        var snapshot = new CardioSessionSnapshot(
            id, CardioActivityTypes.IndoorCycling, Start, Start.AddMinutes(1), null, 5, [], [], null, null, null, null, null, Start, Start, 1);

        Assert.AreEqual(ResourceKey.Create(ResourceKind.CardioSession, id), snapshot.Resource);
    }

    [TestMethod]
    public void RecoveryValuesMustComeTogetherAndBeInRange()
    {
        CardioSessionValidation.Normalize(Valid() with { RecoveryStartBpm = 25, RecoveryEndBpm = 250 });
        AssertInvalid(Valid() with { RecoveryStartBpm = 150 }, nameof(CardioSessionValues.RecoveryStartBpm));
        AssertInvalid(Valid() with { RecoveryEndBpm = 100 }, nameof(CardioSessionValues.RecoveryStartBpm));
        AssertInvalid(Valid() with { RecoveryStartBpm = 24, RecoveryEndBpm = 100 }, nameof(CardioSessionValues.RecoveryStartBpm));
        AssertInvalid(Valid() with { RecoveryStartBpm = 150, RecoveryEndBpm = 251 }, nameof(CardioSessionValues.RecoveryStartBpm));
    }

    [TestMethod]
    public void TemplateNameIsTrimmedAndBounded()
    {
        Assert.AreEqual("Intervals", CardioSessionValidation.Normalize(Valid() with { TemplateName = "  Intervals " }).TemplateName);
        Assert.IsNull(CardioSessionValidation.Normalize(Valid() with { TemplateName = "   " }).TemplateName);
        CardioSessionValidation.Normalize(Valid() with { TemplateName = new string('a', 100) });
        AssertInvalid(Valid() with { TemplateName = new string('a', 101) }, nameof(CardioSessionValues.TemplateName));
    }

    [TestMethod]
    public void ValidPhasesAreKeptAndEmptyBecomesNull()
    {
        CardioSessionValues normalized = CardioSessionValidation.Normalize(Valid() with
        {
            Phases = [new(0, 60, " Warm-up ", 100, 120), new(60, 30, "Push", null, null), new(120, 3_600, "Easy", 40, 230)],
        });
        Assert.HasCount(3, normalized.Phases!);
        Assert.AreEqual("Warm-up", normalized.Phases![0].Name);
        Assert.IsNull(normalized.Phases[1].LowBpm);
        Assert.IsNull(CardioSessionValidation.Normalize(Valid() with { Phases = [] }).Phases);
        Assert.IsNull(CardioSessionValidation.Normalize(Valid()).Phases);
    }

    [TestMethod]
    public void PhaseOrderOverlapAndDurationAreEnforced()
    {
        string key = nameof(CardioSessionValues.Phases);
        AssertInvalid(Valid() with { Phases = [new(0, 60, "A", null, null), new(59, 60, "B", null, null)] }, key);
        AssertInvalid(Valid() with { Phases = [new(100, 60, "A", null, null), new(0, 60, "B", null, null)] }, key);
        AssertInvalid(Valid() with { Phases = [new(-1, 60, "A", null, null)] }, key);
        AssertInvalid(Valid() with { Phases = [new(0, 29, "A", null, null)] }, key);
        AssertInvalid(Valid() with { Phases = [new(0, 3_601, "A", null, null)] }, key);
        CardioSessionValidation.Normalize(Valid() with { Phases = [new(0, 60, "A", null, null), new(60, 60, "B", null, null)] });
    }

    [TestMethod]
    public void PhaseCountNameAndTotalAreBounded()
    {
        string key = nameof(CardioSessionValues.Phases);
        CardioPhaseValues[] thirty = Enumerable.Range(0, 30).Select(i => new CardioPhaseValues(i * 60, 60, "P", null, null)).ToArray();
        CardioSessionValidation.Normalize(Valid() with { Phases = thirty });
        CardioPhaseValues[] thirtyOne = Enumerable.Range(0, 31).Select(i => new CardioPhaseValues(i * 60, 60, "P", null, null)).ToArray();
        AssertInvalid(Valid() with { Phases = thirtyOne }, key);
        AssertInvalid(Valid() with { Phases = [new(0, 60, "  ", null, null)] }, key);
        AssertInvalid(Valid() with { Phases = [new(0, 60, new string('a', 61), null, null)] }, key);
        CardioSessionValidation.Normalize(Valid() with { Phases = [new(0, 60, new string('a', 60), null, null)] });
        CardioSessionValidation.Normalize(Valid() with { Phases = [new(14_400 - 3_600, 3_600, "Last", null, null)] });
        AssertInvalid(Valid() with { Phases = [new(14_400 - 3_600 + 1, 3_600, "Last", null, null)] }, key);
    }

    [TestMethod]
    public void PhaseZoneIsBothOrNoneAndOrdered()
    {
        string key = nameof(CardioSessionValues.Phases);
        AssertInvalid(Valid() with { Phases = [new(0, 60, "A", 120, null)] }, key);
        AssertInvalid(Valid() with { Phases = [new(0, 60, "A", null, 150)] }, key);
        AssertInvalid(Valid() with { Phases = [new(0, 60, "A", 39, 150)] }, key);
        AssertInvalid(Valid() with { Phases = [new(0, 60, "A", 120, 231)] }, key);
        AssertInvalid(Valid() with { Phases = [new(0, 60, "A", 140, 140)] }, key);
    }

    private static CardioSessionValues Valid() => new(
        Guid.NewGuid(),
        CardioActivityTypes.IndoorCycling,
        Start,
        Start.AddMinutes(10),
        new CardioTargetZone(120, 140),
        5,
        [100, 110, 120],
        [800, 810],
        "Polar H10",
        null,
        null,
        null,
        null);

    private static void AssertInvalid(CardioSessionValues values, string field)
    {
        CardioSessionValidationException error = Assert.Throws<CardioSessionValidationException>(
            () => CardioSessionValidation.Normalize(values));
        Assert.IsTrue(error.Errors.ContainsKey(field), $"Expected an error for {field}.");
    }
}
