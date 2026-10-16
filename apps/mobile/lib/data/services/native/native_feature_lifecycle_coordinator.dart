import 'package:flutter/widgets.dart';

import '../../../domain/models/training/training.dart';
import '../../../ui/features/body/body_view_model.dart';
import '../../../ui/features/nutrition/nutrition_view_model.dart';
import '../../../ui/features/training/training_view_model.dart';
import '../../services/local/local_database.dart';
import '../../services/platform/platform_ports.dart';

/// Publishes neutral extension routes and the minimum state needed by an
/// explicitly started workout Live Activity. It never publishes account data,
/// nutrition, or credentials to the App Group.
class NativeFeatureLifecycleCoordinator with WidgetsBindingObserver {
  NativeFeatureLifecycleCoordinator({
    required this.installationDatabase,
    required this.training,
    required this.body,
    required this.nutrition,
    required this.snapshots,
    required this.activities,
    required this.haptics,
    required this.notifications,
    required this.isSessionActive,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now {
    WidgetsBinding.instance.addObserver(this);
    training.addListener(_onTrainingChanged);
    body.addListener(_onBodyChanged);
    nutrition.addListener(_onNutritionChanged);
  }

  final LocalDatabase installationDatabase;
  final TrainingViewModel training;
  final BodyViewModel body;
  final NutritionViewModel nutrition;
  final ExtensionSnapshotPlatform snapshots;
  final LiveActivityPlatform activities;
  final HapticsPlatform haptics;
  final TimerNotificationPlatform notifications;
  final bool Function() isSessionActive;
  final DateTime Function() clock;
  Future<void> _pending = Future<void>.value();
  bool _active = true;
  String? _activitySessionId;
  RestTimerRecord? _lastRestTimer;
  bool _trainingSaving = false;
  bool _bodySaving = false;
  bool _nutritionSaving = false;

  void activate() => _chain(_publishNeutralSnapshot);

  void _chain(Future<void> Function() action) {
    _pending = _pending.then((_) async {
      if (!_active || !isSessionActive()) return;
      try {
        await action();
      } catch (_) {
        // Extension features are optional. Local workouts remain usable.
      }
    });
  }

  void _onTrainingChanged() {
    final wasSaving = _trainingSaving;
    _trainingSaving = training.isSaving;
    if (wasSaving && !_trainingSaving && training.errorMessage == null) {
      _performHaptic(HapticIntent.commit);
    }
    final previousRest = _lastRestTimer;
    final nextRest = training.runningWorkout?.restTimer;
    if (previousRest != null &&
        nextRest == null &&
        DateTime.parse(previousRest.targetAtUtc)
            .toUtc()
            .isBefore(clock().toUtc())) {
      _performHaptic(HapticIntent.timerComplete);
    }
    _lastRestTimer = nextRest;
    _chain(_syncActivity);
  }

  void _onBodyChanged() {
    final wasSaving = _bodySaving;
    _bodySaving = body.isSaving;
    if (wasSaving && !_bodySaving && body.errorMessage == null) {
      _performHaptic(HapticIntent.commit);
    }
  }

  void _onNutritionChanged() {
    final wasSaving = _nutritionSaving;
    _nutritionSaving = nutrition.isSaving;
    if (wasSaving && !_nutritionSaving && nutrition.errorMessage == null) {
      _performHaptic(HapticIntent.commit);
    }
  }

  void _performHaptic(HapticIntent intent) {
    if (!_active || !isSessionActive()) return;
    haptics.perform(intent).catchError((Object _) {});
  }

  Future<void> _publishNeutralSnapshot() async {
    if (!_active || !isSessionActive()) return;
    final generation = await _nextGeneration();
    if (!_active || !isSessionActive()) return;
    await snapshots.publish(
      NeutralExtensionSnapshot(
        schemaVersion: 1,
        generation: generation,
        updatedAtUtc: clock().toUtc(),
        availableRoutes: const {'training', 'checkIn', 'nutrition'},
      ),
    );
  }

  Future<void> _syncActivity() async {
    final workout = training.runningWorkout;
    final id = training.runningWorkoutId;
    if (workout == null || id == null || !workout.isRunning) {
      await _endPriorActivity();
      return;
    }
    if (!_active || !isSessionActive()) return;
    final now = clock().toUtc();
    final restEnd = _activeRestEnd(workout.restTimer, now);
    final state = LiveActivityState(
      sessionId: id,
      status: restEnd == null
          ? LiveActivityStatus.workout
          : LiveActivityStatus.rest,
      startedAtUtc: DateTime.parse(workout.startedAtUtc).toUtc(),
      restEndsAtUtc: restEnd,
      staleAtUtc: _staleAtUtc(restEnd, now),
    );
    if (_activitySessionId != id) {
      await _replaceActivitySession(id, state);
    } else {
      await _updateActivitySession(id, state);
    }
  }

  Future<void> _endPriorActivity() async {
    final prior = _activitySessionId;
    if (prior != null) {
      _activitySessionId = null;
      await activities.end(prior);
    }
  }

  DateTime? _activeRestEnd(RestTimerRecord? rest, DateTime now) {
    if (rest == null) return null;
    final requestedRestEnd = DateTime.parse(rest.targetAtUtc).toUtc();
    return requestedRestEnd.isAfter(now) ? requestedRestEnd : null;
  }

  DateTime _staleAtUtc(DateTime? restEnd, DateTime now) {
    if (restEnd == null) return now.add(const Duration(hours: 8));
    final extended = restEnd.add(const Duration(minutes: 5));
    return extended.isAfter(now)
        ? extended
        : now.add(const Duration(minutes: 5));
  }

  Future<void> _replaceActivitySession(
    String id,
    LiveActivityState state,
  ) async {
    final previous = _activitySessionId;
    if (previous != null) await activities.end(previous);
    if (!_active || !isSessionActive()) return;
    if (await activities.start(state: state)) _activitySessionId = id;
  }

  Future<void> _updateActivitySession(
    String id,
    LiveActivityState state,
  ) async {
    if (!_active || !isSessionActive()) return;
    if (!await activities.update(state: state)) {
      if (!_active || !isSessionActive()) return;
      if (await activities.start(state: state)) _activitySessionId = id;
    }
  }

  Future<int> _nextGeneration() => installationDatabase.transaction(() async {
    final row =
        await (installationDatabase.select(
              installationDatabase.installationMetadata,
            )..where((table) => table.key.equals('native-feature-generation')))
            .getSingleOrNull();
    final previous = row == null ? 0 : (int.tryParse(row.value) ?? 0);
    final next = previous + 1;
    await installationDatabase
        .into(installationDatabase.installationMetadata)
        .insertOnConflictUpdate(
          InstallationMetadataCompanion.insert(
            key: 'native-feature-generation',
            value: '$next',
          ),
        );
    return next;
  });

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _chain(_syncActivity);
  }

  Future<void> disposeForSessionEnd() async {
    if (!_active) return;
    _active = false;
    WidgetsBinding.instance.removeObserver(this);
    training.removeListener(_onTrainingChanged);
    body.removeListener(_onBodyChanged);
    nutrition.removeListener(_onNutritionChanged);
    await _pending;
    final generation = await _nextGeneration();
    try {
      await snapshots.clear(minimumGeneration: generation);
    } catch (_) {}
    try {
      await activities.endAll();
    } catch (_) {}
    _activitySessionId = null;
    final workoutId = training.runningWorkoutId;
    if (workoutId != null) {
      try {
        await notifications.cancel(workoutId);
      } catch (_) {}
    }
  }
}
