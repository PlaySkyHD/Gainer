namespace Gainer.Core.Training;

/// <summary>Checks the shape and bounds of a workout against the sync contract and returns the normalized values.</summary>
public static class WorkoutValidation
{
    public const int MaximumExercises = 50;
    public const int MaximumSetsPerExercise = 50;

    private const int MaximumTitleLength = 160;
    private const int MaximumNotesLength = 2_000;
    private const decimal MaximumWeightKg = 10_000m;
    private const int MaximumRepetitions = 10_000;
    private const decimal MaximumRir = 10m;

    public static WorkoutValues Normalize(WorkoutValues workout)
    {
        ArgumentNullException.ThrowIfNull(workout);
        var errors = new Dictionary<string, string>(StringComparer.Ordinal);
        string title = workout.Title?.Trim() ?? string.Empty;
        if (title.Length is < 1 or > MaximumTitleLength)
        {
            errors[nameof(WorkoutValues.Title)] = "Title must contain between 1 and 160 characters.";
        }
        ValidateNotes(workout.Notes, nameof(WorkoutValues.Notes), errors);
        DateTime startedAtUtc = ToUtc(workout.StartedAtUtc);
        DateTime? endedAtUtc = workout.EndedAtUtc is { } ended ? ToUtc(ended) : null;
        if (endedAtUtc is { } end && end <= startedAtUtc)
        {
            errors[nameof(WorkoutValues.EndedAtUtc)] = "The end must be after the start.";
        }
        if (!PreviousValueSources.TryParse(workout.PreviousValueSource, out _))
        {
            errors[nameof(WorkoutValues.PreviousValueSource)] = "The previous value source is unknown.";
        }
        if (workout.SourcePlanId == Guid.Empty)
        {
            errors[nameof(WorkoutValues.SourcePlanId)] = "The source plan identifier cannot be empty.";
        }
        if (workout.SourceWorkoutId == Guid.Empty)
        {
            errors[nameof(WorkoutValues.SourceWorkoutId)] = "The source workout identifier cannot be empty.";
        }
        if (workout.Exercises.Count > MaximumExercises)
        {
            errors[nameof(WorkoutValues.Exercises)] = $"A workout cannot contain more than {MaximumExercises} exercises.";
        }
        if (workout.Exercises.Any(item => item.WorkoutExerciseId == Guid.Empty) ||
            workout.Exercises.Select(item => item.WorkoutExerciseId).Distinct().Count() != workout.Exercises.Count)
        {
            errors["Exercises.WorkoutExerciseId"] = "Workout exercise identifiers must be non-empty and unique.";
        }

        var setIds = new HashSet<Guid>();
        var normalized = new List<WorkoutExerciseValues>(workout.Exercises.Count);
        for (int index = 0; index < workout.Exercises.Count; index++)
        {
            normalized.Add(NormalizeExercise(workout.Exercises[index], $"Exercises[{index}]", setIds, errors));
        }
        if (errors.Count > 0)
        {
            throw new WorkoutValidationException(errors);
        }
        return new WorkoutValues(
            workout.WorkoutId,
            title,
            NormalizeText(workout.Notes),
            startedAtUtc,
            endedAtUtc,
            PreviousValueSources.ToStorageValue(PreviousValueSources.Parse(workout.PreviousValueSource)),
            workout.SourcePlanId,
            workout.SourceWorkoutId,
            normalized);
    }

    private static WorkoutExerciseValues NormalizeExercise(
        WorkoutExerciseValues exercise,
        string prefix,
        HashSet<Guid> setIds,
        Dictionary<string, string> errors)
    {
        string name = exercise.ExerciseNameSnapshot?.Trim() ?? string.Empty;
        if (name.Length is < 1 or > MaximumTitleLength)
        {
            errors[$"{prefix}.ExerciseNameSnapshot"] = "Exercise name must contain between 1 and 160 characters.";
        }
        string storedType = ExerciseTypes.TryParse(exercise.ExerciseTypeSnapshot, out ExerciseType exerciseType)
            ? ExerciseTypes.ToStorageValue(exerciseType)
            : string.Empty;
        if (storedType.Length == 0)
        {
            errors[$"{prefix}.ExerciseTypeSnapshot"] = "The exercise type is unknown.";
        }
        if (exercise.SourceExerciseId == Guid.Empty)
        {
            errors[$"{prefix}.SourceExerciseId"] = "The source exercise identifier cannot be empty.";
        }
        if (exercise.SupersetId == Guid.Empty)
        {
            errors[$"{prefix}.SupersetId"] = "The superset identifier cannot be empty.";
        }
        ValidateNotes(exercise.Notes, $"{prefix}.Notes", errors);
        if (exercise.Sets.Count > MaximumSetsPerExercise)
        {
            errors[$"{prefix}.Sets"] = $"An exercise cannot contain more than {MaximumSetsPerExercise} sets.";
        }

        var sets = new List<WorkoutSetValues>(exercise.Sets.Count);
        for (int index = 0; index < exercise.Sets.Count; index++)
        {
            sets.Add(NormalizeSet(exercise.Sets[index], $"{prefix}.Sets[{index}]", setIds, errors));
        }

        return new WorkoutExerciseValues(
            exercise.WorkoutExerciseId,
            exercise.SourceExerciseId,
            name,
            storedType,
            NormalizeText(exercise.Notes),
            exercise.SupersetId,
            sets);
    }

    private static WorkoutSetValues NormalizeSet(
        WorkoutSetValues set,
        string setPrefix,
        HashSet<Guid> setIds,
        Dictionary<string, string> errors)
    {
        if (set.SetId == Guid.Empty || !setIds.Add(set.SetId))
        {
            errors[$"{setPrefix}.SetId"] = "Set identifiers must be non-empty and unique.";
        }
        if (set.WeightKg is { } weight && (weight < 0 || weight > MaximumWeightKg))
        {
            errors[$"{setPrefix}.WeightKg"] = "Weight must be between 0 and 10000 kg.";
        }
        if (set.Repetitions is { } repetitions && (repetitions < 0 || repetitions > MaximumRepetitions))
        {
            errors[$"{setPrefix}.Repetitions"] = "Repetitions must be between 0 and 10000.";
        }
        if (set.Rir is { } rir && (rir < 0 || rir > MaximumRir))
        {
            errors[$"{setPrefix}.Rir"] = "RIR must be between 0 and 10.";
        }
        ValidateNotes(set.Notes, $"{setPrefix}.Notes", errors);
        return set with
        {
            SetType = WorkoutSetTypes.ToStorageValue(WorkoutSetTypes.ParseOrNormal(set.SetType)),
            Notes = NormalizeText(set.Notes),
        };
    }

    private static void ValidateNotes(string? notes, string key, Dictionary<string, string> errors)
    {
        if (notes?.Trim().Length > MaximumNotesLength)
        {
            errors[key] = "Notes cannot exceed 2000 characters.";
        }
    }

    internal static string? NormalizeText(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    /// <summary>Client timestamps are UTC; unspecified values are treated as UTC and local values are converted.</summary>
    internal static DateTime ToUtc(DateTime value) => value.Kind switch
    {
        DateTimeKind.Utc => value,
        DateTimeKind.Local => value.ToUniversalTime(),
        _ => DateTime.SpecifyKind(value, DateTimeKind.Utc),
    };
}
