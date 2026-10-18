import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/timer/rest_timer_state.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/ui/features/training/active_workout_controller.dart';
import 'package:gainer_mobile/ui/features/training/workout_view_model.dart';

import 'rest_timer_test_support.dart';
import 'training_test_support.dart';

WorkoutBlock _emptyBench() => WorkoutBlock(
  workoutExerciseId: 'bench',
  sourceExerciseId: 'bench-source',
  exerciseNameSnapshot: 'Bankdrücken',
  exerciseTypeSnapshot: ExerciseKind.strength,
  sets: [
    LoggedSet(setId: 'set-0'),
    LoggedSet(setId: 'set-1'),
  ],
);

void main() {
  late TrainingHarness harness;
  late RestTimerFixture fixture;
  late ActiveWorkoutController active;
  late String workoutId;

  setUp(() async {
    harness = await TrainingHarness.create();
    fixture = RestTimerFixture();
    active = activeWorkoutWithTimers(harness, fixture);
    final workout = await harness.seedWorkout(
      title: 'Push',
      start: DateTime.utc(2026, 10, 17, 8),
      blocks: [_emptyBench()],
    );
    workoutId = workout.workoutId;
    await active.load();
  });

  tearDown(() async {
    fixture.disposeControllers();
    active.dispose();
    await harness.dispose();
  });

  Future<WorkoutViewModel> openModel({required bool autoStart}) async {
    await harness.repository.preferences.update(
      (v) => v.copyWith(autoStartRestTimer: autoStart),
    );
    final model = WorkoutViewModel(
      repository: harness.repository,
      activeWorkout: active,
      workoutId: workoutId,
    );
    addTearDown(model.dispose);
    await model.load();
    return model;
  }

  Future<void> record(WorkoutViewModel model, String setId) async {
    await model.setWeight('bench', setId, 80);
    await model.setRepetitions('bench', setId, 8);
  }

  test('ohne Auto-Start startet ein erfasster Satz keinen Timer', () async {
    final model = await openModel(autoStart: false);

    await record(model, 'set-0');

    expect(active.restTimer!.phase, RestTimerPhase.ready);
    expect(fixture.notifications.scheduled, isEmpty);
  });

  test(
    'mit Auto-Start startet der Timer erst beim vollständigen Satz',
    () async {
      final model = await openModel(autoStart: true);

      await model.setWeight('bench', 'set-0', 80);
      expect(active.restTimer!.phase, RestTimerPhase.ready);

      await model.setRepetitions('bench', 'set-0', 8);
      expect(active.restTimer!.phase, RestTimerPhase.running);
      expect(active.restTimer!.remainingSeconds, 180);
      expect(fixture.notifications.scheduled, hasLength(1));
    },
  );

  test('Bearbeiten eines erfassten Satzes startet nichts', () async {
    final model = await openModel(autoStart: true);
    await record(model, 'set-0');
    await active.restTimer!.close();
    expect(active.restTimer!.phase, RestTimerPhase.ready);

    await model.setWeight('bench', 'set-0', 82.5);

    expect(active.restTimer!.phase, RestTimerPhase.ready);
  });

  test(
    'laufender Timer bleibt beim nächsten erfassten Satz unverändert',
    () async {
      final model = await openModel(autoStart: true);
      await record(model, 'set-0');
      fixture.clock.now = fixture.clock.now.add(const Duration(seconds: 140));
      final before = active.restTimer!.state;
      expect(active.restTimer!.remainingSeconds, 40);

      await record(model, 'set-1');

      expect(identical(active.restTimer!.state, before), isTrue);
      expect(active.restTimer!.remainingSeconds, 40);
      expect(fixture.notifications.scheduled, hasLength(1));
    },
  );

  test('abgelaufener Timer startet mit dem nächsten Satz neu', () async {
    final model = await openModel(autoStart: true);
    await record(model, 'set-0');
    final timer = active.restTimer!;
    fixture.clock.now = fixture.clock.now.add(const Duration(seconds: 200));
    await timer.load();
    expect(timer.phase, RestTimerPhase.expired);

    await record(model, 'set-1');

    expect(timer.phase, RestTimerPhase.running);
    expect(timer.remainingSeconds, 180);
  });

  test('Auto-Start nutzt die zuletzt gewählte Dauer', () async {
    final model = await openModel(autoStart: true);
    await active.restTimer!.startShortcut(90);
    await active.restTimer!.close();

    await record(model, 'set-0');

    expect(active.restTimer!.remainingSeconds, 90);
  });

  test('historisches Training startet nie einen Timer', () async {
    harness.now = DateTime.utc(2026, 10, 17, 9);
    final finished = await harness.repository.finishWorkout(workoutId);
    await active.load();
    expect(active.restTimer, isNull);
    await harness.repository.preferences.update(
      (v) => v.copyWith(autoStartRestTimer: true),
    );
    final model = WorkoutViewModel(
      repository: harness.repository,
      activeWorkout: active,
      workoutId: finished.workoutId,
    );
    addTearDown(model.dispose);
    await model.load();

    await record(model, 'set-0');

    expect(fixture.notifications.scheduled, isEmpty);
  });
}
