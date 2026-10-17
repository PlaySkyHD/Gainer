using System.Reflection;
using System.Text.Json;
using Gainer.Core.Training;

namespace Gainer.Infrastructure.Catalog;

internal static class ExerciseCatalogSnapshot
{
    private const string ResourceSuffix = "Catalog.exercise-catalog.v2.json";
    private static readonly JsonSerializerOptions DeserializeOptions = new() { PropertyNameCaseInsensitive = true };
    private static readonly Lazy<ExerciseCatalogDocument> DocumentHolder = new(Load);

    public static ExerciseCatalogDocument Document => DocumentHolder.Value;

    private static ExerciseCatalogDocument Load()
    {
        Assembly assembly = typeof(ExerciseCatalogSnapshot).Assembly;
        string resourceName = assembly.GetManifestResourceNames()
            .Single(name => name.EndsWith(ResourceSuffix, StringComparison.Ordinal));
        using Stream stream = assembly.GetManifestResourceStream(resourceName)
            ?? throw new InvalidOperationException("The embedded exercise catalog is unavailable.");
        ExerciseCatalogDocument? document = JsonSerializer.Deserialize<ExerciseCatalogDocument>(
            stream,
            DeserializeOptions);
        if (document is null || document.SchemaVersion != 2 || document.Entries.Count == 0 || document.Categories.Count == 0)
        {
            throw new InvalidOperationException("The embedded exercise catalog is invalid.");
        }

        if (document.Entries.Select(item => item.Id).Distinct().Count() != document.Entries.Count)
        {
            throw new InvalidOperationException("Exercise catalog IDs must be unique.");
        }

        if (document.Categories.Select(item => item.Id).Distinct().Count() != document.Categories.Count ||
            document.Categories.Select(item => item.Key).Distinct(StringComparer.Ordinal).Count() != document.Categories.Count)
        {
            throw new InvalidOperationException("Exercise catalog category IDs and keys must be unique.");
        }

        HashSet<string> categoryKeys = document.Categories.Select(item => item.Key).ToHashSet(StringComparer.Ordinal);
        foreach (ExerciseCatalogEntry entry in document.Entries)
        {
            ExerciseTypes.Parse(entry.ExerciseType);
            ExerciseFactors.EnsureValid(entry.BodyweightFactor, entry.WeightFactor);
            if (entry.CategoryKeys.Count == 0 || entry.CategoryKeys.Any(key => !categoryKeys.Contains(key)))
            {
                throw new InvalidOperationException("Every exercise catalog entry needs known category keys.");
            }
        }

        return document;
    }
}

internal sealed record ExerciseCatalogDocument(
    int SchemaVersion,
    string CatalogVersion,
    string Source,
    IReadOnlyList<ExerciseCatalogCategory> Categories,
    IReadOnlyList<ExerciseCatalogEntry> Entries)
{
    public Guid CategoryId(string key) =>
        Categories.Single(item => string.Equals(item.Key, key, StringComparison.Ordinal)).Id;
}

internal sealed record ExerciseCatalogCategory(
    Guid Id,
    string Key,
    string Name);

internal sealed record ExerciseCatalogEntry(
    Guid Id,
    string Name,
    string TargetMuscle,
    string MuscleGroup,
    string Equipment,
    string ExerciseType,
    IReadOnlyList<string> CategoryKeys,
    decimal? BodyweightFactor,
    decimal? WeightFactor);
