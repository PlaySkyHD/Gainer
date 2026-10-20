namespace Gainer.Contracts.Training;

public sealed record MuscleSuggestionTurnRequest(string Question, string Answer);

public sealed record MuscleSuggestionRequest(
    string Name,
    string ExerciseType,
    string? Notes,
    IReadOnlyList<MuscleSuggestionTurnRequest>? Turns);

/// <summary><c>kind</c> is <c>question</c> (with options) or <c>suggestion</c> (with muscles).</summary>
public sealed record MuscleSuggestionResponse(
    string Kind,
    string? Question,
    IReadOnlyList<string> Options,
    IReadOnlyList<string> PrimaryMuscles,
    IReadOnlyList<string> SecondaryMuscles,
    string? Explanation);
