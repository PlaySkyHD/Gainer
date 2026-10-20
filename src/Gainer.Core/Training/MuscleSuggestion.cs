namespace Gainer.Core.Training;

/// <summary>An earlier follow-up question of the assistant and the user's answer.</summary>
public sealed record MuscleSuggestionTurn(string Question, string Answer);

/// <summary>What the assistant knows about the exercise; the conversation holds earlier turns.</summary>
public sealed record MuscleSuggestionInput
{
    public const int MaximumNameLength = 160;
    public const int MaximumNotesLength = 500;
    public const int MaximumTextLength = 300;
    public const int MaximumTurns = 2;

    private MuscleSuggestionInput(string name, string exerciseType, string? notes, IReadOnlyList<MuscleSuggestionTurn> turns)
    {
        Name = name;
        ExerciseType = exerciseType;
        Notes = notes;
        Turns = turns;
    }

    public string Name { get; }
    public string ExerciseType { get; }
    public string? Notes { get; }
    public IReadOnlyList<MuscleSuggestionTurn> Turns { get; }

    /// <summary>True once the follow-up budget is used; the next reply must be a suggestion.</summary>
    public bool MustSuggest => Turns.Count >= MaximumTurns;

    public static MuscleSuggestionInput Create(
        string? name,
        string? exerciseType,
        string? notes,
        IReadOnlyList<MuscleSuggestionTurn>? turns)
    {
        string trimmedName = name?.Trim() ?? string.Empty;
        if (trimmedName.Length is < 1 or > MaximumNameLength)
            throw new MuscleSuggestionException("invalid_name", "The exercise name must contain between 1 and 160 characters.");
        if (!ExerciseTypes.TryParse(exerciseType, out ExerciseType type))
            throw new MuscleSuggestionException("invalid_exercise_type", "The exercise type is unknown.");
        string? trimmedNotes = string.IsNullOrWhiteSpace(notes) ? null : notes.Trim();
        if (trimmedNotes?.Length > MaximumNotesLength)
            throw new MuscleSuggestionException("invalid_notes", "The notes are too long.");
        MuscleSuggestionTurn[] conversation = turns?.ToArray() ?? [];
        if (conversation.Length > MaximumTurns)
            throw new MuscleSuggestionException("too_many_turns", "At most two follow-up questions are allowed.");
        foreach (MuscleSuggestionTurn turn in conversation)
        {
            if (string.IsNullOrWhiteSpace(turn.Question) || string.IsNullOrWhiteSpace(turn.Answer) ||
                turn.Question.Length > MaximumTextLength || turn.Answer.Length > MaximumTextLength)
                throw new MuscleSuggestionException("invalid_turn", "Every turn needs a question and an answer of at most 300 characters.");
        }
        return new MuscleSuggestionInput(
            trimmedName,
            ExerciseTypes.ToStorageValue(type),
            trimmedNotes,
            conversation.Select(turn => new MuscleSuggestionTurn(turn.Question.Trim(), turn.Answer.Trim())).ToArray());
    }
}

/// <summary>Either a follow-up question with answer options or a muscle suggestion.</summary>
public sealed record MuscleSuggestionResult(
    string? Question,
    IReadOnlyList<string> Options,
    IReadOnlyList<string> PrimaryMuscles,
    IReadOnlyList<string> SecondaryMuscles,
    string? Explanation)
{
    public const int MaximumOptions = 4;

    public bool IsQuestion => Question is not null;

    public static MuscleSuggestionResult Ask(string question, IReadOnlyList<string> options) =>
        new(question, options, [], [], null);

    public static MuscleSuggestionResult Suggest(
        IReadOnlyList<string> primary,
        IReadOnlyList<string> secondary,
        string explanation) =>
        new(null, [], primary, secondary, explanation);
}

public interface IMuscleSuggester
{
    Task<MuscleSuggestionResult> SuggestAsync(MuscleSuggestionInput input, CancellationToken cancellationToken = default);
}

public sealed class MuscleSuggestionException(
    string code,
    string message,
    int statusCode = 400,
    Exception? innerException = null) : Exception(message, innerException)
{
    public string Code { get; } = code;
    public int StatusCode { get; } = statusCode;
}
