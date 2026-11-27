namespace Gainer.Core.Nutrition;

/// <summary>
/// Kcal and macros that apply on a day. <paramref name="DayKind"/> is null when the version has no rest-day target and
/// the day kind therefore does not matter; <paramref name="DayKindChosen"/> tells whether the user set it.
/// </summary>
public sealed record DayTargetValues(
    NutritionDayKind? DayKind,
    bool DayKindChosen,
    decimal Kilocalories,
    decimal ProteinGrams,
    decimal CarbohydrateGrams,
    decimal FatGrams);

/// <summary>
/// Port of the app's <c>dayTarget</c> (day_target.dart): the rest-day target applies when the version has one and the
/// day counts as rest day, i.e. the day kind the user chose or, without a choice, the automatic one from the training
/// schedule projection. Otherwise the version's own target applies.
/// </summary>
public static class DayTarget
{
    /// <summary>
    /// Day kind that selects the target; null without a rest-day target. <paramref name="automaticKind"/> is only
    /// called when the version has a rest-day target and the user chose no kind.
    /// </summary>
    public static NutritionDayKind? KindOn(bool hasRestDayTarget, NutritionDayKind? chosenKind, Func<NutritionDayKind> automaticKind)
    {
        ArgumentNullException.ThrowIfNull(automaticKind);
        return hasRestDayTarget ? chosenKind ?? automaticKind() : null;
    }

    /// <summary>The target of <paramref name="version"/> on a day with the given chosen and automatic day kind.</summary>
    public static DayTargetValues On(
        NutritionTargetVersionDraft version,
        NutritionDayKind? chosenKind,
        Func<NutritionDayKind> automaticKind)
    {
        ArgumentNullException.ThrowIfNull(version);
        NutritionDayKind? kind = KindOn(version.RestDay is not null, chosenKind, automaticKind);
        bool chosen = kind is not null && chosenKind is not null;
        return kind == NutritionDayKind.Rest && version.RestDay is { } rest
            ? new DayTargetValues(kind, chosen, rest.Kilocalories, rest.ProteinGrams, rest.CarbohydrateGrams, rest.FatGrams)
            : new DayTargetValues(kind, chosen, version.Kilocalories, version.ProteinGrams, version.CarbohydrateGrams, version.FatGrams);
    }
}
