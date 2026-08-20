using Gainer.Core.Security;
using Gainer.Core.Mutations;

namespace Gainer.Core.Nutrition;

public enum NutritionTargetOrigin
{
    Manual = 1,
}

public enum NutritionGoalCategory
{
    Custom = 1,
    Cut = 2,
    Maintenance = 3,
    Bulk = 4,
}

public enum NutritionTargetInputMode
{
    Grams = 1,
    Percent = 2,
}

public sealed class NutritionTargetSchedule : UserOwnedEntity
{
    public Guid Id { get; init; }
    public DateTime CreatedAtUtc { get; init; }
    public DateTime UpdatedAtUtc { get; set; }
    public long Version { get; set; }
    public ICollection<NutritionTargetVersion> Versions { get; } = new List<NutritionTargetVersion>();
}

public sealed class NutritionTargetVersion : UserOwnedEntity
{
    public Guid Id { get; init; }
    public Guid NutritionTargetScheduleId { get; init; }
    public NutritionTargetSchedule NutritionTargetSchedule { get; init; } = null!;
    public DateOnly EffectiveFrom { get; set; }
    public DateOnly? EffectiveUntil { get; set; }
    public string Name { get; set; } = string.Empty;
    public NutritionGoalCategory Category { get; set; }
    public NutritionTargetInputMode InputMode { get; set; }
    public decimal Kilocalories { get; set; }
    public decimal ProteinGrams { get; set; }
    public decimal CarbohydrateGrams { get; set; }
    public decimal FatGrams { get; set; }
    public decimal? ProteinPercent { get; set; }
    public decimal? CarbohydratePercent { get; set; }
    public decimal? FatPercent { get; set; }
    public NutritionTargetOrigin Origin { get; set; }
    public string? AlgorithmVersion { get; set; }
    public string? Reason { get; set; }
}

public sealed record NutritionTargetVersionDraft(
    Guid TargetVersionId,
    string Name,
    NutritionGoalCategory Category,
    DateOnly EffectiveFrom,
    DateOnly? EffectiveUntil,
    decimal Kilocalories,
    NutritionTargetInputMode InputMode,
    decimal ProteinGrams,
    decimal CarbohydrateGrams,
    decimal FatGrams,
    decimal? ProteinPercent,
    decimal? CarbohydratePercent,
    decimal? FatPercent,
    NutritionTargetOrigin Origin,
    string? AlgorithmVersion,
    string? Reason,
    decimal MacroEnergyKilocalories,
    bool RequiresEnergyMismatchConfirmation)
{
    public static NutritionTargetVersionDraft Create(
        Guid targetVersionId,
        DateOnly effectiveFrom,
        decimal kilocalories,
        decimal proteinGrams,
        decimal carbohydrateGrams,
        decimal fatGrams,
        NutritionTargetOrigin origin,
        string? algorithmVersion,
        string? reason)
        => CreateInGrams(
            targetVersionId,
            "Ziel",
            NutritionGoalCategory.Custom,
            effectiveFrom,
            null,
            kilocalories,
            proteinGrams,
            carbohydrateGrams,
            fatGrams,
            origin,
            algorithmVersion,
            reason);

    public static NutritionTargetVersionDraft CreateInGrams(
        Guid targetVersionId,
        string name,
        NutritionGoalCategory category,
        DateOnly effectiveFrom,
        DateOnly? effectiveUntil,
        decimal kilocalories,
        decimal proteinGrams,
        decimal carbohydrateGrams,
        decimal fatGrams,
        NutritionTargetOrigin origin = NutritionTargetOrigin.Manual,
        string? algorithmVersion = null,
        string? reason = null)
        => CreateCore(
            targetVersionId,
            name,
            category,
            effectiveFrom,
            effectiveUntil,
            kilocalories,
            NutritionTargetInputMode.Grams,
            proteinGrams,
            carbohydrateGrams,
            fatGrams,
            null,
            null,
            null,
            origin,
            algorithmVersion,
            reason);

    public static NutritionTargetVersionDraft CreateInPercent(
        Guid targetVersionId,
        string name,
        NutritionGoalCategory category,
        DateOnly effectiveFrom,
        DateOnly? effectiveUntil,
        decimal kilocalories,
        decimal proteinPercent,
        decimal carbohydratePercent,
        decimal fatPercent,
        NutritionTargetOrigin origin = NutritionTargetOrigin.Manual,
        string? algorithmVersion = null,
        string? reason = null)
    {
        NutritionTotals derived = NutritionCalculator.CalculateMacroTargetsFromPercent(
            kilocalories, proteinPercent, carbohydratePercent, fatPercent);
        return CreateCore(
            targetVersionId,
            name,
            category,
            effectiveFrom,
            effectiveUntil,
            kilocalories,
            NutritionTargetInputMode.Percent,
            derived.ProteinGrams!.Value,
            derived.CarbohydrateGrams!.Value,
            derived.FatGrams!.Value,
            proteinPercent,
            carbohydratePercent,
            fatPercent,
            origin,
            algorithmVersion,
            reason);
    }

    public static NutritionTargetVersionDraft Restore(
        Guid targetVersionId,
        string name,
        NutritionGoalCategory category,
        DateOnly effectiveFrom,
        DateOnly? effectiveUntil,
        decimal kilocalories,
        NutritionTargetInputMode inputMode,
        decimal proteinGrams,
        decimal carbohydrateGrams,
        decimal fatGrams,
        decimal? proteinPercent,
        decimal? carbohydratePercent,
        decimal? fatPercent,
        NutritionTargetOrigin origin,
        string? algorithmVersion,
        string? reason)
        => CreateCore(
            targetVersionId, name, category, effectiveFrom, effectiveUntil, kilocalories, inputMode,
            proteinGrams, carbohydrateGrams, fatGrams, proteinPercent, carbohydratePercent, fatPercent,
            origin, algorithmVersion, reason);

    private static NutritionTargetVersionDraft CreateCore(
        Guid targetVersionId,
        string name,
        NutritionGoalCategory category,
        DateOnly effectiveFrom,
        DateOnly? effectiveUntil,
        decimal kilocalories,
        NutritionTargetInputMode inputMode,
        decimal proteinGrams,
        decimal carbohydrateGrams,
        decimal fatGrams,
        decimal? proteinPercent,
        decimal? carbohydratePercent,
        decimal? fatPercent,
        NutritionTargetOrigin origin,
        string? algorithmVersion,
        string? reason)
    {
        var errors = new Dictionary<string, string>(StringComparer.Ordinal);
        if (targetVersionId == Guid.Empty) errors[nameof(TargetVersionId)] = "TargetVersionId cannot be empty.";
        string normalizedName = name?.Trim() ?? string.Empty;
        if (normalizedName.Length is 0 or > NutritionLimits.MaxTargetPhaseNameLength)
            errors[nameof(Name)] = $"Name must contain 1 to {NutritionLimits.MaxTargetPhaseNameLength} characters.";
        if (!Enum.IsDefined(category)) errors[nameof(Category)] = "Category is invalid.";
        if (!Enum.IsDefined(inputMode)) errors[nameof(InputMode)] = "Input mode is invalid.";
        if (effectiveUntil < effectiveFrom) errors[nameof(EffectiveUntil)] = "EffectiveUntil cannot be before EffectiveFrom.";
        ValidateTarget(kilocalories, NutritionLimits.MaxDailyKilocalories, nameof(Kilocalories), errors);
        ValidateTarget(proteinGrams, NutritionLimits.MaxDailyMacroGrams, nameof(ProteinGrams), errors);
        ValidateTarget(carbohydrateGrams, NutritionLimits.MaxDailyMacroGrams, nameof(CarbohydrateGrams), errors);
        ValidateTarget(fatGrams, NutritionLimits.MaxDailyMacroGrams, nameof(FatGrams), errors);
        if (origin != NutritionTargetOrigin.Manual) errors[nameof(Origin)] = "Only manually entered nutrition targets are supported.";
        string? normalizedAlgorithmVersion = string.IsNullOrWhiteSpace(algorithmVersion) ? null : algorithmVersion.Trim();
        string? normalizedReason = string.IsNullOrWhiteSpace(reason) ? null : reason.Trim();
        if (normalizedAlgorithmVersion?.Length > 80) errors[nameof(AlgorithmVersion)] = "AlgorithmVersion is too long.";
        if (normalizedReason?.Length > 500) errors[nameof(Reason)] = "Reason is too long.";
        if (normalizedAlgorithmVersion is not null) errors[nameof(AlgorithmVersion)] = "Manual targets cannot have an algorithm version.";
        if (normalizedReason is not null) errors[nameof(Reason)] = "Manual targets cannot have an automated reason.";
        if (inputMode == NutritionTargetInputMode.Grams &&
            (proteinPercent is not null || carbohydratePercent is not null || fatPercent is not null))
            errors["MacroDistribution"] = "Gram targets cannot contain percentage values.";
        if (inputMode == NutritionTargetInputMode.Percent)
        {
            if (proteinPercent is null || carbohydratePercent is null || fatPercent is null)
            {
                errors["MacroDistribution"] = "Percentage targets require all three macro percentages.";
            }
            else
            {
                try
                {
                    NutritionTotals derived = NutritionCalculator.CalculateMacroTargetsFromPercent(
                        kilocalories, proteinPercent.Value, carbohydratePercent.Value, fatPercent.Value);
                    if (derived.ProteinGrams != proteinGrams ||
                        derived.CarbohydrateGrams != carbohydrateGrams ||
                        derived.FatGrams != fatGrams)
                        errors["MacroDistribution"] = "Derived gram targets do not match the percentage distribution.";
                }
                catch (NutritionValidationException exception)
                {
                    foreach ((string field, string error) in exception.Errors) errors[field] = error;
                }
            }
        }
        if (errors.Count > 0) throw new NutritionValidationException(errors);

        decimal macroEnergy = NutritionCalculator.CalculateMacroEnergy(proteinGrams, carbohydrateGrams, fatGrams);
        return new NutritionTargetVersionDraft(
            targetVersionId, normalizedName, category, effectiveFrom, effectiveUntil, kilocalories, inputMode,
            proteinGrams, carbohydrateGrams, fatGrams, proteinPercent, carbohydratePercent, fatPercent,
            origin, normalizedAlgorithmVersion, normalizedReason, macroEnergy,
            NutritionCalculator.HasMacroEnergyMismatch(kilocalories, proteinGrams, carbohydrateGrams, fatGrams));
    }

    private static void ValidateTarget(decimal value, decimal max, string field, IDictionary<string, string> errors)
    {
        if (value is <= 0m || value > max) errors[field] = $"{field} must be positive and no greater than {max}.";
    }
}

public sealed record NutritionTargetScheduleDraft(IReadOnlyList<NutritionTargetVersionDraft> Versions)
{
    public static NutritionTargetScheduleDraft Create(IEnumerable<NutritionTargetVersionDraft> versions)
    {
        ArgumentNullException.ThrowIfNull(versions);
        NutritionTargetVersionDraft[] ordered = versions.OrderBy(item => item.EffectiveFrom).ToArray();
        var errors = new Dictionary<string, string>(StringComparer.Ordinal);
        if (ordered.Length is 0 || ordered.Length > NutritionLimits.MaxTargetVersions)
            errors[nameof(Versions)] = $"A schedule must contain 1 to {NutritionLimits.MaxTargetVersions} versions.";
        else if (ordered.Select(item => item.TargetVersionId).Distinct().Count() != ordered.Length ||
                 ordered.Select(item => item.EffectiveFrom).Distinct().Count() != ordered.Length)
            errors[nameof(Versions)] = "Target version identifiers and effective dates must be unique.";
        else if (ordered.Zip(ordered.Skip(1), (current, next) =>
                     current.EffectiveUntil is null || current.EffectiveUntil >= next.EffectiveFrom).Any(overlaps => overlaps))
            errors[nameof(Versions)] = "Nutrition target phases cannot overlap.";
        if (errors.Count > 0) throw new NutritionValidationException(errors);
        return new NutritionTargetScheduleDraft(ordered);
    }

    public NutritionTargetVersionDraft? GetEffective(DateOnly localDate) =>
        Versions.LastOrDefault(item => item.EffectiveFrom <= localDate &&
            (item.EffectiveUntil is null || item.EffectiveUntil >= localDate));
}

public sealed record NutritionTargetScheduleSnapshot(
    Guid NutritionTargetScheduleId,
    IReadOnlyList<NutritionTargetVersionDraft> Versions,
    DateTime CreatedAtUtc,
    DateTime UpdatedAtUtc,
    long Version) : IResourceSnapshot
{
    public ResourceKey Resource => ResourceKey.Create(ResourceKind.NutritionTargetSchedule, NutritionTargetScheduleId);

    public NutritionTargetVersionDraft? GetEffective(DateOnly localDate) =>
        Versions.LastOrDefault(item => item.EffectiveFrom <= localDate &&
            (item.EffectiveUntil is null || item.EffectiveUntil >= localDate));
}

public sealed record SaveNutritionTargetScheduleMutation : ITypedMutation<NutritionTargetScheduleSnapshot>
{
    private SaveNutritionTargetScheduleMutation(
        MutationMetadata metadata,
        Guid nutritionTargetScheduleId,
        long baseVersion,
        NutritionTargetScheduleDraft values)
    {
        Metadata = metadata;
        NutritionTargetScheduleId = nutritionTargetScheduleId;
        BaseVersion = baseVersion;
        Values = values;
        Scope = AtomicMutationScope.Create(ResourceVersionExpectation.Create(
            ResourceKey.Create(ResourceKind.NutritionTargetSchedule, nutritionTargetScheduleId), baseVersion));
    }

    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }
    public Guid NutritionTargetScheduleId { get; }
    public long BaseVersion { get; }
    public NutritionTargetScheduleDraft Values { get; }

    public static SaveNutritionTargetScheduleMutation Create(
        MutationMetadata metadata,
        Guid nutritionTargetScheduleId,
        long baseVersion,
        NutritionTargetScheduleDraft values)
    {
        ArgumentNullException.ThrowIfNull(metadata);
        ArgumentNullException.ThrowIfNull(values);
        if (nutritionTargetScheduleId == Guid.Empty) throw new ArgumentException("Nutrition target schedule identifier cannot be empty.", nameof(nutritionTargetScheduleId));
        if (baseVersion < 0) throw new ArgumentOutOfRangeException(nameof(baseVersion));
        return new SaveNutritionTargetScheduleMutation(metadata, nutritionTargetScheduleId, baseVersion, values);
    }
}

public interface INutritionTargetScheduleMutationHandler
{
    Task<NutritionTargetScheduleSnapshot> SaveAsync(
        SaveNutritionTargetScheduleMutation mutation,
        CancellationToken cancellationToken = default);
}

public sealed class NutritionTargetScheduleConflictException(string message) : Exception(message);
public sealed class NutritionTargetScheduleNotFoundException : Exception;
