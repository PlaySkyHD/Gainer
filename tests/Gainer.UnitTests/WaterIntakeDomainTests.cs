using Gainer.Core.Mutations;
using Gainer.Core.Nutrition;

namespace Gainer.UnitTests;

[TestClass]
public sealed class WaterIntakeDomainTests
{
    private static readonly DateOnly Day = new(2026, 10, 25);

    [TestMethod]
    public void AddIncreasesAndSetReplacesTheTotal()
    {
        Assert.AreEqual(1_750, Change(WaterIntakeChange.Add, 500).ApplyTo(1_250));
        Assert.AreEqual(800, Change(WaterIntakeChange.Set, 800).ApplyTo(1_300));
        Assert.AreEqual(0, Change(WaterIntakeChange.Set, 0).ApplyTo(1_300));
        Assert.AreEqual(WaterIntakeLimits.MaxDailyMl, Change(WaterIntakeChange.Add, 200).ApplyTo(9_800));
    }

    [TestMethod]
    public void TotalAboveTheDailyLimitIsRejected()
    {
        NutritionValidationException error = Assert.Throws<NutritionValidationException>(() =>
            Change(WaterIntakeChange.Add, 300).ApplyTo(9_800));

        Assert.IsTrue(error.Errors.ContainsKey(nameof(ChangeWaterIntakeMutation.AmountMl)));
    }

    [TestMethod]
    [DataRow(WaterIntakeChange.Add, 0)]
    [DataRow(WaterIntakeChange.Add, -5)]
    [DataRow(WaterIntakeChange.Add, 10_001)]
    [DataRow(WaterIntakeChange.Set, -1)]
    [DataRow(WaterIntakeChange.Set, 10_001)]
    public void AmountsOutsideTheLimitsAreRejected(WaterIntakeChange change, int amountMl)
    {
        _ = Assert.Throws<NutritionValidationException>(() => Change(change, amountMl));
    }

    [TestMethod]
    public void MutationDeclaresItsResourceAndRejectsInvalidArguments()
    {
        Guid id = Guid.NewGuid();
        ChangeWaterIntakeMutation mutation = ChangeWaterIntakeMutation.Create(Metadata(), id, Day, 3, WaterIntakeChange.Set, 400);

        ResourceVersionExpectation expected = mutation.Scope.Resources.Single();
        Assert.AreEqual(ResourceKind.WaterIntakeDay, expected.Resource.Kind);
        Assert.AreEqual(id, expected.Resource.ResourceId);
        Assert.AreEqual(3, expected.BaseVersion);
        _ = Assert.Throws<ArgumentException>(() =>
            ChangeWaterIntakeMutation.Create(Metadata(), Guid.Empty, Day, 0, WaterIntakeChange.Add, 200));
        _ = Assert.Throws<ArgumentOutOfRangeException>(() =>
            ChangeWaterIntakeMutation.Create(Metadata(), id, Day, -1, WaterIntakeChange.Add, 200));
        _ = Assert.Throws<ArgumentOutOfRangeException>(() =>
            ChangeWaterIntakeMutation.Create(Metadata(), id, Day, 0, (WaterIntakeChange)9, 200));
        _ = Assert.Throws<ArgumentNullException>(() =>
            ChangeWaterIntakeMutation.Create(null!, id, Day, 0, WaterIntakeChange.Add, 200));
    }

    [TestMethod]
    public void SnapshotPointsToTheWaterResource()
    {
        Guid id = Guid.NewGuid();
        var snapshot = new WaterIntakeDaySnapshot(id, Day, 500, DateTime.UnixEpoch, DateTime.UnixEpoch, 2);

        Assert.AreEqual(ResourceKey.Create(ResourceKind.WaterIntakeDay, id), snapshot.Resource);
    }

    private static ChangeWaterIntakeMutation Change(WaterIntakeChange change, int amountMl) =>
        ChangeWaterIntakeMutation.Create(Metadata(), Guid.NewGuid(), Day, 0, change, amountMl);

    private static MutationMetadata Metadata() => MutationMetadata.Create(Guid.NewGuid(), Guid.NewGuid(), 1);
}
