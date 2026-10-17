using Gainer.Core.Mutations;

namespace Gainer.UnitTests;

[TestClass]
public sealed class MutationContractTests
{
    [TestMethod]
    public void MutationScopeSupportsAtomicMultiAggregateOperations()
    {
        ResourceVersionExpectation workout = Expect(ResourceKind.Workout, baseVersion: 4);
        ResourceVersionExpectation rotation = Expect(ResourceKind.WorkoutRotation, baseVersion: 2);
        AtomicMutationScope scope = AtomicMutationScope.Create(workout, rotation);

        Assert.HasCount(2, scope.Resources);
        Assert.AreEqual(4, scope.Resources[0].BaseVersion);
        Assert.AreEqual(2, scope.Resources[1].BaseVersion);
    }

    [TestMethod]
    public void MutationMetadataAndVersionsRejectInvalidValues()
    {
        Assert.Throws<ArgumentException>(() =>
            MutationMetadata.Create(Guid.Empty, Guid.NewGuid(), clientSequence: 1));
        Assert.Throws<ArgumentException>(() =>
            MutationMetadata.Create(Guid.NewGuid(), Guid.Empty, clientSequence: 1));
        Assert.Throws<ArgumentOutOfRangeException>(() =>
            MutationMetadata.Create(Guid.NewGuid(), Guid.NewGuid(), clientSequence: 0));
        Assert.Throws<ArgumentOutOfRangeException>(() =>
            ResourceVersionExpectation.Create(ResourceKey.Create(ResourceKind.Workout, Guid.NewGuid()), -1));
    }

    [TestMethod]
    public void MutationScopeRejectsDuplicateResources()
    {
        ResourceVersionExpectation resource = Expect(ResourceKind.DailyCheckIn, baseVersion: 1);

        Assert.Throws<ArgumentException>(() => AtomicMutationScope.Create(resource, resource));
    }

    [TestMethod]
    public void ChangeCollectorCapturesTypedSnapshotsAndTombstones()
    {
        var collector = new ChangeCollector();
        ResourceKey goal = ResourceKey.Create(ResourceKind.BodyGoal, Guid.NewGuid());
        ResourceKey checkIn = ResourceKey.Create(ResourceKind.DailyCheckIn, Guid.NewGuid());

        collector.CaptureUpsert(new TestSnapshot(goal, Version: 2));
        collector.CaptureDeletion(checkIn, version: 3);

        Assert.IsInstanceOfType<UpsertedResourceChange>(collector.Changes[0]);
        Assert.IsInstanceOfType<DeletedResourceChange>(collector.Changes[1]);
        Assert.Throws<InvalidOperationException>(() =>
            collector.CaptureUpsert(new TestSnapshot(goal, Version: 3)));
    }

    [TestMethod]
    public void MutationContractsExposeNoUserOrFreeFormDataAccessSelectors()
    {
        Type[] contractTypes = typeof(MutationMetadata).Assembly.GetTypes()
            .Where(type => type.Namespace == typeof(MutationMetadata).Namespace)
            .ToArray();
        string[] forbiddenFragments = ["UserId", "Sql", "TableName", "Crud"];

        string[] exposedMemberNames = contractTypes
            .SelectMany(type => type.GetMembers())
            .Select(member => member.Name)
            .ToArray();

        Assert.IsFalse(exposedMemberNames.Any(name =>
            forbiddenFragments.Any(fragment => name.Contains(fragment, StringComparison.OrdinalIgnoreCase))));
    }

    private static ResourceVersionExpectation Expect(ResourceKind kind, long baseVersion)
    {
        return ResourceVersionExpectation.Create(ResourceKey.Create(kind, Guid.NewGuid()), baseVersion);
    }

    private sealed record CompleteWorkoutMutation(
        MutationMetadata Metadata,
        AtomicMutationScope Scope) : ITypedMutation<bool>;

    private sealed record TestSnapshot(ResourceKey Resource, long Version) : IResourceSnapshot;
}
