using Gainer.Core.Security;

namespace Gainer.Core.Nutrition;

public enum MealType
{
    Breakfast = 1,
    Lunch = 2,
    Dinner = 3,
    Snacks = 4,
}

public sealed class NutritionDay : UserOwnedEntity
{
    public Guid Id { get; init; }
    public DateOnly LocalDate { get; init; }
    public DateTime CreatedAtUtc { get; init; }
    public DateTime UpdatedAtUtc { get; set; }
    public long Version { get; set; }
    public ICollection<NutritionEntry> Entries { get; } = new List<NutritionEntry>();
}

public sealed class NutritionEntry : UserOwnedEntity
{
    public Guid Id { get; init; }
    public Guid NutritionDayId { get; init; }
    public NutritionDay NutritionDay { get; init; } = null!;
    public MealType Meal { get; set; }
    public int Position { get; set; }
    public string ProductName { get; set; } = string.Empty;
    public string? Brand { get; set; }
    public decimal AmountGrams { get; set; }
    public string AmountUnit { get; set; } = "g";
    public decimal? PieceGrams { get; set; }
    public decimal? PieceCount { get; set; }
    public decimal Kilocalories { get; set; }
    public decimal? ProteinGrams { get; set; }
    public decimal? CarbohydrateGrams { get; set; }
    public decimal? FatGrams { get; set; }
    public decimal? SaltGrams { get; set; }
    public string? Provider { get; set; }
    public string? Barcode { get; set; }
    public DateTime? RetrievedAtUtc { get; set; }
    public decimal BasisGrams { get; set; }
    public decimal KilocaloriesPerBasis { get; set; }
    public decimal? ProteinGramsPerBasis { get; set; }
    public decimal? CarbohydrateGramsPerBasis { get; set; }
    public decimal? FatGramsPerBasis { get; set; }
    public decimal? SaltGramsPerBasis { get; set; }
}
