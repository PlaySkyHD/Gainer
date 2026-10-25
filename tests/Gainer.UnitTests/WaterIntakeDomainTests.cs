using Gainer.Core.Mutations;
using Gainer.Core.Nutrition;

namespace Gainer.UnitTests;

[TestClass]
public sealed class WaterIntakeDomainTests
{
    private static readonly DateOnly Day = new(2026, 10, 25);

    [TestMethod]
    [DataRow(0)]
    [DataRow(1_250)]
    [DataRow(10_000)]
    public void TotalsWithinTheDailyLimitsAreAccepted(int amountMl)
    {
        Assert.AreEqual(amountMl, Set(amountMl).AmountMl);
    }

    [TestMethod]
    [DataRow(-1)]
    [DataRow(10_001)]
    [DataRow(int.MaxValue)]
    public void TotalsOutsideTheLimitsAreRejected(int amountMl)
    {
        NutritionValidationException error = Assert.Throws<NutritionValidationException>(() => Set(amountMl));

        Assert.IsTrue(error.Errors.ContainsKey(nameof(SetWaterIntakeMutation.AmountMl)));
    }

    [TestMethod]
    public void MutationDeclaresItsResourceAndRejectsInvalidArguments()
    {
        Guid id = Guid.NewGuid();
        SetWaterIntakeMutation mutation = SetWaterIntakeMutation.Create(Metadata(), id, Day, 3, 400);

        ResourceVersionExpectation expected = mutation.Scope.Resources.Single();
        Assert.AreEqual(ResourceKind.WaterIntakeDay, expected.Resource.Kind);
        Assert.AreEqual(id, expected.Resource.ResourceId);
        Assert.AreEqual(3, expected.BaseVersion);
        Assert.AreEqual(Day, mutation.LocalDate);
        _ = Assert.Throws<ArgumentException>(() =>
            SetWaterIntakeMutation.Create(Metadata(), Guid.Empty, Day, 0, 200));
        _ = Assert.Throws<ArgumentOutOfRangeException>(() =>
            SetWaterIntakeMutation.Create(Metadata(), id, Day, -1, 200));
        _ = Assert.Throws<ArgumentNullException>(() =>
            SetWaterIntakeMutation.Create(null!, id, Day, 0, 200));
    }

    [TestMethod]
    public void SnapshotPointsToTheWaterResource()
    {
        Guid id = Guid.NewGuid();
        var snapshot = new WaterIntakeDaySnapshot(id, Day, 500, DateTime.UnixEpoch, DateTime.UnixEpoch, 2);

        Assert.AreEqual(ResourceKey.Create(ResourceKind.WaterIntakeDay, id), snapshot.Resource);
    }

    private static SetWaterIntakeMutation Set(int amountMl) =>
        SetWaterIntakeMutation.Create(Metadata(), Guid.NewGuid(), Day, 0, amountMl);

    private static MutationMetadata Metadata() => MutationMetadata.Create(Guid.NewGuid(), Guid.NewGuid(), 1);
}
