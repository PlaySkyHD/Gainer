namespace Gainer.Core.Training;

/// <summary>Checks the shape and bounds of a training plan against the sync contract and returns the normalized values.</summary>
public static class TrainingPlanValidation
{
    public const int MaximumEntries = 50;
    public const int MaximumPlansPerReorder = 50;

    private const int MaximumNameLength = 160;
    private const int MaximumNotesLength = 2_000;
    private const int MaximumWarmupSets = 20;
    private const int MaximumWorkingSets = 50;
    private const int MaximumSetsPerEntry = 50;

    public static TrainingPlanValues Normalize(TrainingPlanValues plan)
    {
        ArgumentNullException.ThrowIfNull(plan);
        var errors = new Dictionary<string, string>(StringComparer.Ordinal);
        string name = plan.Name?.Trim() ?? string.Empty;
        ValidatePlan(plan, name, errors);

        var normalized = new List<TrainingPlanEntryValues>(plan.Entries.Count);
        for (int index = 0; index < plan.Entries.Count; index++)
        {
            TrainingPlanEntryValues entry = plan.Entries[index];
            ValidateEntry(entry, $"Entries[{index}]", errors);
            normalized.Add(entry with { Notes = NormalizeText(entry.Notes) });
        }
        if (errors.Count > 0)
        {
            throw new TrainingPlanValidationException(errors);
        }
        return new TrainingPlanValues(
            plan.PlanId,
            name,
            NormalizeText(plan.Notes),
            PreviousValueSources.ToStorageValue(PreviousValueSources.Parse(plan.PreviousValueSource)),
            normalized);
    }

    private static void ValidatePlan(TrainingPlanValues plan, string name, Dictionary<string, string> errors)
    {
        if (name.Length is < 1 or > MaximumNameLength)
        {
            errors[nameof(TrainingPlanValues.Name)] = "Name must contain between 1 and 160 characters.";
        }
        if (plan.Notes?.Trim().Length > MaximumNotesLength)
        {
            errors[nameof(TrainingPlanValues.Notes)] = "Notes cannot exceed 2000 characters.";
        }
        if (!PreviousValueSources.TryParse(plan.PreviousValueSource, out _))
        {
            errors[nameof(TrainingPlanValues.PreviousValueSource)] = "The previous value source is unknown.";
        }
        if (plan.Entries.Count > MaximumEntries)
        {
            errors[nameof(TrainingPlanValues.Entries)] = $"A plan cannot contain more than {MaximumEntries} entries.";
        }
        if (plan.Entries.Any(item => item.EntryId == Guid.Empty) ||
            plan.Entries.Select(item => item.EntryId).Distinct().Count() != plan.Entries.Count)
        {
            errors["Entries.EntryId"] = "Plan entry identifiers must be non-empty and unique.";
        }
    }

    private static void ValidateEntry(TrainingPlanEntryValues entry, string prefix, Dictionary<string, string> errors)
    {
        if (entry.ExerciseId == Guid.Empty)
        {
            errors[$"{prefix}.ExerciseId"] = "The exercise identifier cannot be empty.";
        }
        if (entry.WarmupSets is < 0 or > MaximumWarmupSets)
        {
            errors[$"{prefix}.WarmupSets"] = "Warmup sets must be between 0 and 20.";
        }
        if (entry.WorkingSets is < 0 or > MaximumWorkingSets)
        {
            errors[$"{prefix}.WorkingSets"] = "Working sets must be between 0 and 50.";
        }
        else if (entry.WarmupSets + entry.WorkingSets is < 1 or > MaximumSetsPerEntry)
        {
            errors[$"{prefix}.WorkingSets"] = "An entry requires between 1 and 50 sets in total.";
        }
        if (entry.Notes?.Trim().Length > MaximumNotesLength)
        {
            errors[$"{prefix}.Notes"] = "Notes cannot exceed 2000 characters.";
        }
        if (entry.SupersetId == Guid.Empty)
        {
            errors[$"{prefix}.SupersetId"] = "The superset identifier cannot be empty.";
        }
    }

    internal static string? NormalizeText(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
