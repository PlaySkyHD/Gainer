import 'muscles.dart';

/// Eine Rückfrage der KI und die Antwort des Nutzers.
class MuscleAiTurn {
  const MuscleAiTurn({required this.question, required this.answer});

  final String question;
  final String answer;

  Map<String, Object?> toJson() => {'question': question, 'answer': answer};
}

/// Antwort der KI: eine Rückfrage oder ein Vorschlag.
sealed class MuscleAiReply {
  const MuscleAiReply();
}

class MuscleAiQuestion extends MuscleAiReply {
  const MuscleAiQuestion({required this.question, required this.options});

  final String question;
  final List<String> options;
}

class MuscleAiSuggestion extends MuscleAiReply {
  const MuscleAiSuggestion({
    required this.primary,
    required this.secondary,
    required this.explanation,
  });

  final List<Muscle> primary;
  final List<Muscle> secondary;
  final String explanation;
}

/// Höchstzahl an Rückfragen, wie im Backend.
const maxMuscleAiTurns = 2;
