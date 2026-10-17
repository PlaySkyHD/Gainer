import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/previous_values.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';
import 'package:gainer_mobile/ui/features/training/active_workout_controller.dart';
import 'package:gainer_mobile/ui/features/training/repeat_workout_sheet.dart';
import 'package:gainer_mobile/ui/features/training/training_format.dart';

import 'training_test_support.dart';

WorkoutBlock _bankdruecken(List<LoggedSet> sets) => WorkoutBlock(
  workoutExerciseId: 'bank-block',
  sourceExerciseId: 'bank-source',
  exerciseNameSnapshot: 'Bankdrücken',
  exerciseTypeSnapshot: ExerciseKind.strength,
  sets: sets,
);

/// Ein Aufwärmsatz, zwei normale Sätze und ein Dropsatz mit Werten.
List<LoggedSet> _pushSets() => const [
  LoggedSet(setId: 'w', setType: SetType.warmup, weightKg: 60, repetitions: 10),
  LoggedSet(setId: 's1', weightKg: 100, repetitions: 8),
  LoggedSet(setId: 's2', weightKg: 100, repetitions: 7),
  LoggedSet(setId: 'd', setType: SetType.dropset, weightKg: 80, repetitions: 6),
];

Finder _inDialog(String label) => find.descendant(
  of: find.byType(GainerStackedDialog<bool>),
  matching: find.text(label),
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

  Widget host(Workout source) => Builder(
    builder: (context) => CupertinoButton(
      onPressed: () => showRepeatWorkoutSheet(
        context,
        repository: harness.repository,
        activeWorkout: activeWorkout,
        source: source,
      ),
      child: const Text('Wiederholen öffnen'),
    ),
  );

  Future<void> pumpHost(WidgetTester tester, Workout source) async {
    await tester.pumpWidget(trainingTestApp(home: host(source)));
    await settle(tester);
    await tester.tap(find.text('Wiederholen öffnen'));
    await settle(tester);
  }

  Future<Workout> seedPush() async {
    final workout = await harness.seedWorkout(
      title: 'Push',
      start: DateTime.utc(2026, 10, 9, 17),
      end: DateTime.utc(2026, 10, 9, 18),
      blocks: [_bankdruecken(_pushSets())],
    );
    return workout;
  }

  testWidgets(
    'Wiederholtes Training startet ohne Werte mit gleichen Satztypen',
    (tester) async {
      final source = (await tester.runAsync(seedPush))!;
      await pumpHost(tester, source);

      expect(find.text('Training wiederholen'), findsOneWidget);
      expect(find.text('Aktuellste'), findsOneWidget);
      expect(find.text('Wiederholtes Training'), findsOneWidget);
      expect(
        find.text(
          'Werte vom ${formatShortDate(source.startedAtUtc.toLocal())}',
        ),
        findsOneWidget,
      );
      expect(find.text('Trainingsplan'), findsNothing);

      await tester.tap(find.text('Wiederholtes Training'));
      await settle(tester);
      expect(find.byIcon(CupertinoIcons.checkmark), findsOneWidget);
      await tester.tap(find.text('Training beginnen'));
      await settle(tester);

      final active = await tester.runAsync(
        harness.repository.readActiveWorkout,
      );
      expect(active?.title, 'Push');
      expect(active?.sourceWorkoutId, source.workoutId);
      expect(active?.previousValueSource, PreviousValueSource.workout);
      final block = active!.exercises.single;
      expect(block.sets.map((set) => set.setType), [
        SetType.warmup,
        SetType.normal,
        SetType.normal,
        SetType.dropset,
      ]);
      expect(
        block.sets.every(
          (set) => set.weightKg == null && set.repetitions == null,
        ),
        isTrue,
      );
      expect(find.text('Beenden'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Trainingsplan ist nur mit sourcePlanId wählbar', (tester) async {
    final source = (await tester.runAsync(seedPush))!;
    final fromPlan = source.copyWith(sourcePlanId: () => testId(900));
    await pumpHost(tester, fromPlan);

    expect(find.text('Trainingsplan'), findsOneWidget);
    await tester.tap(find.text('Trainingsplan'));
    await settle(tester);
    await tester.tap(find.text('Training beginnen'));
    await settle(tester);

    final active = await tester.runAsync(harness.repository.readActiveWorkout);
    expect(active?.previousValueSource, PreviousValueSource.plan);
  });

  testWidgets('bei aktivem Training Fortsetzen-Dialog statt zweitem Training', (
    tester,
  ) async {
    final source = (await tester.runAsync(seedPush))!;
    await tester.runAsync(() async {
      await harness.seedWorkout(
        title: 'Legs',
        start: DateTime.utc(2026, 10, 17, 8),
      );
      await activeWorkout.load();
    });
    await pumpHost(tester, source);

    await tester.tap(find.text('Training beginnen'));
    await settle(tester);
    expect(_inDialog('Aktives Training fortsetzen'), findsOneWidget);
    await tester.tap(_inDialog('Aktives Training fortsetzen'));
    await settle(tester);

    final diary = await tester.runAsync(harness.repository.readDiary);
    expect(diary, hasLength(2));
    final active = await tester.runAsync(harness.repository.readActiveWorkout);
    expect(active?.title, 'Legs');
    expect(find.text('Beenden'), findsOneWidget);
  });

  test('wiederholtes Quelltraining gelöscht: Vorwerte fallen auf nach Übung zurück', () async {
    await harness.seedWorkout(
      title: 'Push',
      start: DateTime.utc(2026, 10, 1, 9),
      end: DateTime.utc(2026, 10, 1, 10),
      blocks: [
        _bankdruecken(const [
          LoggedSet(setId: 'o1', weightKg: 90, repetitions: 5),
        ]),
      ],
    );
    final source = await harness.seedWorkout(
      title: 'Push',
      start: DateTime.utc(2026, 10, 9, 9),
      end: DateTime.utc(2026, 10, 9, 10),
      blocks: [
        _bankdruecken(const [
          LoggedSet(setId: 's1', weightKg: 100, repetitions: 8),
        ]),
      ],
    );
    harness.now = DateTime.utc(2026, 10, 17, 9);
    final repository = harness.repository;
    final repeated = await repository.startRepeat(
      source.workoutId,
      previousValueSource: PreviousValueSource.workout,
    );
    final blockId = repeated.exercises.single.workoutExerciseId;

    final before = previousValuesFor(
      repeated,
      await repository.readDiary(),
    )[blockId]!;
    expect(before.single?.weightKg, 100);

    await repository.deleteWorkout(source.workoutId);

    final kept = await repository.readWorkout(repeated.workoutId);
    expect(kept, isNotNull);
    expect(kept?.sourceWorkoutId, source.workoutId);
    final after = previousValuesFor(
      repeated,
      await repository.readDiary(),
    )[blockId]!;
    expect(after.single?.weightKg, 90);
    expect(after.single?.repetitions, 5);
  });
}
