import '../../../domain/models/training/muscle_ai.dart';
import '../../../domain/models/training/muscles.dart';
import '../../../domain/models/training/workout_model.dart';
import '../../services/api/api_client.dart';

/// Fragt die KI nach den Muskeln einer Übung. Braucht eine Verbindung.
abstract interface class MuscleSuggestionService {
  Future<MuscleAiReply> suggest({
    required String name,
    required ExerciseKind kind,
    String? notes,
    List<MuscleAiTurn> turns = const [],
  });
}

class ApiMuscleSuggestionService implements MuscleSuggestionService {
  ApiMuscleSuggestionService(this.api);

  final ApiClient api;

  @override
  Future<MuscleAiReply> suggest({
    required String name,
    required ExerciseKind kind,
    String? notes,
    List<MuscleAiTurn> turns = const [],
  }) async {
    final json = await api.suggestMuscles(
      name: name,
      exerciseType: kind.wireValue,
      notes: notes,
      turns: [for (final turn in turns) turn.toJson()],
    );
    if (json['kind'] == 'question') {
      return MuscleAiQuestion(
        question: json['question'] as String? ?? '',
        options: [
          for (final option in json['options'] as List? ?? const [])
            option as String,
        ],
      );
    }
    final primary = Muscle.listFromJson(json['primaryMuscles']);
    if (primary.isEmpty) {
      throw const FormatException('Der Vorschlag enthält keine Muskeln.');
    }
    return MuscleAiSuggestion(
      primary: primary,
      secondary: Muscle.listFromJson(json['secondaryMuscles']),
      explanation: json['explanation'] as String? ?? '',
    );
  }
}
