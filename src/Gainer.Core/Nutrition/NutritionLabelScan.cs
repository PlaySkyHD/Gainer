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
        NutritionLabelFieldDraft kcal = ChooseEnergy(kilocalories, kilojoules, factor, converted, protein, carbohydrate, fat);
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

    /// <summary>
    /// Takes kcal when it passes the macro check. If kcal is missing or rejected and the label also prints kJ,
    /// the converted kJ value is used when it passes; otherwise the kcal result stays.
    /// </summary>
    private static NutritionLabelFieldDraft ChooseEnergy(
        NutritionLabelReading kilocalories,
        NutritionLabelReading kilojoules,
        decimal? factor,
        bool converted,
        NutritionLabelFieldDraft protein,
        NutritionLabelFieldDraft carbohydrate,
        NutritionLabelFieldDraft fat)
    {
        // Too much energy can only be judged when all three macros were read, and not when kcal and kJ agree.
        bool allMacrosRead = protein.Per100Grams is not null && carbohydrate.Per100Grams is not null && fat.Per100Grams is not null;
        bool checkUpper = allMacrosRead && !AreConsistent(kilocalories.Value, kilojoules.Value);
        NutritionLabelFieldDraft fromKcal = CheckAgainstMacroEnergy(
            Field(kilocalories, factor, converted, 0, MaxPlausibleKilocaloriesPer100Grams), protein, carbohydrate, fat, checkUpper);
        if (fromKcal.Per100Grams is not null || kilojoules.Value is not { } kj) return fromKcal;
        var energy = new NutritionLabelReading(kj / KilojoulesPerKilocalorie, kilojoules.Evidence);
        // The unit kJ is printed on the label, so a converted kJ value gets no upper check (liqueurs, kJ-only labels).
        NutritionLabelFieldDraft fromKj = CheckAgainstMacroEnergy(
            Field(energy, factor, true, 0, MaxPlausibleKilocaloriesPer100Grams), protein, carbohydrate, fat, false);
        // A kcal value that was read but rejected keeps its evidence if the kJ value is no better.
        bool kcalWasRead = kilocalories.Value is not null;
        return fromKj.Per100Grams is null && kcalWasRead ? fromKcal : fromKj;
    }

    /// <summary>True when both energies were read and kcal × 4.184 matches kJ within 5 %, so the label confirms itself.</summary>
    private static bool AreConsistent(decimal? kilocalories, decimal? kilojoules)
    {
        const decimal tolerance = 0.05m;
        return kilocalories is { } kcal && kilojoules is { } kj
            && Math.Abs(kcal * KilojoulesPerKilocalorie - kj) <= kj * tolerance;
    }

    private static NutritionLabelFieldDraft CheckAgainstMacroEnergy(
        NutritionLabelFieldDraft kcal,
        NutritionLabelFieldDraft protein,
        NutritionLabelFieldDraft carbohydrate,
        NutritionLabelFieldDraft fat,
        bool checkUpper)
    {
        // Below this macro energy (water, diet drinks) rounding makes the comparison meaningless; juice (about 45 kcal) is still checked.
        const decimal minMacroEnergy = 20m;
        // Fiber, polyols and rounding let labels undercut 4/4/9 a lot, so only energy below a quarter of it is a misread.
        const decimal minShareOfMacroEnergy = 0.25m;
        // Alcohol (7 kcal/g) is not in 4/4/9: sweet wine and liqueurs reach about 2.8 times the macro energy.
        // A kJ number read as kcal is about 4.2 times, so 3.5 separates them. Alcohol in a label with few macros
        // can exceed it, hence the higher minimum macro energy for this side.
        const decimal maxShareOfMacroEnergy = 3.5m;
        const decimal minMacroEnergyForUpperCheck = 50m;
        if (kcal.Per100Grams is not { } energyPer100) return kcal;
        // Unreadable macros count as 0: that only lowers the macro energy, which is safe for the lower check
        // but would wrongly reject the energy in the upper check, so that one runs only with all macros read.
        decimal macroEnergy = NutritionCalculator.CalculateMacroEnergy(
            protein.Per100Grams ?? 0m, carbohydrate.Per100Grams ?? 0m, fat.Per100Grams ?? 0m);
        bool farBelowMacroEnergy = macroEnergy >= minMacroEnergy
            && energyPer100 < macroEnergy * minShareOfMacroEnergy;
        bool farAboveMacroEnergy = checkUpper && macroEnergy >= minMacroEnergyForUpperCheck
            && energyPer100 > macroEnergy * maxShareOfMacroEnergy;
        return farBelowMacroEnergy || farAboveMacroEnergy
            ? kcal with { Per100Grams = null, Status = NutritionLabelFieldStatus.Implausible }
            : kcal;
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
