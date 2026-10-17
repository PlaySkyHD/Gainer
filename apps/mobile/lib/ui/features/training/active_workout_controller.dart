import 'package:flutter/foundation.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../../domain/models/training/workout_model.dart';

/// Hält das laufende Training des Kontos für Tagebuch, Trainingsleiste und
/// Trainingsscreen. Hängt am `AccountScope`, damit ein Kontowechsel einen
/// frischen Zustand ohne Daten des alten Kontos liefert.
class ActiveWorkoutController extends ChangeNotifier {
  ActiveWorkoutController(this._repository);

  final TrainingLogRepository _repository;
  Workout? _active;
  bool _disposed = false;

  /// Das aktive Training oder null, wenn keines läuft.
  Workout? get active => _active;

  bool get hasActiveWorkout => _active != null;

  /// Liest den Stand aus dem lokalen Speicher. Wird nach jeder Änderung
  /// eines Trainings und nach Synchronisation aufgerufen.
  /// Fehler des letzten Ladevorgangs; null, wenn er geklappt hat.
  Object? lastLoadError;

  /// Schlägt das Lesen fehl, bleibt der letzte bekannte Stand erhalten. Der
  /// Aufrufer (z. B. eine Speicher-Queue) bricht dadurch nicht ab.
  Future<void> load() async {
    try {
      final workout = await _repository.readActiveWorkout();
      lastLoadError = null;
      if (_disposed || _sameAs(workout)) return;
      _active = workout;
      notifyListeners();
    } catch (error, stackTrace) {
      lastLoadError = error;
      debugPrint(
        'Aktives Training konnte nicht geladen werden: $error\n$stackTrace',
      );
    }
  }

  bool _sameAs(Workout? workout) {
    final current = _active;
    if (current == null || workout == null) return current == workout;
    return current.workoutId == workout.workoutId &&
        current.title == workout.title &&
        current.startedAtUtc == workout.startedAtUtc;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
