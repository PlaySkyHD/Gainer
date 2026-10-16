using System.Reflection;
using System.Text.Json;

namespace Gainer.Infrastructure.Catalog;

internal static class ExerciseCatalogSnapshot
{
    private const string ResourceSuffix = "Catalog.exercise-catalog.v1.json";
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
        if (document is null || document.SchemaVersion != 1 || document.Entries.Count == 0)
        {
            throw new InvalidOperationException("The embedded exercise catalog is invalid.");
        }

        if (document.Entries.Select(item => item.Id).Distinct().Count() != document.Entries.Count)
        {
            throw new InvalidOperationException("Exercise catalog IDs must be unique.");
        }

        return document;
    }
}

internal sealed record ExerciseCatalogDocument(
    int SchemaVersion,
    string CatalogVersion,
    string Source,
    IReadOnlyList<ExerciseCatalogEntry> Entries);

internal sealed record ExerciseCatalogEntry(
    Guid Id,
    string Name,
    string TargetMuscle,
    string MuscleGroup,
    string Equipment);
