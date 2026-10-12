import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/data/services/native/native_feature_lifecycle_coordinator.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';
import 'package:gainer_mobile/domain/models/training/training.dart';
import 'package:gainer_mobile/ui/features/body/body_view_model.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_view_model.dart';
import 'package:gainer_mobile/ui/features/training/training_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'session end tombstones widget state and cancels workout alerts',
    (tester) async {
      final database = LocalDatabase(NativeDatabase.memory());
      final training = _Training();
      training.runningWorkoutId = 'workout-123';
      final snapshots = _Snapshots();
      final notifications = _Notifications();
      final coordinator = _coordinator(
        database: database,
        training: training,
        snapshots: snapshots,
        notifications: notifications,
      );

      coordinator.activate();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.runAsync(() => coordinator.disposeForSessionEnd());

      expect(snapshots.published, hasLength(1));
      expect(snapshots.clearedGenerations, [
        snapshots.published.single.generation + 1,
      ]);
      expect(notifications.cancelled, ['workout-123']);
      await database.close();
    },
  );

  testWidgets('expired rest resumes as workout without changing local record', (
    tester,
  ) async {
    final database = LocalDatabase(NativeDatabase.memory());
    final training = _Training()
      ..runningWorkoutId = 'workout-456'
      ..runningWorkout = WorkoutRecord(
        sourceTemplateId: null,
        templateNameSnapshot: 'Strength',
        status: 'running',
        exercises: const [],
        startedAtUtc: DateTime.utc(2026, 10, 12, 9).toIso8601String(),
        completedAtUtc: null,
        discardedAtUtc: null,
        updatedAtUtc: DateTime.utc(2026, 10, 12, 9).toIso8601String(),
        restTimer: RestTimerRecord(
          sourceSetId: 'set-1',
          durationSeconds: 60,
          targetAtUtc: DateTime.utc(2026, 10, 12, 9, 1).toIso8601String(),
        ),
      );
    final activities = _Activities();
    final coordinator = _coordinator(
      database: database,
      training: training,
      activities: activities,
      clock: () => DateTime.utc(2026, 10, 12, 9, 2),
    );

    coordinator.activate();
    training.changed();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );

    expect(activities.started, hasLength(1));
    expect(activities.started.single.status, LiveActivityStatus.workout);
    expect(activities.started.single.restEndsAtUtc, isNull);
    expect(training.runningWorkout!.restTimer, isNotNull);

    await tester.runAsync(() => coordinator.disposeForSessionEnd());
    await database.close();
  });
}

NativeFeatureLifecycleCoordinator _coordinator({
  required LocalDatabase database,
  required _Training training,
  _Snapshots? snapshots,
  _Activities? activities,
  _Notifications? notifications,
  DateTime Function()? clock,
}) => NativeFeatureLifecycleCoordinator(
  installationDatabase: database,
  training: training,
  body: _Body(),
  nutrition: _Nutrition(),
  snapshots: snapshots ?? _Snapshots(),
  activities: activities ?? _Activities(),
  haptics: _Haptics(),
  notifications: notifications ?? _Notifications(),
  isSessionActive: () => true,
  clock: clock,
);

class _Training extends ChangeNotifier implements TrainingViewModel {
  @override
  WorkoutRecord? runningWorkout;
  @override
  String? runningWorkoutId;
  @override
  bool isSaving = false;
  @override
  String? errorMessage;

  void changed() => notifyListeners();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Body extends ChangeNotifier implements BodyViewModel {
  @override
  bool isSaving = false;
  @override
  String? errorMessage;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Nutrition extends ChangeNotifier implements NutritionViewModel {
  @override
  bool isSaving = false;
  @override
  String? errorMessage;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Snapshots implements ExtensionSnapshotPlatform {
  final published = <NeutralExtensionSnapshot>[];
  final clearedGenerations = <int>[];

  @override
  Future<void> publish(NeutralExtensionSnapshot snapshot) async =>
      published.add(snapshot);
  @override
  Future<void> clear({required int minimumGeneration}) async =>
      clearedGenerations.add(minimumGeneration);
}

class _Activities implements LiveActivityPlatform {
  final started = <LiveActivityState>[];

  @override
  Future<bool> start({required LiveActivityState state}) async {
    started.add(state);
    return true;
  }

  @override
  Future<bool> update({required LiveActivityState state}) async => true;
  @override
  Future<void> end(String sessionId) async {}
  @override
  Future<void> endAll() async {}
}

class _Notifications implements TimerNotificationPlatform {
  final cancelled = <String>[];

  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> schedule({
    required String workoutId,
    required int generation,
    required DateTime targetAtUtc,
  }) async {}
  @override
  Future<void> cancel(String workoutId) async => cancelled.add(workoutId);
}

class _Haptics implements HapticsPlatform {
  @override
  Future<void> perform(HapticIntent intent) async {}
}
