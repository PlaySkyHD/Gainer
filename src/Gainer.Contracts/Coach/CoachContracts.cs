using System.ComponentModel.DataAnnotations;

namespace Gainer.Contracts.Coach;

public sealed record CoachResponseRequest
{
    public CoachResponseRequest(string question)
    {
        Question = question;
    }

    [Required, StringLength(1000, MinimumLength = 1)]
    public string Question { get; init; }
}

public sealed record CoachFactResponse(
    string FactId,
    string Kind,
    string Label,
    decimal? NumericValue,
    string? TextValue,
    string? Unit,
    string Period,
    string? AlgorithmVersion);

public sealed record CoachObservationResponse(string Text, IReadOnlyList<string> FactIds);

/// <summary>A note the coach proposes; the app stores it only after the user taps „Merken“.</summary>
public sealed record CoachMemorySuggestionResponse(string Category, string Text);

public sealed record CoachResponse(
    string Summary,
    IReadOnlyList<CoachObservationResponse> Observations,
    IReadOnlyList<CoachFactResponse> Facts,
    IReadOnlyList<string> DataGaps,
    IReadOnlyList<string> Suggestions,
    long AsOfRevision,
    IReadOnlyList<CoachMemorySuggestionResponse>? MemorySuggestions = null);

/// <summary>Creates a coach memory entry. The same text again sets the category of the existing entry.</summary>
public sealed record CoachMemoryRequest
{
    public CoachMemoryRequest(string category, string text)
    {
        Category = category;
        Text = text;
    }

    /// <summary>One of goal, preference, intolerance, injury, other.</summary>
    [Required, StringLength(16, MinimumLength = 1)]
    public string Category { get; init; }

    /// <summary>1 to 200 UTF-16 code units after trimming.</summary>
    [Required, StringLength(200, MinimumLength = 1)]
    public string Text { get; init; }
}

/// <summary>Replaces category and text of a coach memory entry.</summary>
public sealed record CoachMemoryUpdateRequest
{
    public CoachMemoryUpdateRequest(string category, string text, long? baseVersion = null)
    {
        Category = category;
        Text = text;
        BaseVersion = baseVersion;
    }

    /// <summary>One of goal, preference, intolerance, injury, other.</summary>
    [Required, StringLength(16, MinimumLength = 1)]
    public string Category { get; init; }

    /// <summary>1 to 200 UTF-16 code units after trimming.</summary>
    [Required, StringLength(200, MinimumLength = 1)]
    public string Text { get; init; }

    /// <summary>
    /// Version the client edited. A different stored version answers 409 <c>memory_conflict</c>.
    /// Optional for older app builds; without it the change is not checked.
    /// </summary>
    [Range(1, long.MaxValue)]
    public long? BaseVersion { get; init; }
}

public sealed record CoachMemoryResponse(
    Guid Id,
    string Category,
    string Text,
    DateTime CreatedAtUtc,
    DateTime UpdatedAtUtc,
    long Version);

/// <summary>All entries of the current user, newest first, with the per-user maximum.</summary>
public sealed record CoachMemoryListResponse(IReadOnlyList<CoachMemoryResponse> Items, int MaxEntries);
