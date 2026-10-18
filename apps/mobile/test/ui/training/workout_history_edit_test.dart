import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/local/local_mutation.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/ui/features/training/active_workout_controller.dart';
import 'package:gainer_mobile/ui/features/training/workout_screen.dart';

import 'training_test_support.dart';

WorkoutBlock _bank(List<LoggedSet> sets) => WorkoutBlock(
  workoutExerciseId: 'bank-block',
  sourceExerciseId: 'bank-source',
  exerciseNameSnapshot: 'Bankdrücken',
  exerciseTypeSnapshot: ExerciseKind.strength,
  sets: sets,
);

void main() {
  late TrainingHarness harness;
  late ActiveWorkoutController activeWorkout;

  setUp(() async {
    harness = await TrainingHarness.create();
    activeWorkout = ActiveWorkoutController(harness.repository);
  });

  tearDown(() async {
    activeWorkout.dispose();
    await harness.dispose();
  });

  Future<Workout> seedHistoric() => harness.seedWorkout(
    title: 'Push',
    start: DateTime.utc(2026, 10, 9, 17),
    end: DateTime.utc(2026, 10, 9, 18),
    blocks: [
      _bank(const [LoggedSet(setId: 's1', weightKg: 100, repetitions: 8)]),
    ],
  );

  testWidgets('Satz im historischen Training ändern wird gespeichert', (
    tester,
  ) async {
    final push = (await tester.runAsync(seedHistoric))!;
    await tester.runAsync(
      () => harness.seedWorkout(
        title: 'Legs',
        start: DateTime.utc(2026, 10, 15, 17),
        end: DateTime.utc(2026, 10, 15, 18),
        blocks: [
          _bank(const [LoggedSet(setId: 'l1', weightKg: 40, repetitions: 5)]),
        ],
      ),
    );
    // Die Trainings gelten als gesendet; die Änderung wird ein eigenes Update.
    await tester.runAsync(harness.markOutboxSent);

    await tester.pumpWidget(
      trainingTestApp(
        home: Builder(
          builder: (context) => CupertinoButton(
            onPressed: () => openWorkoutScreen(
              context,
              repository: harness.repository,
              activeWorkout: activeWorkout,
              workoutId: push.workoutId,
            ),
            child: const Text('Öffnen'),
          ),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Öffnen'));
    await settle(tester);

    final repetitions = find.descendant(
      of: find.bySemanticsLabel('Wdh.'),
      matching: find.byType(CupertinoTextField),
    );
    await tester.enterText(repetitions.first, '10');
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester);

    final saved = await tester.runAsync(
      () => harness.repository.readWorkout(push.workoutId),
    );
    expect(saved?.exercises.single.sets.single.repetitions, 10);
    expect(saved?.endedAtUtc, push.endedAtUtc);
    final outbox = (await tester.runAsync(harness.store.readOutbox))!;
    expect(outbox.last.operation, LocalMutationOperation.update);
    expect(tester.takeException(), isNull);
  });

  test('geänderter Satz erscheint im Tagebuch', () async {
    final push = await seedHistoric();
    await harness.seedWorkout(
      title: 'Legs',
      start: DateTime.utc(2026, 10, 15, 17),
      end: DateTime.utc(2026, 10, 15, 18),
      blocks: [
        _bank(const [LoggedSet(setId: 'l1', weightKg: 40, repetitions: 5)]),
      ],
    );

    final loaded = (await harness.repository.readWorkout(push.workoutId))!;
    final block = loaded.exercises.single;
    await harness.repository.saveWorkout(
      loaded.copyWith(
        exercises: [
          block.copyWith(
            sets: [block.sets.single.copyWith(repetitions: () => 10)],
          ),
        ],
      ),
    );

    final diary = await harness.repository.readDiary();
    expect(
      diary
          .firstWhere((w) => w.workoutId == push.workoutId)
          .exercises
          .single
          .sets
          .single
          .repetitions,
      10,
    );
  });
}
