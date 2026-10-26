using System.ComponentModel.DataAnnotations;
using System.Reflection;
using System.Text.Json;
using Gainer.Contracts.Sync;
using Gainer.Core.Mutations;
using Gainer.Core.Sync;

namespace Gainer.UnitTests;

[TestClass]
public sealed class SyncContractTests
{
    private static readonly int[] ExpectedProtocolWindow = [2, 4];

    [TestMethod]
    public void ClientRequestsCannotSelectAUserIdentity()
    {
        Type[] requestTypes =
        [
            typeof(PushMutationRequest),
            typeof(ResourceVersionRequest),
            typeof(RegisterSyncClientRequest),
        ];
        Assert.IsFalse(requestTypes.SelectMany(type => type.GetProperties())
            .Any(property => property.Name.Contains("UserId", StringComparison.OrdinalIgnoreCase)));
    }

    [TestMethod]
    public void PushContractCarriesProtocolDependencyAndMultiResourceVersions()
    {
        Guid dependency = Guid.NewGuid();
        var request = new PushMutationRequest(
            SyncProtocol.CurrentVersion,
            Guid.NewGuid(),
            42,
            "saveWorkout",
            [
                new ResourceVersionRequest("Workout", Guid.NewGuid(), 3),
                new ResourceVersionRequest("TrainingPlan", Guid.NewGuid(), 2),
            ],
            dependency,
            JsonDocument.Parse("{\"workout\":{\"endedAtUtc\":\"2026-08-18T12:00:00Z\"}}").RootElement.Clone());

        Assert.AreEqual(dependency, request.DependsOnMutationId);
        Assert.HasCount(2, request.Resources);
        Assert.AreEqual(3, request.Resources[0].BaseVersion);
        Assert.HasCount(0, Validate(request));
    }

    [TestMethod]
    public void PullContractKeepsBatchBoundariesAndTombstonesExplicit()
    {
        var response = new PullChangesResponse(
            SyncProtocol.CurrentVersion,
            8,
            true,
            [new SyncChangeBatchResponse(Guid.NewGuid(), 8, Guid.NewGuid(),
            [
                new SyncChangeResponse("CustomExercise", Guid.NewGuid(), 3, true, null),
                new SyncChangeResponse("Workout", Guid.NewGuid(), 2, false,
                    JsonDocument.Parse("{\"version\":2}").RootElement.Clone()),
            ])]);
        Assert.HasCount(1, response.Batches);
        Assert.HasCount(2, response.Batches[0].Changes);
        Assert.IsTrue(response.Batches[0].Changes[0].IsTombstone);
    }

    [TestMethod]
    public void NutritionExtensionKeepsExistingProtocolWindowCompatible()
    {
        CollectionAssert.AreEqual(
            ExpectedProtocolWindow,
            new[] { SyncProtocol.PreviousVersion, SyncProtocol.CurrentVersion });
        var nutrition = new ResourceVersionRequest("NutritionDay", Guid.NewGuid(), 0);
        Assert.HasCount(0, Validate(nutrition));
    }

    [TestMethod]
    public void ProtocolsGateTrainingAndTheTypesAddedAfterProtocolThree()
    {
        CollectionAssert.AreEquivalent(
            new[]
            {
                nameof(ResourceKind.CustomExercise), nameof(ResourceKind.TrainingPlan), nameof(ResourceKind.Workout),
                nameof(ResourceKind.ExerciseCategory), nameof(ResourceKind.CardioSession),
                nameof(ResourceKind.TrainingSchedule), nameof(ResourceKind.NutritionDayTemplate),
                nameof(ResourceKind.WaterIntakeDay),
            },
            SyncResourceProtocol.TypesNewerThan(SyncProtocol.PreviousVersion).ToArray());
        CollectionAssert.AreEquivalent(
            new[]
            {
                nameof(ResourceKind.CardioSession), nameof(ResourceKind.TrainingSchedule),
                nameof(ResourceKind.NutritionDayTemplate), nameof(ResourceKind.WaterIntakeDay),
            },
            SyncResourceProtocol.TypesNewerThan(SyncProtocol.TrainingContractVersion).ToArray());
        Assert.HasCount(0, SyncResourceProtocol.TypesNewerThan(SyncProtocol.CurrentVersion));
        Assert.IsTrue(SyncResourceProtocol.Supports(SyncProtocol.PreviousVersion, nameof(ResourceKind.NutritionDay)));
    }

    [TestMethod]
    public void EveryResourceKindHasAMinimumProtocolInsideTheWindow()
    {
        string[] kinds = Enum.GetNames<ResourceKind>();
        CollectionAssert.AreEquivalent(kinds, SyncResourceProtocol.KnownTypes.ToArray());
        Assert.AreEqual(SyncProtocol.PreviousVersion, kinds.Min(SyncResourceProtocol.MinimumVersionFor));
        foreach (string kind in kinds)
        {
            int minimum = SyncResourceProtocol.MinimumVersionFor(kind);
            Assert.IsTrue(
                minimum is >= SyncProtocol.PreviousVersion and <= SyncProtocol.CurrentVersion,
                $"{kind} needs a minimum protocol between {SyncProtocol.PreviousVersion} and {SyncProtocol.CurrentVersion}.");
        }
    }

    [TestMethod]
    public void CoreProtocolNumbersMatchTheContract()
    {
        // Core cannot reference Contracts, so it repeats the numbers; they must stay equal.
        CollectionAssert.AreEqual(
            new[] { SyncProtocol.PreviousVersion, SyncProtocol.TrainingContractVersion, SyncProtocol.CurrentVersion },
            new[] { SyncResourceProtocol.ProtocolTwo, SyncResourceProtocol.ProtocolThree, SyncResourceProtocol.CurrentVersion });
    }

    [TestMethod]
    public void UnknownResourceTypesFailClosed()
    {
        Assert.AreEqual(SyncProtocol.CurrentVersion, SyncResourceProtocol.MinimumVersionFor("WorkoutRotation"));
        Assert.IsFalse(SyncResourceProtocol.Supports(SyncProtocol.TrainingContractVersion, "WorkoutRotation"));
        Assert.IsFalse(SyncResourceProtocol.Supports(SyncProtocol.TrainingContractVersion, string.Empty));
    }

    private static List<ValidationResult> Validate(object value)
    {
        var results = new List<ValidationResult>();
        Validator.TryValidateObject(value, new ValidationContext(value), results, validateAllProperties: true);
        return results;
    }
}
