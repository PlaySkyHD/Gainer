using Gainer.Core.Training;

namespace Gainer.UnitTests;

[TestClass]
public sealed class ExerciseCatalogDomainTests
{
    [TestMethod]
    [DataRow("strength", ExerciseType.Strength)]
    [DataRow("bodyweightLoaded", ExerciseType.BodyweightLoaded)]
    [DataRow("bodyweightOnly", ExerciseType.BodyweightOnly)]
    [DataRow("assisted", ExerciseType.Assisted)]
    [DataRow("STRENGTH", ExerciseType.Strength)]
    [DataRow("BodyWeightLoaded", ExerciseType.BodyweightLoaded)]
    [DataRow("bodyweightonly", ExerciseType.BodyweightOnly)]
    [DataRow("Assisted", ExerciseType.Assisted)]
    public void ParserAcceptsStorageValuesCaseInsensitively(string value, ExerciseType expected)
    {
        Assert.AreEqual(expected, ExerciseTypes.Parse(value));
    }

    [TestMethod]
    [DataRow("")]
    [DataRow("   ")]
    [DataRow(null)]
    [DataRow("cardio")]
    [DataRow("Strength ")]
    [DataRow("Bodyweight")]
    public void ParserRejectsUnknownOrEmptyTypesWithoutFallback(string? value)
    {
        Assert.ThrowsExactly<UnknownExerciseTypeException>(() => ExerciseTypes.Parse(value));
    }

    [TestMethod]
    public void StorageValuesRoundTripThroughParser()
    {
        foreach (ExerciseType type in Enum.GetValues<ExerciseType>())
        {
            Assert.AreEqual(type, ExerciseTypes.Parse(ExerciseTypes.ToStorageValue(type)));
        }

        Assert.AreEqual("bodyweightLoaded", ExerciseTypes.ToStorageValue(ExerciseType.BodyweightLoaded));
    }

    [TestMethod]
    [DataRow(ExerciseType.Strength, 0.0)]
    [DataRow(ExerciseType.BodyweightLoaded, 1.0)]
    [DataRow(ExerciseType.BodyweightOnly, 1.0)]
    [DataRow(ExerciseType.Assisted, 1.0)]
    public void BodyweightFactorDefaultsToTypeWithoutOwnOrCatalogValue(ExerciseType type, double expected)
    {
        var exercise = new Exercise { ExerciseType = type };

        Assert.AreEqual((decimal)expected, ExerciseFactors.BodyweightFactor(exercise));
        Assert.AreEqual(1m, ExerciseFactors.WeightFactor(exercise));
    }

    [TestMethod]
    public void ExplicitFactorsOverrideTypeDefaults()
    {
        var pushUp = new Exercise { ExerciseType = ExerciseType.BodyweightOnly, BodyweightFactor = 0.64m };
        var heavyRow = new Exercise { ExerciseType = ExerciseType.Strength, WeightFactor = 2m };

        Assert.AreEqual(0.64m, ExerciseFactors.BodyweightFactor(pushUp));
        Assert.AreEqual(2m, ExerciseFactors.WeightFactor(heavyRow));
        Assert.AreEqual(0m, ExerciseFactors.BodyweightFactor(heavyRow));
    }

    [TestMethod]
    public void PushUpExampleYieldsFiveHundredTwelveKilogramVolumeFromFactorsAlone()
    {
        var pushUp = new Exercise { ExerciseType = ExerciseType.BodyweightOnly, BodyweightFactor = 0.64m };
        decimal bodyweightKg = 80m;
        const int repetitions = 10;

        decimal load = bodyweightKg * ExerciseFactors.BodyweightFactor(pushUp) * ExerciseFactors.WeightFactor(pushUp);

        Assert.AreEqual(512m, load * repetitions);
    }

    [TestMethod]
    public void FactorBoundsAreInclusiveForBodyweightAndExclusiveAtZeroForWeight()
    {
        ExerciseFactors.EnsureValid(0m, 0.001m);
        ExerciseFactors.EnsureValid(1m, 10m);
        ExerciseFactors.EnsureValid(null, null);

        Assert.ThrowsExactly<ArgumentOutOfRangeException>(() => ExerciseFactors.EnsureValid(-0.01m, null));
        Assert.ThrowsExactly<ArgumentOutOfRangeException>(() => ExerciseFactors.EnsureValid(1.01m, null));
        Assert.ThrowsExactly<ArgumentOutOfRangeException>(() => ExerciseFactors.EnsureValid(null, 0m));
        Assert.ThrowsExactly<ArgumentOutOfRangeException>(() => ExerciseFactors.EnsureValid(null, 10.01m));
    }
}
