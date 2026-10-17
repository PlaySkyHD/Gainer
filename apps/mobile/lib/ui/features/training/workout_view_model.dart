import 'package:flutter/foundation.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../../domain/models/training/workout_model.dart';
import '../../../domain/models/training/workout_validation.dart';
import 'active_workout_controller.dart';

enum WorkoutFinishOutcome { finished, failed }

/// Zustand eines Trainings im Trainingsscreen. Jede Änderung wird sofort
/// lokal angezeigt und über [TrainingLogRepository.saveWorkout] gespeichert.
/// Schlägt das Speichern fehl, bleibt die Änderung in der Ansicht erhalten und
/// kann mit [retrySave] erneut gesendet werden.
class WorkoutViewModel extends ChangeNotifier {
  WorkoutViewModel({
    required this.repository,
    required this.activeWorkout,
    required this.workoutId,
  });

  final TrainingLogRepository repository;
  final ActiveWorkoutController activeWorkout;
  final String workoutId;

  Workout? _workout;
  bool isLoading = false;
  String? errorMessage;
  bool _hasUnsavedChanges = false;
  bool _disposed = false;

  /// Serialisiert Speichervorgänge, damit sich Schreibzugriffe nicht überholen.
  Future<void> _queue = Future.value();

  Workout? get workout => _workout;

  bool get isActive => _workout?.isActive ?? false;

  bool get hasUnsavedChanges => _hasUnsavedChanges;

  Future<void> load() async {
    if (_disposed) return;
    isLoading = true;
    _notify();
    try {
      final loaded = await repository.readWorkout(workoutId);
      if (_disposed) return;
      _workout = loaded;
      errorMessage = loaded == null
          ? 'Das Training ist nicht mehr verfügbar.'
          : null;
    } catch (_) {
      if (!_disposed) {
        errorMessage = 'Das Training konnte nicht geladen werden.';
      }
    } finally {
      if (!_disposed) {
        isLoading = false;
        _notify();
      }
    }
  }

  /// Wendet [change] auf das angezeigte Training an und speichert es.
  /// Das Future endet, wenn dieser Stand gespeichert oder der Fehler gemeldet ist.
  Future<void> edit(Workout Function(Workout current) change) {
    final current = _workout;
    if (current == null) return Future.value();
    _workout = change(current);
    _hasUnsavedChanges = true;
    _notify();
    return _enqueueSave();
  }

  /// Sendet eine nach einem Fehler verbliebene Änderung erneut.
  Future<void> retrySave() => _enqueueSave();

  /// Beendet das Training. Dies ist der Hook für den Fehlwerte-Dialog und die
  /// Zusammenfassung; vorerst wird ohne Rückfrage direkt beendet.
  Future<WorkoutFinishOutcome> requestFinish() async {
    await _enqueueSave();
    if (_hasUnsavedChanges) return WorkoutFinishOutcome.failed;
    try {
      await repository.finishWorkout(workoutId);
    } catch (_) {
      if (!_disposed) {
        errorMessage = 'Das Training konnte nicht beendet werden.';
        _notify();
      }
      return WorkoutFinishOutcome.failed;
    }
    await activeWorkout.load();
    await _reloadSilently();
    return WorkoutFinishOutcome.finished;
  }

  /// Löscht das Training nach Bestätigung durch die Ansicht.
  Future<bool> deleteWorkout() async {
    await _queue;
    try {
      await repository.deleteWorkout(workoutId);
    } catch (_) {
      if (!_disposed) {
        errorMessage = 'Das Training konnte nicht gelöscht werden.';
        _notify();
      }
      return false;
    }
    await activeWorkout.load();
    return true;
  }

  Future<void> _enqueueSave() {
    _queue = _queue.then((_) => _saveIfChanged());
    return _queue;
  }

  Future<void> _saveIfChanged() async {
    final snapshot = _workout;
    if (snapshot == null || !_hasUnsavedChanges) return;
    _hasUnsavedChanges = false;
    try {
      await repository.saveWorkout(snapshot);
      if (_disposed) return;
      errorMessage = null;
    } catch (error) {
      _hasUnsavedChanges = true;
      if (!_disposed) {
        errorMessage = _saveErrorMessage(error);
      }
    }
    await activeWorkout.load();
    _notify();
  }

  Future<void> _reloadSilently() async {
    final loaded = await repository.readWorkout(workoutId);
    if (_disposed) return;
    _workout = loaded ?? _workout;
    _notify();
  }

  String _saveErrorMessage(Object error) {
    if (error is WorkoutValidationException && error.fields.isNotEmpty) {
      return error.fields.values.first;
    }
    return 'Speichern fehlgeschlagen. Deine Änderung bleibt auf dem Bildschirm und kann erneut gespeichert werden.';
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
