namespace Gainer.Core.Nutrition;

public enum NutritionLabelBasis
{
    Per100Grams = 1,
    Per100Milliliters = 2,
    PerServing = 3,
}

public enum NutritionLabelFieldStatus
{
    Confirmed = 1,
    Converted = 2,
    Missing = 3,
    Implausible = 4,
}

/// <summary>A value as printed on the label, with the label text it was read from.</summary>
public sealed record NutritionLabelReading(decimal? Value, string? Evidence)
{
    public static readonly NutritionLabelReading Empty = new(null, null);
}

/// <summary>Everything read from one basis column of a label, before conversion.</summary>
public sealed record NutritionLabelReadings(
    NutritionLabelBasis Basis,
    decimal? ServingMassGrams,
    NutritionLabelReading Kilocalories,
    NutritionLabelReading Kilojoules,
    NutritionLabelReading ProteinGrams,
    NutritionLabelReading CarbohydrateGrams,
    NutritionLabelReading FatGrams,
    NutritionLabelReading? SaltGrams = null,
    NutritionLabelReading? SodiumGrams = null,
    NutritionLabelReading? FiberGrams = null);

public sealed record NutritionLabelFieldDraft(
    decimal? OriginalValue,
    decimal? Per100Grams,
    NutritionLabelFieldStatus Status,
    string? Evidence);

public sealed record NutritionLabelScanDraft(
    NutritionLabelBasis Basis,
    decimal? ServingMassGrams,
    NutritionLabelFieldDraft Kilocalories,
    NutritionLabelFieldDraft ProteinGrams,
    NutritionLabelFieldDraft CarbohydrateGrams,
    NutritionLabelFieldDraft FatGrams,
    NutritionLabelFieldDraft SaltGrams,
    NutritionLabelFieldDraft FiberGrams,
    bool CanConfirm,
    string Provider,
    string ProviderModelVersion,
    string ParserVersion,
    DateTime ScannedAtUtc)
{
    public const int MaxEvidenceLength = 120;
    public const decimal KilojoulesPerKilocalorie = 4.184m;
    public const decimal SaltPerSodium = 2.5m;
    // Pure fat is about 900 kcal per 100 g; anything clearly above that is a misread.
    public const decimal MaxPlausibleKilocaloriesPer100Grams = 950m;
    public const decimal MaxPlausibleMacroGramsPer100Grams = 100m;
    // Rounding on printed labels lets the macro sum exceed 100 g slightly.
    public const decimal MaxPlausibleMacroSumPer100Grams = 105m;

    /// <summary>
    /// Converts label readings to values per 100 g. Liquids printed per 100 ml are taken as 1 g per ml,
    /// serving values need the serving mass, and energy printed only in kJ is converted to kcal.
    /// </summary>
    public static NutritionLabelScanDraft Create(
        NutritionLabelReadings readings,
        string provider,
        string providerModelVersion,
        string parserVersion,
        DateTime scannedAtUtc)
    {
        ArgumentNullException.ThrowIfNull(readings);
        (NutritionLabelBasis basis, decimal? servingMassGrams, NutritionLabelReading kilocalories,
            NutritionLabelReading kilojoules, NutritionLabelReading proteinGrams,
            NutritionLabelReading carbohydrateGrams, NutritionLabelReading fatGrams,
            NutritionLabelReading? saltGrams, NutritionLabelReading? sodiumGrams,
            NutritionLabelReading? fiberGrams) = readings;
        ArgumentNullException.ThrowIfNull(kilocalories);
        ArgumentNullException.ThrowIfNull(kilojoules);
        ArgumentNullException.ThrowIfNull(proteinGrams);
        ArgumentNullException.ThrowIfNull(carbohydrateGrams);
        ArgumentNullException.ThrowIfNull(fatGrams);
        var errors = new Dictionary<string, string>(StringComparer.Ordinal);
        if (!Enum.IsDefined(basis)) errors[nameof(Basis)] = "Basis is invalid.";
        string normalizedProvider = Normalize(provider, nameof(Provider), errors);
        string normalizedModel = Normalize(providerModelVersion, nameof(ProviderModelVersion), errors);
        string normalizedParser = Normalize(parserVersion, nameof(ParserVersion), errors);
        if (scannedAtUtc.Kind != DateTimeKind.Utc) errors[nameof(ScannedAtUtc)] = "ScannedAtUtc must be UTC.";
        if (errors.Count > 0) throw new NutritionValidationException(errors);

        decimal? servingMass = servingMassGrams is >= NutritionLimits.MinAmountGrams and <= NutritionLimits.MaxAmountGrams
            ? servingMassGrams
            : null;
        decimal? factor = basis switch
        {
            NutritionLabelBasis.PerServing => servingMass is { } mass ? 100m / mass : null,
            _ => 1m,
        };
        bool converted = basis != NutritionLabelBasis.Per100Grams;

        NutritionLabelReading energy = kilocalories;
        if (kilocalories.Value is null && kilojoules.Value is { } kj)
        {
            energy = new NutritionLabelReading(kj / KilojoulesPerKilocalorie, kilojoules.Evidence);
            converted = true;
        }

        NutritionLabelFieldDraft kcal = Field(energy, factor, converted, 0, MaxPlausibleKilocaloriesPer100Grams);
        if (kcal.Per100Grams == 0m) kcal = kcal with { Per100Grams = null, Status = NutritionLabelFieldStatus.Implausible };
        converted = basis != NutritionLabelBasis.Per100Grams;
        NutritionLabelFieldDraft protein = Field(proteinGrams, factor, converted, 1, MaxPlausibleMacroGramsPer100Grams);
        NutritionLabelFieldDraft carbohydrate = Field(carbohydrateGrams, factor, converted, 1, MaxPlausibleMacroGramsPer100Grams);
        NutritionLabelFieldDraft fat = Field(fatGrams, factor, converted, 1, MaxPlausibleMacroGramsPer100Grams);
        // Salt is optional for confirmation; labels listing only sodium are converted.
        NutritionLabelReading salt = saltGrams ?? NutritionLabelReading.Empty;
        bool saltConverted = converted;
        if (salt.Value is null && sodiumGrams?.Value is { } sodium)
        {
            salt = new NutritionLabelReading(sodium * SaltPerSodium, sodiumGrams.Evidence);
            saltConverted = true;
        }
        NutritionLabelFieldDraft saltField = Field(salt, factor, saltConverted, 2, NutritionLimits.MaxSaltGramsPer100Grams);
        // Fiber is optional for confirmation and scaled like the macros.
        NutritionLabelFieldDraft fiberField = Field(
            fiberGrams ?? NutritionLabelReading.Empty, factor, converted, 1, MaxPlausibleMacroGramsPer100Grams);
        decimal macroSum = (protein.Per100Grams ?? 0m) + (carbohydrate.Per100Grams ?? 0m) + (fat.Per100Grams ?? 0m);
        bool canConfirm = kcal.Per100Grams is not null && macroSum <= MaxPlausibleMacroSumPer100Grams;

        return new NutritionLabelScanDraft(
            basis,
            servingMass,
            kcal,
            protein,
            carbohydrate,
            fat,
            saltField,
            fiberField,
            canConfirm,
            normalizedProvider,
            normalizedModel,
            normalizedParser,
            scannedAtUtc);
    }

    private static NutritionLabelFieldDraft Field(
        NutritionLabelReading reading,
        decimal? factor,
        bool converted,
        int decimals,
        decimal maximumPer100Grams)
    {
        string? evidence = string.IsNullOrWhiteSpace(reading.Evidence) ? null : reading.Evidence.Trim();
        if (evidence?.Length > MaxEvidenceLength) evidence = evidence[..MaxEvidenceLength];
        if (reading.Value is not { } original)
            return new NutritionLabelFieldDraft(null, null, NutritionLabelFieldStatus.Missing, evidence);
        original = Math.Round(original, 2, MidpointRounding.AwayFromZero);
        if (original < 0m)
            return new NutritionLabelFieldDraft(original, null, NutritionLabelFieldStatus.Implausible, evidence);
        if (factor is not { } scale)
            return new NutritionLabelFieldDraft(original, null, NutritionLabelFieldStatus.Missing, evidence);
        decimal per100 = Math.Round(original * scale, decimals, MidpointRounding.AwayFromZero);
        if (per100 > maximumPer100Grams)
            return new NutritionLabelFieldDraft(original, null, NutritionLabelFieldStatus.Implausible, evidence);
        return new NutritionLabelFieldDraft(
            original,
            per100,
            converted ? NutritionLabelFieldStatus.Converted : NutritionLabelFieldStatus.Confirmed,
            evidence);
    }

    private static string Normalize(string value, string field, Dictionary<string, string> errors)
    {
        string normalized = value?.Trim() ?? string.Empty;
        if (normalized.Length is 0 or > 80) errors[field] = $"{field} is invalid.";
        return normalized;
    }
}

public interface INutritionLabelScanner
{
    Task<NutritionLabelScanDraft> ScanAsync(MealImageInput image, CancellationToken cancellationToken = default);
}
