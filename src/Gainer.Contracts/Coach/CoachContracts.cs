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

public sealed record CoachResponse(
    string Summary,
    IReadOnlyList<CoachObservationResponse> Observations,
    IReadOnlyList<CoachFactResponse> Facts,
    IReadOnlyList<string> DataGaps,
    IReadOnlyList<string> Suggestions,
    long AsOfRevision);
