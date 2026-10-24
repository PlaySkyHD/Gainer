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

/// <summary>Creates or replaces a coach memory entry.</summary>
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

    [Required, StringLength(200, MinimumLength = 1)]
    public string Text { get; init; }
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
