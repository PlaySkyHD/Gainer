using Gainer.Core.Values;

namespace Gainer.UnitTests;

[TestClass]
public sealed class CanonicalValueTests
{
    [TestMethod]
    public void CanonicalMeasurementsAcceptTheirInclusiveLowerBounds()
    {
        Assert.AreEqual(0m, Kilograms.From(0m).Value);
        Assert.AreEqual(0m, Grams.From(0m).Value);
        Assert.AreEqual(0m, Kilocalories.From(0m).Value);
        Assert.AreEqual(0, Steps.From(0).Value);
        Assert.AreEqual(0, SleepMinutes.From(0).Value);
        Assert.AreEqual(0m, RepetitionsInReserve.From(0m).Value);
        Assert.AreEqual(10m, RepetitionsInReserve.From(10m).Value);
    }

    [TestMethod]
    public void CanonicalMeasurementsRejectValuesOutsideTheirBounds()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => Kilograms.From(-0.01m));
        Assert.Throws<ArgumentOutOfRangeException>(() => Grams.From(-0.01m));
        Assert.Throws<ArgumentOutOfRangeException>(() => Kilocalories.From(-0.01m));
        Assert.Throws<ArgumentOutOfRangeException>(() => Steps.From(-1));
        Assert.Throws<ArgumentOutOfRangeException>(() => SleepMinutes.From(-1));
        Assert.Throws<ArgumentOutOfRangeException>(() => SleepMinutes.From(SleepMinutes.Maximum + 1));
        Assert.Throws<ArgumentOutOfRangeException>(() => RepetitionsInReserve.From(-0.1m));
        Assert.Throws<ArgumentOutOfRangeException>(() => RepetitionsInReserve.From(10.1m));
    }

    [TestMethod]
    public void KilogramsExposePositiveBodyWeightValidation()
    {
        Assert.IsFalse(Kilograms.From(0m).IsPositive);
        Assert.IsTrue(Kilograms.From(0.01m).IsPositive);
    }

    [TestMethod]
    public void IanaTimeZoneRejectsWindowsIdsAndUnknownZones()
    {
        Assert.IsTrue(IanaTimeZone.TryCreate("Europe/Berlin", out _));
        Assert.IsTrue(IanaTimeZone.TryCreate("UTC", out _));
        Assert.IsFalse(IanaTimeZone.TryCreate("W. Europe Standard Time", out _));
        Assert.IsFalse(IanaTimeZone.TryCreate("Europe/Does_Not_Exist", out _));
    }

    [TestMethod]
    public void LocalDateUsesInjectedTimeProviderAndIanaZone()
    {
        var timeProvider = new FixedTimeProvider(
            new DateTimeOffset(2026, 1, 1, 23, 30, 0, TimeSpan.Zero));

        DateOnly berlinDate = IanaTimeZone.From("Europe/Berlin").GetLocalDate(timeProvider);
        DateOnly newYorkDate = IanaTimeZone.From("America/New_York").GetLocalDate(timeProvider);

        Assert.AreEqual(new DateOnly(2026, 1, 2), berlinDate);
        Assert.AreEqual(new DateOnly(2026, 1, 1), newYorkDate);
    }

    private sealed class FixedTimeProvider(DateTimeOffset utcNow) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow()
        {
            return utcNow;
        }
    }
}
