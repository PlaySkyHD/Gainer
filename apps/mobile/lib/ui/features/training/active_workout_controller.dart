import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../../domain/models/training/workout_model.dart';
import 'rest_timer_controller.dart';

/// Hält das laufende Training des Kontos für Tagebuch, Trainingsleiste und
/// Trainingsscreen. Hängt am `AccountScope`, damit ein Kontowechsel einen
/// frischen Zustand ohne Daten des alten Kontos liefert.
///
/// Der Pausentimer lebt hier mit dem aktiven Training, nicht im Screen: Minimieren
/// oder Schließen des Trainingsscreens lässt ihn weiterlaufen, damit die
/// Ablaufbenachrichtigung erhalten bleibt. Er endet mit dem Training.
class ActiveWorkoutController extends ChangeNotifier {
  ActiveWorkoutController(this._repository, {this.restTimerFactory});

  final TrainingLogRepository _repository;

  /// Baut den Pausentimer je aktivem Training. Ohne Fabrik gibt es keinen Timer.
  final RestTimerController Function(String workoutId)? restTimerFactory;

  /// `true`, wenn Live Activities in den iOS-Einstellungen aus sind. Der
  /// Live-Activity-Coordinator hält den Wert aktuell.
  final ValueNotifier<bool> liveActivitiesOff = ValueNotifier(false);

  /// Öffnet die App-Einstellungen; setzt der Live-Activity-Coordinator.
  Future<void> Function()? openLiveActivitySettings;
  Workout? _active;
  RestTimerController? _restTimer;
  bool _disposed = false;

  /// Das aktive Training oder null, wenn keines läuft.
  Workout? get active => _active;

  bool get hasActiveWorkout => _active != null;

  /// Pausentimer des aktiven Trainings; null ohne aktives Training oder ohne Fabrik.
  RestTimerController? get restTimer => _restTimer;

  /// Fehler des letzten Ladevorgangs; null, wenn er geklappt hat.
  Object? lastLoadError;

  /// Liest den Stand aus dem lokalen Speicher. Wird nach jeder Änderung
  /// eines Trainings und nach Synchronisation aufgerufen.
  /// Schlägt das Lesen fehl, bleibt der letzte bekannte Stand erhalten. Der
  /// Aufrufer (z. B. eine Speicher-Queue) bricht dadurch nicht ab.
  Future<void> load() async {
    try {
      final workout = await _repository.readActiveWorkout();
      lastLoadError = null;
      if (_disposed || _sameAs(workout)) return;
      _active = workout;
      _syncRestTimer();
      notifyListeners();
    } catch (error, stackTrace) {
      lastLoadError = error;
      debugPrint(
        'Aktives Training konnte nicht geladen werden: $error\n$stackTrace',
      );
    }
  }

  /// Beendet den Pausentimer eines Trainings, das beendet oder gelöscht wurde.
  /// Ein späterer [load] ohne aktives Training fände sonst nichts mehr zu beenden.
  Future<void> endRestTimer(String workoutId) async {
    final timer = _restTimer;
    if (timer == null || timer.workoutId != workoutId) return;
    _restTimer = null;
    await _endTimer(timer);
    notifyListeners();
  }

  /// Setzt den Timer zurück und gibt ihn frei; das meldet auch den
  /// Lifecycle-Beobachter ab.
  Future<void> _endTimer(RestTimerController timer) async {
    await timer.endForWorkout();
    timer.dispose();
  }

  /// Vollständiger Vergleich, damit auch Satz- und Übungsänderungen die
  /// Beobachter erreichen (z. B. die Live Activity).
  bool _sameAs(Workout? workout) => _active == workout;

  /// Hält genau einen Timer für das aktive Training. Verschwindet das Training
  /// ohne [endRestTimer], etwa durch Sync, wird der Timer hier beendet.
  void _syncRestTimer() {
    final factory = restTimerFactory;
    final workoutId = _active?.workoutId;
    if (factory == null || _restTimer?.workoutId == workoutId) return;
    final previous = _restTimer;
    _restTimer = null;
    if (previous != null) unawaited(_endTimer(previous));
    if (workoutId == null) return;
    final timer = factory(workoutId);
    _restTimer = timer;
    unawaited(timer.load().catchError((Object _) {}));
  }

  @override
  void dispose() {
    _disposed = true;
    _restTimer?.dispose();
    _restTimer = null;
    liveActivitiesOff.dispose();
    super.dispose();
  }
}
