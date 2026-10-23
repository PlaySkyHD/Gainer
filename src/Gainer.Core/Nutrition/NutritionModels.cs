using Gainer.Core.Security;

namespace Gainer.Core.Nutrition;

public enum MealType
{
    Breakfast = 1,
    Lunch = 2,
    Dinner = 3,
    Snacks = 4,
}

/// <summary>Whether a day counts as a training or a rest day for its nutrition target.</summary>
public enum NutritionDayKind
{
    Training = 1,
    Rest = 2,
}

public sealed class NutritionDay : UserOwnedEntity
{
    public Guid Id { get; init; }
    public DateOnly LocalDate { get; init; }

    /// <summary>Kind chosen by the user for this day; null means it is derived from training and schedule.</summary>
    public NutritionDayKind? DayKind { get; set; }
    public DateTime CreatedAtUtc { get; init; }
    public DateTime UpdatedAtUtc { get; set; }
    public long Version { get; set; }
    public ICollection<NutritionEntry> Entries { get; } = new List<NutritionEntry>();
}

/// <summary>Values of a logged food, shared by diary entries and day template entries.</summary>
public abstract class NutritionEntryValues : UserOwnedEntity
{
    public Guid Id { get; init; }
    public MealType Meal { get; set; }
    public int Position { get; set; }
    public string ProductName { get; set; } = string.Empty;
    public string? Brand { get; set; }
    public decimal AmountGrams { get; set; }
    public decimal? PieceGrams { get; set; }
    public decimal? PieceCount { get; set; }
    public decimal Kilocalories { get; set; }
    public decimal? ProteinGrams { get; set; }
    public decimal? CarbohydrateGrams { get; set; }
    public decimal? FatGrams { get; set; }
    public decimal? SaltGrams { get; set; }
    public decimal? FiberGrams { get; set; }
    public string? Provider { get; set; }
    public string? Barcode { get; set; }
    public DateTime? RetrievedAtUtc { get; set; }
    public decimal BasisGrams { get; set; }
    public decimal KilocaloriesPerBasis { get; set; }
    public decimal? ProteinGramsPerBasis { get; set; }
    public decimal? CarbohydrateGramsPerBasis { get; set; }
    public decimal? FatGramsPerBasis { get; set; }
    public decimal? SaltGramsPerBasis { get; set; }
    public decimal? FiberGramsPerBasis { get; set; }

    /// <summary>Copies every value except the identifier and the owner.</summary>
    public void CopyValuesFrom(NutritionEntryValues source)
    {
        ArgumentNullException.ThrowIfNull(source);
        Meal = source.Meal;
        Position = source.Position;
        ProductName = source.ProductName;
        Brand = source.Brand;
        AmountGrams = source.AmountGrams;
        PieceGrams = source.PieceGrams;
        PieceCount = source.PieceCount;
        Kilocalories = source.Kilocalories;
        ProteinGrams = source.ProteinGrams;
        CarbohydrateGrams = source.CarbohydrateGrams;
        FatGrams = source.FatGrams;
        SaltGrams = source.SaltGrams;
        FiberGrams = source.FiberGrams;
        Provider = source.Provider;
        Barcode = source.Barcode;
        RetrievedAtUtc = source.RetrievedAtUtc;
        BasisGrams = source.BasisGrams;
        KilocaloriesPerBasis = source.KilocaloriesPerBasis;
        ProteinGramsPerBasis = source.ProteinGramsPerBasis;
        CarbohydrateGramsPerBasis = source.CarbohydrateGramsPerBasis;
        FatGramsPerBasis = source.FatGramsPerBasis;
        SaltGramsPerBasis = source.SaltGramsPerBasis;
        FiberGramsPerBasis = source.FiberGramsPerBasis;
    }
}

public sealed class NutritionEntry : NutritionEntryValues
{
    public Guid NutritionDayId { get; init; }
    public NutritionDay NutritionDay { get; init; } = null!;
    public string AmountUnit { get; set; } = "g";
}
