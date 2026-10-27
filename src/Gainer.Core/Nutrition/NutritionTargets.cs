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

    /// <summary>Daily salt limit in grams; null means the default of <see cref="NutritionLimits.DefaultDailySaltTargetGrams"/>.</summary>
    public decimal? SaltGrams { get; set; }

    /// <summary>Daily fiber minimum in grams; null means the default of <see cref="NutritionLimits.DefaultDailyFiberTargetGrams"/>.</summary>
    public decimal? FiberGrams { get; set; }

    /// <summary>Separate rest day target; present exactly when <see cref="RestKilocalories"/> is set.</summary>
    public NutritionTargetInputMode? RestInputMode { get; set; }
    public decimal? RestKilocalories { get; set; }
    public decimal? RestProteinGrams { get; set; }
    public decimal? RestCarbohydrateGrams { get; set; }
    public decimal? RestFatGrams { get; set; }
    public decimal? RestProteinPercent { get; set; }
    public decimal? RestCarbohydratePercent { get; set; }
    public decimal? RestFatPercent { get; set; }
    public NutritionTargetOrigin Origin { get; set; }
    public string? AlgorithmVersion { get; set; }
    public string? Reason { get; set; }
}

/// <summary>Identity, name, category and effective period of a nutrition target phase.</summary>
public sealed record NutritionTargetPhase(
    Guid TargetVersionId,
    string Name,
    NutritionGoalCategory Category,
    DateOnly EffectiveFrom,
    DateOnly? EffectiveUntil = null);

/// <summary>Daily energy and macro targets in grams, with the percentages when they were entered as a distribution.</summary>
public readonly record struct NutritionMacroTargets(
    decimal Kilocalories,
    decimal ProteinGrams,
    decimal CarbohydrateGrams,
    decimal FatGrams,
    decimal? ProteinPercent = null,
    decimal? CarbohydratePercent = null,
    decimal? FatPercent = null);

/// <summary>Optional salt and fiber targets plus the origin metadata of a nutrition target version.</summary>
public sealed record NutritionTargetOptions(
    NutritionTargetOrigin Origin = NutritionTargetOrigin.Manual,
    string? AlgorithmVersion = null,
    string? Reason = null,
    decimal? SaltGrams = null,
    decimal? FiberGrams = null);

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
    bool RequiresEnergyMismatchConfirmation,
    decimal? SaltGrams = null,
    NutritionRestDayTargetDraft? RestDay = null,
    decimal? FiberGrams = null)
{
    /// <summary>The salt limit that applies, falling back to the default when none is set.</summary>
    public decimal EffectiveSaltGrams => SaltGrams ?? NutritionLimits.DefaultDailySaltTargetGrams;

    /// <summary>The fiber minimum that applies, falling back to the default when none is set.</summary>
    public decimal EffectiveFiberGrams => FiberGrams ?? NutritionLimits.DefaultDailyFiberTargetGrams;

    public static NutritionTargetVersionDraft Create(
        Guid targetVersionId,
        DateOnly effectiveFrom,
        NutritionMacroTargets macros,
        NutritionTargetOptions? options = null)
        => CreateInGrams(
            new NutritionTargetPhase(targetVersionId, "Ziel", NutritionGoalCategory.Custom, effectiveFrom),
            macros,
            options);

    public static NutritionTargetVersionDraft CreateInGrams(
        NutritionTargetPhase phase,
        NutritionMacroTargets macros,
        NutritionTargetOptions? options = null)
        => CreateCore(
            phase,
            NutritionTargetInputMode.Grams,
            macros with { ProteinPercent = null, CarbohydratePercent = null, FatPercent = null },
            options ?? new NutritionTargetOptions());

    public static NutritionTargetVersionDraft CreateInPercent(
        NutritionTargetPhase phase,
        decimal kilocalories,
        decimal proteinPercent,
        decimal carbohydratePercent,
        decimal fatPercent,
        NutritionTargetOptions? options = null)
    {
        NutritionTotals derived = NutritionCalculator.CalculateMacroTargetsFromPercent(
            kilocalories, proteinPercent, carbohydratePercent, fatPercent);
        return CreateCore(
            phase,
            NutritionTargetInputMode.Percent,
            new NutritionMacroTargets(
                kilocalories,
                derived.ProteinGrams!.Value,
                derived.CarbohydrateGrams!.Value,
                derived.FatGrams!.Value,
                proteinPercent,
                carbohydratePercent,
                fatPercent),
            options ?? new NutritionTargetOptions());
    }

    public static NutritionTargetVersionDraft Restore(
        NutritionTargetPhase phase,
        NutritionTargetInputMode inputMode,
        NutritionMacroTargets macros,
        NutritionTargetOptions options,
        NutritionRestDayTargetDraft? restDay = null)
        => CreateCore(phase, inputMode, macros, options, restDay);

    private static NutritionTargetVersionDraft CreateCore(
        NutritionTargetPhase phase,
        NutritionTargetInputMode inputMode,
        NutritionMacroTargets macros,
        NutritionTargetOptions options,
        NutritionRestDayTargetDraft? restDay = null)
    {
        ArgumentNullException.ThrowIfNull(phase);
        ArgumentNullException.ThrowIfNull(options);
        (Guid targetVersionId, string name, NutritionGoalCategory category, DateOnly effectiveFrom, DateOnly? effectiveUntil) =
            (phase.TargetVersionId, phase.Name, phase.Category, phase.EffectiveFrom, phase.EffectiveUntil);
        (decimal kilocalories, decimal proteinGrams, decimal carbohydrateGrams, decimal fatGrams) =
            (macros.Kilocalories, macros.ProteinGrams, macros.CarbohydrateGrams, macros.FatGrams);
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
        if (options.SaltGrams is not null) ValidateTarget(options.SaltGrams.Value, NutritionLimits.MaxDailySaltTargetGrams, nameof(SaltGrams), errors);
        if (options.FiberGrams is not null) ValidateTarget(options.FiberGrams.Value, NutritionLimits.MaxDailyFiberTargetGrams, nameof(FiberGrams), errors);
        if (options.Origin != NutritionTargetOrigin.Manual) errors[nameof(Origin)] = "Only manually entered nutrition targets are supported.";
        string? normalizedAlgorithmVersion = string.IsNullOrWhiteSpace(options.AlgorithmVersion) ? null : options.AlgorithmVersion.Trim();
        string? normalizedReason = string.IsNullOrWhiteSpace(options.Reason) ? null : options.Reason.Trim();
        ValidateAutomationMetadata(normalizedAlgorithmVersion, normalizedReason, errors);
        ValidateMacroDistribution(inputMode, macros, errors);
        if (errors.Count > 0) throw new NutritionValidationException(errors);

        decimal macroEnergy = NutritionCalculator.CalculateMacroEnergy(proteinGrams, carbohydrateGrams, fatGrams);
        return new NutritionTargetVersionDraft(
            targetVersionId, normalizedName, category, effectiveFrom, effectiveUntil, kilocalories, inputMode,
            proteinGrams, carbohydrateGrams, fatGrams, macros.ProteinPercent, macros.CarbohydratePercent, macros.FatPercent,
            options.Origin, normalizedAlgorithmVersion, normalizedReason, macroEnergy,
            NutritionCalculator.HasMacroEnergyMismatch(kilocalories, proteinGrams, carbohydrateGrams, fatGrams),
            options.SaltGrams,
            restDay,
            options.FiberGrams);
    }

    private static void ValidateAutomationMetadata(string? algorithmVersion, string? reason, Dictionary<string, string> errors)
    {
        if (algorithmVersion?.Length > 80) errors[nameof(AlgorithmVersion)] = "AlgorithmVersion is too long.";
        if (reason?.Length > 500) errors[nameof(Reason)] = "Reason is too long.";
        if (algorithmVersion is not null) errors[nameof(AlgorithmVersion)] = "Manual targets cannot have an algorithm version.";
        if (reason is not null) errors[nameof(Reason)] = "Manual targets cannot have an automated reason.";
    }

    internal static void ValidateMacroDistribution(
        NutritionTargetInputMode inputMode,
        NutritionMacroTargets macros,
        Dictionary<string, string> errors)
    {
        if (inputMode == NutritionTargetInputMode.Grams &&
            (macros.ProteinPercent is not null || macros.CarbohydratePercent is not null || macros.FatPercent is not null))
            errors["MacroDistribution"] = "Gram targets cannot contain percentage values.";
        if (inputMode == NutritionTargetInputMode.Percent)
            ValidatePercentDistribution(macros, errors);
    }

    private static void ValidatePercentDistribution(NutritionMacroTargets macros, Dictionary<string, string> errors)
    {
        if (macros.ProteinPercent is null || macros.CarbohydratePercent is null || macros.FatPercent is null)
        {
            errors["MacroDistribution"] = "Percentage targets require all three macro percentages.";
        }
        else
        {
            try
            {
                NutritionTotals derived = NutritionCalculator.CalculateMacroTargetsFromPercent(
                    macros.Kilocalories, macros.ProteinPercent.Value, macros.CarbohydratePercent.Value, macros.FatPercent.Value);
                if (derived.ProteinGrams != macros.ProteinGrams ||
                    derived.CarbohydrateGrams != macros.CarbohydrateGrams ||
                    derived.FatGrams != macros.FatGrams)
                    errors["MacroDistribution"] = "Derived gram targets do not match the percentage distribution.";
            }
            catch (NutritionValidationException exception)
            {
                foreach ((string field, string error) in exception.Errors) errors[field] = error;
            }
        }
    }

    internal static void ValidateTarget(decimal value, decimal max, string field, Dictionary<string, string> errors)
    {
        if (value is <= 0m || value > max) errors[field] = $"{field} must be positive and no greater than {max}.";
    }
}

/// <summary>Optional rest day target of a target version. Validated like the main (training day) target.</summary>
public sealed record NutritionRestDayTargetDraft(
    NutritionTargetInputMode InputMode,
    decimal Kilocalories,
    decimal ProteinGrams,
    decimal CarbohydrateGrams,
    decimal FatGrams,
    decimal? ProteinPercent,
    decimal? CarbohydratePercent,
    decimal? FatPercent,
    decimal MacroEnergyKilocalories,
    bool RequiresEnergyMismatchConfirmation)
{
    private const string Prefix = "RestDay.";

    public static NutritionRestDayTargetDraft Create(NutritionTargetInputMode inputMode, NutritionMacroTargets macros)
    {
        (decimal kilocalories, decimal proteinGrams, decimal carbohydrateGrams, decimal fatGrams) =
            (macros.Kilocalories, macros.ProteinGrams, macros.CarbohydrateGrams, macros.FatGrams);
        var errors = new Dictionary<string, string>(StringComparer.Ordinal);
        if (!Enum.IsDefined(inputMode)) errors[nameof(InputMode)] = "Input mode is invalid.";
        NutritionTargetVersionDraft.ValidateTarget(kilocalories, NutritionLimits.MaxDailyKilocalories, nameof(Kilocalories), errors);
        NutritionTargetVersionDraft.ValidateTarget(proteinGrams, NutritionLimits.MaxDailyMacroGrams, nameof(ProteinGrams), errors);
        NutritionTargetVersionDraft.ValidateTarget(carbohydrateGrams, NutritionLimits.MaxDailyMacroGrams, nameof(CarbohydrateGrams), errors);
        NutritionTargetVersionDraft.ValidateTarget(fatGrams, NutritionLimits.MaxDailyMacroGrams, nameof(FatGrams), errors);
        NutritionTargetVersionDraft.ValidateMacroDistribution(
            inputMode,
            macros,
            errors);
        if (errors.Count > 0)
            throw new NutritionValidationException(errors.ToDictionary(item => Prefix + item.Key, item => item.Value, StringComparer.Ordinal));
        return new NutritionRestDayTargetDraft(
            inputMode, kilocalories, proteinGrams, carbohydrateGrams, fatGrams,
            macros.ProteinPercent, macros.CarbohydratePercent, macros.FatPercent,
            NutritionCalculator.CalculateMacroEnergy(proteinGrams, carbohydrateGrams, fatGrams),
            NutritionCalculator.HasMacroEnergyMismatch(kilocalories, proteinGrams, carbohydrateGrams, fatGrams));
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
        ArgumentOutOfRangeException.ThrowIfNegative(baseVersion);
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
