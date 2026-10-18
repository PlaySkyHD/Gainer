namespace Gainer.Core.Training;

/// <summary>Checks the shape and bounds of a cardio session against the sync contract and returns the normalized values.</summary>
public static class CardioSessionValidation
{
    public const int MaximumDurationHours = 24;
    public const int MaximumRrIntervals = 40_000;

    private const int MinimumZoneBpm = 40;
    private const int MaximumZoneBpm = 230;
    private const int MinimumSampleIntervalSeconds = 1;
    private const int MaximumSampleIntervalSeconds = 60;
    private const int MinimumHeartRateBpm = 25;
    private const int MaximumHeartRateBpm = 250;
    private const int MinimumRrMs = 200;
    private const int MaximumRrMs = 3_000;
    private const int MaximumSensorNameLength = 100;
    private const int MaximumNotesLength = 2_000;
    private const decimal MaximumDistanceKm = 1_000m;
    private const decimal MaximumPowerWatts = 3_000m;
    private const decimal MaximumEnergyKcal = 20_000m;

    public static CardioSessionValues Normalize(CardioSessionValues session)
    {
        ArgumentNullException.ThrowIfNull(session);
        var errors = new Dictionary<string, string>(StringComparer.Ordinal);
        if (!CardioActivityTypes.IsKnown(session.ActivityType))
        {
            errors[nameof(CardioSessionValues.ActivityType)] = "The activity type is unknown.";
        }

        DateTime startedAtUtc = WorkoutValidation.ToUtc(session.StartedAtUtc);
        DateTime endedAtUtc = WorkoutValidation.ToUtc(session.EndedAtUtc);
        TimeSpan duration = endedAtUtc - startedAtUtc;
        if (duration <= TimeSpan.Zero)
        {
            errors[nameof(CardioSessionValues.EndedAtUtc)] = "The end must be after the start.";
        }
        else if (duration > TimeSpan.FromHours(MaximumDurationHours))
        {
            errors[nameof(CardioSessionValues.EndedAtUtc)] = $"A session cannot last longer than {MaximumDurationHours} hours.";
        }

        if (session.TargetZone is { } zone &&
            (zone.LowBpm < MinimumZoneBpm || zone.HighBpm > MaximumZoneBpm || zone.LowBpm >= zone.HighBpm))
        {
            errors[nameof(CardioSessionValues.TargetZone)] =
                $"The target zone must satisfy {MinimumZoneBpm} <= low < high <= {MaximumZoneBpm}.";
        }

        bool intervalValid = session.SampleIntervalSeconds is >= MinimumSampleIntervalSeconds and <= MaximumSampleIntervalSeconds;
        if (!intervalValid)
        {
            errors[nameof(CardioSessionValues.SampleIntervalSeconds)] =
                $"The sample interval must be between {MinimumSampleIntervalSeconds} and {MaximumSampleIntervalSeconds} seconds.";
        }

        IReadOnlyList<int> heartRate = session.HeartRateBpm ?? [];
        if (heartRate.Any(value => value != 0 && (value < MinimumHeartRateBpm || value > MaximumHeartRateBpm)))
        {
            errors[nameof(CardioSessionValues.HeartRateBpm)] =
                $"Each heart rate must be 0 or between {MinimumHeartRateBpm} and {MaximumHeartRateBpm}.";
        }
        else if (intervalValid && duration > TimeSpan.Zero &&
                 heartRate.Count > Math.Ceiling(duration.TotalSeconds / session.SampleIntervalSeconds) + 1)
        {
            errors[nameof(CardioSessionValues.HeartRateBpm)] = "There are more heart rate values than the duration allows.";
        }

        IReadOnlyList<int> rr = session.RrIntervalsMs ?? [];
        if (rr.Count > MaximumRrIntervals)
        {
            errors[nameof(CardioSessionValues.RrIntervalsMs)] = $"At most {MaximumRrIntervals} RR intervals are allowed.";
        }
        else if (rr.Any(value => value < MinimumRrMs || value > MaximumRrMs))
        {
            errors[nameof(CardioSessionValues.RrIntervalsMs)] =
                $"Each RR interval must be between {MinimumRrMs} and {MaximumRrMs} ms.";
        }

        string? sensorName = WorkoutValidation.NormalizeText(session.SensorName);
        if (sensorName?.Length > MaximumSensorNameLength)
        {
            errors[nameof(CardioSessionValues.SensorName)] = $"The sensor name cannot exceed {MaximumSensorNameLength} characters.";
        }
        ValidateRange(session.DistanceKm, MaximumDistanceKm, nameof(CardioSessionValues.DistanceKm), errors);
        ValidateRange(session.AveragePowerWatts, MaximumPowerWatts, nameof(CardioSessionValues.AveragePowerWatts), errors);
        ValidateRange(session.EnergyKcal, MaximumEnergyKcal, nameof(CardioSessionValues.EnergyKcal), errors);
        string? notes = WorkoutValidation.NormalizeText(session.Notes);
        if (notes?.Length > MaximumNotesLength)
        {
            errors[nameof(CardioSessionValues.Notes)] = $"Notes cannot exceed {MaximumNotesLength} characters.";
        }

        if (errors.Count > 0)
        {
            throw new CardioSessionValidationException(errors);
        }
        return new CardioSessionValues(
            session.SessionId,
            session.ActivityType,
            startedAtUtc,
            endedAtUtc,
            session.TargetZone,
            session.SampleIntervalSeconds,
            heartRate.ToArray(),
            rr.ToArray(),
            sensorName,
            session.DistanceKm,
            session.AveragePowerWatts,
            session.EnergyKcal,
            notes);
    }

    private static void ValidateRange(decimal? value, decimal maximum, string key, Dictionary<string, string> errors)
    {
        if (value is < 0m || value > maximum)
        {
            errors[key] = $"The value must be between 0 and {maximum}.";
        }
    }
}
