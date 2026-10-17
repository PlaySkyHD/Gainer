import 'package:flutter/foundation.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../../domain/models/training/workout_model.dart';
import 'active_workout_controller.dart';

/// Tagebuch und Start-/Löschaktionen des Trainings-Tabs.
class TrainingHomeViewModel extends ChangeNotifier {
  TrainingHomeViewModel({
    required this.repository,
    required this.activeWorkout,
  });

  final TrainingLogRepository repository;
  final ActiveWorkoutController activeWorkout;

  /// Nicht gelöschte Trainings, neueste zuerst.
  List<Workout> diary = const [];
  bool isLoading = false;
  String? errorMessage;
  bool _disposed = false;

  Future<void> loadDiary() async {
    if (_disposed) return;
    isLoading = true;
    errorMessage = null;
    _notify();
    try {
      final loaded = await repository.readDiary();
      if (_disposed) return;
      diary = loaded;
    } catch (_) {
      if (!_disposed) {
        errorMessage = 'Das Tagebuch konnte nicht geladen werden.';
      }
    } finally {
      if (!_disposed) {
        isLoading = false;
        _notify();
      }
    }
  }

  /// Startet ein leeres Training und liefert die ID des Trainings, das
  /// geöffnet werden soll. Existiert schon ein aktives Training, wird dessen
  /// ID geliefert. Bei Fehlern liefert die Methode null und setzt [errorMessage].
  Future<String?> startEmptyWorkout() async {
    try {
      final workout = await repository.startEmpty();
      await activeWorkout.load();
      await loadDiary();
      return workout.workoutId;
    } on ActiveWorkoutExistsException catch (error) {
      return error.workoutId;
    } catch (_) {
      errorMessage = 'Das Training konnte nicht gestartet werden. Es wurde nichts gespeichert.';
      _notify();
      return null;
    }
  }

  /// Entfernt das Training sofort aus der Liste und speichert die Löschung.
  /// Schlägt das Speichern fehl, wird das Tagebuch neu geladen.
  Future<void> deleteWorkout(String workoutId) async {
    diary = [
      for (final workout in diary)
        if (workout.workoutId != workoutId) workout,
    ];
    _notify();
    try {
      await repository.deleteWorkout(workoutId);
    } catch (_) {
      errorMessage = 'Das Training konnte nicht gelöscht werden.';
      await loadDiary();
      await activeWorkout.load();
      return;
    }
    await activeWorkout.endRestTimer(workoutId);
    await activeWorkout.load();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
