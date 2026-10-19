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
    private const int MaximumTemplateNameLength = 100;
    private const int MaximumPhases = 30;
    private const int MinimumPhaseSeconds = 30;
    private const int MaximumPhaseSeconds = 3_600;
    private const int MaximumPlannedSeconds = 4 * 3_600;
    private const int MaximumPhaseNameLength = 60;
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

        if ((session.RecoveryStartBpm is null) != (session.RecoveryEndBpm is null))
        {
            errors[nameof(CardioSessionValues.RecoveryStartBpm)] = "Recovery start and end must be set together.";
        }
        else if (session.RecoveryStartBpm is { } recoveryStart && session.RecoveryEndBpm is { } recoveryEnd &&
                 (recoveryStart is < MinimumHeartRateBpm or > MaximumHeartRateBpm ||
                  recoveryEnd is < MinimumHeartRateBpm or > MaximumHeartRateBpm))
        {
            errors[nameof(CardioSessionValues.RecoveryStartBpm)] =
                $"Recovery heart rates must be between {MinimumHeartRateBpm} and {MaximumHeartRateBpm}.";
        }

        string? templateName = WorkoutValidation.NormalizeText(session.TemplateName);
        if (templateName?.Length > MaximumTemplateNameLength)
        {
            errors[nameof(CardioSessionValues.TemplateName)] =
                $"The template name cannot exceed {MaximumTemplateNameLength} characters.";
        }

        IReadOnlyList<CardioPhaseValues>? phases = NormalizePhases(session.Phases, errors);

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
            notes,
            session.RecoveryStartBpm,
            session.RecoveryEndBpm,
            templateName,
            phases);
    }

    private static IReadOnlyList<CardioPhaseValues>? NormalizePhases(
        IReadOnlyList<CardioPhaseValues>? phases,
        Dictionary<string, string> errors)
    {
        if (phases is null || phases.Count == 0)
        {
            return null;
        }
        const string key = nameof(CardioSessionValues.Phases);
        if (phases.Count > MaximumPhases)
        {
            errors[key] = $"At most {MaximumPhases} phases are allowed.";
            return null;
        }

        var result = new List<CardioPhaseValues>(phases.Count);
        long previousEnd = 0;
        foreach (CardioPhaseValues phase in phases)
        {
            if (phase is null)
            {
                errors[key] = "A phase cannot be empty.";
                return null;
            }
            string name = (phase.Name ?? string.Empty).Trim();
            if (name.Length is < 1 or > MaximumPhaseNameLength)
            {
                errors[key] = $"A phase name must be between 1 and {MaximumPhaseNameLength} characters.";
                return null;
            }
            if (phase.DurationSeconds is < MinimumPhaseSeconds or > MaximumPhaseSeconds)
            {
                errors[key] = $"A phase must last between {MinimumPhaseSeconds} and {MaximumPhaseSeconds} seconds.";
                return null;
            }
            if (phase.StartOffsetSeconds < previousEnd)
            {
                errors[key] = "Phases must be in order, start at 0 or later and must not overlap.";
                return null;
            }
            if ((phase.LowBpm is null) != (phase.HighBpm is null) ||
                (phase.LowBpm is { } low && phase.HighBpm is { } high &&
                 (low < MinimumZoneBpm || high > MaximumZoneBpm || low >= high)))
            {
                errors[key] = $"A phase zone must be set together and satisfy {MinimumZoneBpm} <= low < high <= {MaximumZoneBpm}.";
                return null;
            }
            long end = (long)phase.StartOffsetSeconds + phase.DurationSeconds;
            if (end > MaximumPlannedSeconds)
            {
                errors[key] = "The phases cannot exceed 4 hours in total.";
                return null;
            }
            previousEnd = end;
            result.Add(phase with { Name = name });
        }
        return result;
    }

    private static void ValidateRange(decimal? value, decimal maximum, string key, Dictionary<string, string> errors)
    {
        if (value is < 0m || value > maximum)
        {
            errors[key] = $"The value must be between 0 and {maximum}.";
        }
    }
}
