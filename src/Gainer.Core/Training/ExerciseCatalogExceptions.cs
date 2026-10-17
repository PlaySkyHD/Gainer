namespace Gainer.Core.Training;

public sealed class BaseExerciseImmutableException()
    : InvalidOperationException("Base catalog exercises are immutable.");

public sealed class UnknownExerciseTypeException(string? value)
    : ArgumentException($"Unknown exercise type '{value}'.", nameof(value));
