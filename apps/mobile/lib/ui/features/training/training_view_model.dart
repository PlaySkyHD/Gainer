import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/training/training_repository.dart';
import '../../../domain/models/training/training.dart';

class TrainingViewModel extends ChangeNotifier {
  TrainingViewModel(this.repository);

  final TrainingRepository repository;
  TrainingPlanningSnapshot? planning;
  WorkoutRecord? runningWorkout;
  String? runningWorkoutId;
  List<TrainingHistoryEntry> history = const [];
  Map<String, PreviousPerformance?> previousByExerciseId = const {};
  bool isLoading = false;
  bool isSaving = false;
  String? errorMessage;
  String? notificationNotice;
  Timer? _ticker;
  bool _disposed = false;

  int? get remainingRestSeconds =>
      repository.remainingRestSeconds(runningWorkout?.restTimer);

  void reportNotificationUnavailable() {
    if (_disposed) return;
    notificationNotice = 'Die Pause-Benachrichtigung ist gerade nicht verfügbar. Der Timer läuft in der App weiter.';
    notifyListeners();
  }

  Future<void> load() => _load(resumeTimerNotification: true);

  /// Refreshes persisted state after a successful server pull without asking
  /// for notification permission as a side effect of sync.
  Future<void> refreshAfterSync() => _load(resumeTimerNotification: false);

  Future<void> _load({required bool resumeTimerNotification}) => _run(() async {
    planning = await repository.readPlanning();
    final rows = await repository.store.readAggregates('workout');
    final running = rows.where((row) {
      final value = WorkoutRecord.fromJson(
        row.workingCopy as Map<String, dynamic>,
      );
      return value.isRunning;
    });
    if (running.isNotEmpty) {
      runningWorkoutId = running.first.aggregateId;
      runningWorkout = WorkoutRecord.fromJson(
        running.first.workingCopy as Map<String, dynamic>,
      );
    } else {
      runningWorkoutId = null;
      runningWorkout = null;
    }
    history = await repository.readHistory();
    final previous = <String, PreviousPerformance?>{};
    for (final exercise in runningWorkout?.exercises ?? const []) {
      final id = exercise.sourceExerciseId;
      if (id != null && !previous.containsKey(id)) {
        previous[id] = await repository.previousPerformance(id);
      }
    }
    previousByExerciseId = Map.unmodifiable(previous);
    _syncTicker();
    if (resumeTimerNotification) {
      await repository.resumeRestTimerNotification();
    }
  });

  Future<void> createExercise(String name) => _run(() async {
    await repository.createCustomExercise(ExerciseValues(name: name));
    planning = await repository.readPlanning();
  }, saving: true);

  Future<void> saveExercise(String? id, ExerciseValues values) =>
      _run(() async {
        if (id == null) {
          await repository.createCustomExercise(values);
        } else {
          await repository.updateCustomExercise(id, values);
        }
        planning = await repository.readPlanning();
      }, saving: true);

  Future<void> archiveExercise(String id) => _run(() async {
    await repository.archiveCustomExercise(id);
    planning = await repository.readPlanning();
  }, saving: true);

  Future<void> archiveTemplate(String id) => _run(() async {
    await repository.archiveTemplate(id);
    planning = await repository.readPlanning();
  }, saving: true);

  Future<void> saveRotation(List<String> templateIds) => _run(() async {
    await repository.saveRotation(templateIds);
    planning = await repository.readPlanning();
  }, saving: true);

  Future<void> saveTemplate({
    String? id,
    required String name,
    required List<TrainingTemplateItem> items,
  }) => _run(() async {
    await repository.saveTemplate(id: id, name: name, items: items);
    planning = await repository.readPlanning();
  }, saving: true);

  Future<void> start(String templateId) => _run(() async {
    runningWorkoutId = await repository.startWorkout(templateId);
    await load();
  }, saving: true);

  Future<void> logSet({
    required String exerciseId,
    required String setId,
    required double? weightKg,
    required int? repetitions,
    required double? rir,
    required String? notes,
    required bool complete,
  }) => _run(() async {
    runningWorkout = await repository.logSet(
      workoutId: runningWorkoutId!,
      exerciseId: exerciseId,
      setId: setId,
      weightKg: weightKg,
      repetitions: repetitions,
      rir: rir,
      notes: notes,
      complete: complete,
    );
    final sourceId = runningWorkout!.exercises
        .firstWhere((exercise) => exercise.id == exerciseId)
        .sourceExerciseId;
    if (sourceId != null) {
      previousByExerciseId = Map.unmodifiable({
        ...previousByExerciseId,
        sourceId: await repository.previousPerformance(sourceId),
      });
    }
    _syncTicker();
  }, saving: true);

  Future<void> addSet(String exerciseId) => _run(() async {
    runningWorkout = await repository.addSet(
      workoutId: runningWorkoutId!,
      workoutExerciseId: exerciseId,
    );
  }, saving: true);

  Future<void> removeSet(String exerciseId, String setId) => _run(() async {
    runningWorkout = await repository.removeSet(
      workoutId: runningWorkoutId!,
      workoutExerciseId: exerciseId,
      setId: setId,
    );
  }, saving: true);

  Future<void> addExercise(String exerciseId) => _run(() async {
    runningWorkout = await repository.addExerciseToWorkout(
      workoutId: runningWorkoutId!,
      exerciseId: exerciseId,
    );
  }, saving: true);

  Future<void> removeExercise(String exerciseId) => _run(() async {
    runningWorkout = await repository.removeExerciseFromWorkout(
      workoutId: runningWorkoutId!,
      workoutExerciseId: exerciseId,
    );
  }, saving: true);

  Future<void> moveExercise(String exerciseId, int position) => _run(() async {
    runningWorkout = await repository.moveExercise(
      workoutId: runningWorkoutId!,
      workoutExerciseId: exerciseId,
      targetPosition: position,
    );
  }, saving: true);

  Future<void> moveSet(String exerciseId, String setId, int position) =>
      _run(() async {
        runningWorkout = await repository.moveSet(
          workoutId: runningWorkoutId!,
          workoutExerciseId: exerciseId,
          setId: setId,
          targetPosition: position,
        );
      }, saving: true);

  Future<void> moveTemplateInRotation(List<String> ids, int from, int to) {
    if (to < 0 || to >= ids.length) return Future.value();
    final reordered = [...ids];
    final item = reordered.removeAt(from);
    reordered.insert(to, item);
    return saveRotation(reordered);
  }

  Future<void> finish() => _run(() async {
    await repository.completeWorkout(runningWorkoutId!);
    runningWorkout = null;
    runningWorkoutId = null;
    history = await repository.readHistory();
    _syncTicker();
  }, saving: true);

  Future<void> discard() => _run(() async {
    await repository.discardWorkout(runningWorkoutId!);
    runningWorkout = null;
    runningWorkoutId = null;
    _syncTicker();
  }, saving: true);

  Future<void> timerAction(Future<WorkoutRecord> Function(String) action) =>
      _run(() async {
        runningWorkout = await action(runningWorkoutId!);
        _syncTicker();
      }, saving: true);

  void _syncTicker() {
    _ticker?.cancel();
    if (_disposed) return;
    if (runningWorkout?.restTimer == null) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed) {
        _ticker?.cancel();
        return;
      }
      if (runningWorkout?.restTimer?.remainingSeconds(DateTime.now()) == 0) {
        _ticker?.cancel();
      }
      notifyListeners();
    });
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool saving = false,
  }) async {
    if (_disposed) return;
    isLoading = !saving;
    isSaving = saving;
    errorMessage = null;
    notificationNotice = null;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isLoading = false;
      isSaving = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    super.dispose();
  }
}
