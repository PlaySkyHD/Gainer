using System.Text;
using Gainer.Core.Security;

namespace Gainer.Core.Coach;

/// <summary>Kinds of durable notes a user can keep for the coach.</summary>
public enum CoachMemoryCategory
{
    Goal,
    Preference,
    Intolerance,
    Injury,
    Other,
}

/// <summary>A note the user confirmed or wrote; the coach reads it as data, never as instructions.</summary>
public sealed class CoachMemory : UserOwnedEntity
{
    public Guid Id { get; init; }
    public CoachMemoryCategory Category { get; set; }
    public string Text { get; set; } = string.Empty;
    public DateTime CreatedAtUtc { get; init; }
    public DateTime UpdatedAtUtc { get; set; }
    public long Version { get; set; }
}

/// <summary>Read model of one coach memory entry.</summary>
public sealed record CoachMemoryItem(
    Guid Id,
    CoachMemoryCategory Category,
    string Text,
    DateTime CreatedAtUtc,
    DateTime UpdatedAtUtc,
    long Version);

/// <summary>Result of creating an entry; <see cref="Created" /> is false when the same text already existed.</summary>
public sealed record CoachMemoryCreateResult(CoachMemoryItem Item, bool Created);

/// <summary>Read-only access to the current user's memory, as used by the coach.</summary>
public interface ICoachMemoryQueries
{
    /// <summary>Returns the current user's entries, newest first.</summary>
    Task<IReadOnlyList<CoachMemoryItem>> ListAsync(CancellationToken cancellationToken = default);
}

/// <summary>User-driven management of the current user's coach memory.</summary>
public interface ICoachMemoryStore : ICoachMemoryQueries
{
    Task<CoachMemoryCreateResult> CreateAsync(
        CoachMemoryCategory category, string text, CancellationToken cancellationToken = default);

    Task<CoachMemoryItem> UpdateAsync(
        Guid id, CoachMemoryCategory category, string text, CancellationToken cancellationToken = default);

    /// <summary>Returns false when no own entry with this id exists.</summary>
    Task<bool> DeleteAsync(Guid id, CancellationToken cancellationToken = default);

    /// <summary>Deletes every entry of the current user and returns how many there were.</summary>
    Task<int> DeleteAllAsync(CancellationToken cancellationToken = default);
}

/// <summary>Business failure with a stable code for the HTTP contract.</summary>
public sealed class CoachMemoryException(string code, string message) : Exception(message)
{
    public const string Invalid = "memory_invalid";
    public const string NotFound = "memory_not_found";
    public const string LimitReached = "memory_limit_reached";
    public const string Duplicate = "memory_duplicate";

    public string Code { get; } = code;
}

/// <summary>Limits, wire names and text normalization for coach memory.</summary>
public static class CoachMemoryRules
{
    public const int MaxEntriesPerUser = 50;
    public const int MaxTextLength = 200;
    public const int MaxSuggestions = 3;

    /// <summary>Upper bound for the memory text sent to the model per request.</summary>
    public const int MaxPromptCharacters = 4_000;

    public static IReadOnlyList<string> WireNames { get; } = ["goal", "preference", "intolerance", "injury", "other"];

    public static string ToWire(CoachMemoryCategory category) => category switch
    {
        CoachMemoryCategory.Goal => "goal",
        CoachMemoryCategory.Preference => "preference",
        CoachMemoryCategory.Intolerance => "intolerance",
        CoachMemoryCategory.Injury => "injury",
        CoachMemoryCategory.Other => "other",
        _ => throw new ArgumentOutOfRangeException(nameof(category), category, "Unknown memory category."),
    };

    public static bool TryParse(string? value, out CoachMemoryCategory category)
    {
        CoachMemoryCategory? parsed = value switch
        {
            "goal" => CoachMemoryCategory.Goal,
            "preference" => CoachMemoryCategory.Preference,
            "intolerance" => CoachMemoryCategory.Intolerance,
            "injury" => CoachMemoryCategory.Injury,
            "other" => CoachMemoryCategory.Other,
            _ => null,
        };
        category = parsed.GetValueOrDefault();
        return parsed.HasValue;
    }

    /// <summary>Turns control characters and line breaks into spaces, collapses runs of spaces and trims.</summary>
    public static string Normalize(string? text)
    {
        if (string.IsNullOrEmpty(text)) return string.Empty;
        var builder = new StringBuilder(text.Length);
        bool pendingSpace = false;
        foreach (char character in text)
        {
            if (char.IsWhiteSpace(character) || char.IsControl(character))
            {
                pendingSpace = builder.Length > 0;
                continue;
            }
            if (pendingSpace) builder.Append(' ');
            pendingSpace = false;
            builder.Append(character);
        }
        return builder.ToString();
    }

    /// <summary>Key under which two texts count as the same entry.</summary>
    public static string DuplicateKey(string text) => Normalize(text).ToUpperInvariant();

    /// <summary>Returns the normalized text or throws <see cref="CoachMemoryException" /> when it is empty or too long.</summary>
    public static string RequireValidText(string? text)
    {
        string normalized = Normalize(text);
        return normalized.Length is >= 1 and <= MaxTextLength
            ? normalized
            : throw new CoachMemoryException(CoachMemoryException.Invalid, "The memory text must contain 1 to 200 characters.");
    }
}
