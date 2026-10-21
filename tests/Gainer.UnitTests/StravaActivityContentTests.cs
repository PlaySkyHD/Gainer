using System.Xml.Linq;
using Gainer.Core.Integrations;
using Gainer.Core.Training;

namespace Gainer.UnitTests;

[TestClass]
public sealed class StravaActivityContentTests
{
    private static readonly XNamespace Tcx = "http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2";
    private static readonly DateTime Start = new(2026, 10, 21, 17, 0, 0, DateTimeKind.Utc);

    [TestMethod]
    public void CardioBecomesIndoorRideWithHeartRateTrackAndSpreadDistance()
    {
        CardioSession session = Cardio();

        StravaUpload upload = StravaActivityContent.ForCardio(session);

        Assert.AreEqual($"gainer-cardio-{session.Id:N}", upload.ExternalId);
        Assert.AreEqual("4×4", upload.Name);
        Assert.IsTrue(upload.Trainer);
        Assert.IsNull(upload.SportTypeAfterUpload);
        Assert.AreEqual("Locker\nZielbereich 120–140 bpm\nØ 152,5 W", upload.Description);

        XDocument document = XDocument.Load(new MemoryStream(upload.TcxFile));
        XElement activity = document.Descendants(Tcx + "Activity").Single();
        Assert.AreEqual("Biking", activity.Attribute("Sport")!.Value);
        XElement lap = activity.Element(Tcx + "Lap")!;
        Assert.AreEqual("20", lap.Element(Tcx + "TotalTimeSeconds")!.Value);
        Assert.AreEqual("200", lap.Element(Tcx + "DistanceMeters")!.Value);
        Assert.AreEqual("31", lap.Element(Tcx + "Calories")!.Value);
        Assert.AreEqual("125", lap.Element(Tcx + "AverageHeartRateBpm")!.Element(Tcx + "Value")!.Value);
        Assert.AreEqual("130", lap.Element(Tcx + "MaximumHeartRateBpm")!.Element(Tcx + "Value")!.Value);

        XElement[] points = lap.Descendants(Tcx + "Trackpoint").ToArray();
        // Four samples every 5 s plus the end point.
        Assert.HasCount(5, points);
        Assert.AreEqual("2026-10-21T17:00:00Z", points[0].Element(Tcx + "Time")!.Value);
        Assert.IsNull(points[0].Element(Tcx + "HeartRateBpm"), "A sample without signal has no heart rate.");
        Assert.AreEqual("120", points[1].Element(Tcx + "HeartRateBpm")!.Element(Tcx + "Value")!.Value);
        Assert.AreEqual("50", points[1].Element(Tcx + "DistanceMeters")!.Value);
        Assert.AreEqual("2026-10-21T17:00:20Z", points[4].Element(Tcx + "Time")!.Value);
        Assert.AreEqual("200", points[4].Element(Tcx + "DistanceMeters")!.Value);
    }

    [TestMethod]
    public void CardioWithoutTemplateOrExtrasIsNamedAfterTheActivity()
    {
        CardioSession session = Cardio();
        session.TemplateName = null;
        session.Notes = null;
        session.TargetZoneLowBpm = null;
        session.TargetZoneHighBpm = null;
        session.AveragePowerWatts = null;
        session.DistanceKm = null;
        session.HeartRateBpm = [0, 0];

        StravaUpload upload = StravaActivityContent.ForCardio(session);

        Assert.AreEqual("Rad-Ergometer", upload.Name);
        Assert.IsNull(upload.Description);
        XElement lap = XDocument.Load(new MemoryStream(upload.TcxFile)).Descendants(Tcx + "Lap").Single();
        Assert.IsNull(lap.Element(Tcx + "AverageHeartRateBpm"));
        Assert.IsFalse(lap.Descendants(Tcx + "Trackpoint").Any(point => point.Element(Tcx + "DistanceMeters") is not null));
    }

    [TestMethod]
    public void StrengthIsUploadedAsOtherAndRetypedWithExerciseSummary()
    {
        var workout = new Workout
        {
            Id = Guid.NewGuid(),
            Title = "Push",
            StartedAtUtc = Start,
            EndedAtUtc = Start.AddMinutes(55),
        };

        StravaUpload upload = StravaActivityContent.ForStrength(workout,
        [
            new StravaStrengthExercise("Bankdrücken",
            [
                new StravaStrengthSet(WorkoutSetType.Warmup, 40m, 10),
                new StravaStrengthSet(WorkoutSetType.Normal, 80m, 8),
                new StravaStrengthSet(WorkoutSetType.Normal, 80m, 8),
                new StravaStrengthSet(WorkoutSetType.Normal, 82.5m, 6),
            ]),
            new StravaStrengthExercise("Dips", [new StravaStrengthSet(WorkoutSetType.Normal, null, 12)]),
            new StravaStrengthExercise("Nur Aufwärmen", [new StravaStrengthSet(WorkoutSetType.Warmup, 20m, 10)]),
        ]);

        Assert.AreEqual($"gainer-strength-{workout.Id:N}", upload.ExternalId);
        Assert.AreEqual("Push", upload.Name);
        Assert.AreEqual("WeightTraining", upload.SportTypeAfterUpload);
        Assert.IsFalse(upload.Trainer);
        Assert.AreEqual("Bankdrücken: 2 × 8 · 80 kg, 1 × 6 · 82,5 kg\nDips: 1 × 12", upload.Description);
        XElement activity = XDocument.Load(new MemoryStream(upload.TcxFile)).Descendants(Tcx + "Activity").Single();
        Assert.AreEqual("Other", activity.Attribute("Sport")!.Value);
        Assert.AreEqual("3300", activity.Descendants(Tcx + "TotalTimeSeconds").Single().Value);
    }

    [TestMethod]
    public void SetSummaryCountsSetsWithoutRepetitions()
    {
        Assert.AreEqual(
            "2 Sätze · 20 kg",
            StravaActivityContent.SetSummary(
            [
                new StravaStrengthSet(WorkoutSetType.Normal, 20m, null),
                new StravaStrengthSet(WorkoutSetType.Dropset, 20m, null),
            ]));
        Assert.IsNull(StravaActivityContent.SetSummary([]));
    }

    private static CardioSession Cardio() => new()
    {
        Id = Guid.NewGuid(),
        StartedAtUtc = Start,
        EndedAtUtc = Start.AddSeconds(20),
        SampleIntervalSeconds = 5,
        HeartRateBpm = [0, 120, 125, 130],
        DistanceKm = 0.2m,
        EnergyKcal = 30.6m,
        AveragePowerWatts = 152.5m,
        TargetZoneLowBpm = 120,
        TargetZoneHighBpm = 140,
        Notes = " Locker ",
        TemplateName = "4×4",
    };
}
