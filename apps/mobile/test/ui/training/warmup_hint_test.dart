import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/training/training_preferences.dart';
import 'package:gainer_mobile/domain/models/training/warmup.dart';
import 'package:gainer_mobile/domain/models/training/workout_input.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/ui/features/training/active_workout_controller.dart';
import 'package:gainer_mobile/ui/features/training/workout_screen.dart';

import 'training_plans_test_support.dart';
import 'training_test_support.dart';
import 'workout_flow_test_support.dart';

WorkoutBlock _block(
  String id,
  String sourceId,
  List<LoggedSet> sets, {
  String? name,
}) => WorkoutBlock(
  workoutExerciseId: id,
  sourceExerciseId: sourceId,
  exerciseNameSnapshot: name ?? id,
  exerciseTypeSnapshot: ExerciseKind.strength,
  sets: sets,
);

/// Historisches Training mit 80 kg × 8 in „bench“ und 30 kg × 10 in „curl“.
List<WorkoutBlock> _history({double bench = 80}) => [
  _block('old-bench', 'bench', [
    LoggedSet(setId: 'o1', weightKg: bench, repetitions: 8),
    LoggedSet(setId: 'o2', weightKg: bench, repetitions: 8),
  ], name: 'Bankdrücken'),
  _block('old-curl', 'curl', const [
    LoggedSet(setId: 'o3', weightKg: 30, repetitions: 10),
  ], name: 'Bizepscurl'),
];

class _Opened {
  _Opened(this.harness, this.active, this.workoutId);

  final TrainingHarness harness;
  final ActiveWorkoutController active;
  final String workoutId;
}

Future<_Opened> _open(
  WidgetTester tester, {
  List<WorkoutBlock>? history,
  List<WorkoutBlock>? current,
  bool ended = false,
  TrainingPreferenceValues Function(TrainingPreferenceValues)? preferences,
}) async {
  usePhoneSize(tester);
  final harness = await tester.runAsync(TrainingHarness.create);
  if (harness == null) throw StateError('Harness nicht erstellt.');
  addTearDown(() => tester.runAsync(harness.dispose));
  final active = ActiveWorkoutController(harness.repository);
  addTearDown(active.dispose);
  if (preferences != null) {
    await tester.runAsync(
      () => harness.repository.preferences.update(preferences),
    );
  }
  if (history != null) {
    await tester.runAsync(
      () => harness.seedWorkout(
        title: 'Alt',
        start: DateTime.utc(2026, 10, 10, 8),
        end: DateTime.utc(2026, 10, 10, 9),
        blocks: history,
      ),
    );
  }
  final blocks =
      current ??
      [
        _block('bench', 'bench', const [
          LoggedSet(setId: 'b1'),
          LoggedSet(setId: 'b2'),
        ], name: 'Bankdrücken'),
      ];
  final workout = await tester.runAsync(
    () => harness.seedWorkout(
      title: 'Neu',
      start: DateTime.utc(2026, 10, 17, 8),
      end: ended ? DateTime.utc(2026, 10, 17, 9) : null,
      blocks: blocks,
    ),
  );
  await tester.runAsync(active.load);
  await tester.pumpWidget(
    trainingTestApp(
      home: WorkoutScreen(
        repository: harness.repository,
        activeWorkout: active,
        workoutId: workout!.workoutId,
      ),
    ),
  );
  await settle(tester);
  return _Opened(harness, active, workout.workoutId);
}

Finder get _hint => labelled('Aufwärmhinweis');

void main() {
  testWidgets('Standardstufen zeigen 40 kg und 65 kg zum Vorwert 80 kg', (
    tester,
  ) async {
    await _open(tester, history: _history());

    expect(find.text('Aufwärmen 40 kg · 65 kg'), findsOneWidget);
    expect(_hint, findsOneWidget);
    expect(find.byIcon(CupertinoIcons.flame), findsOneWidget);
  });

  testWidgets('mit Wiederholungen: 50 kg × 8 · 80 kg × 3 zum Vorwert 100 kg', (
    tester,
  ) async {
    await _open(
      tester,
      history: _history(bench: 100),
      preferences: (v) => v.copyWith(
        warmup: const WarmupSettings(
          showRepetitions: true,
          steps: [
            WarmupStep(percent: 50, repetitions: 8),
            WarmupStep(percent: 80, repetitions: 3),
          ],
        ),
      ),
    );

    expect(find.text('Aufwärmen 50 kg × 8 · 80 kg × 3'), findsOneWidget);
  });

  testWidgets('ohne Wiederholungsschalter bleiben Wiederholungen verborgen', (
    tester,
  ) async {
    await _open(
      tester,
      history: _history(bench: 100),
      preferences: (v) => v.copyWith(
        warmup: const WarmupSettings(
          steps: [WarmupStep(percent: 50, repetitions: 8)],
        ),
      ),
    );

    expect(find.text('Aufwärmen 50 kg'), findsOneWidget);
  });

  testWidgets('in lbs wird in lbs gerundet', (tester) async {
    await _open(
      tester,
      history: _history(bench: WeightUnit.lbs.toKg(225)),
      preferences: (v) => v.copyWith(weightUnit: WeightUnit.lbs),
    );

    expect(find.text('Aufwärmen 115 lbs · 180 lbs'), findsOneWidget);
  });

  testWidgets('ohne Vorwert gibt es keinen Hinweis', (tester) async {
    await _open(tester);

    expect(_hint, findsNothing);
  });

  testWidgets('ein Vorwert ohne Gewicht gibt keinen Hinweis', (tester) async {
    await _open(
      tester,
      history: [
        _block('old', 'bench', const [LoggedSet(setId: 'o', repetitions: 8)]),
      ],
    );

    expect(_hint, findsNothing);
  });

  testWidgets('global ausgeschaltet gibt es keinen Hinweis', (tester) async {
    await _open(
      tester,
      history: _history(),
      preferences: (v) =>
          v.copyWith(warmup: const WarmupSettings(enabled: false)),
    );

    expect(_hint, findsNothing);
  });

  testWidgets('für eine Übung aus fehlt der Hinweis nur dort', (tester) async {
    await _open(
      tester,
      history: _history(),
      current: [
        _block('bench', 'bench', const [
          LoggedSet(setId: 'b1'),
        ], name: 'Bankdrücken'),
        _block('curl', 'curl', const [
          LoggedSet(setId: 'c1'),
        ], name: 'Bizepscurl'),
      ],
      preferences: (v) => v.copyWith(
        warmupOverrides: {
          'curl': const ExerciseWarmupOverride(
            exerciseId: 'curl',
            enabled: false,
          ),
        },
      ),
    );

    expect(_hint, findsOneWidget);
    expect(find.text('Aufwärmen 40 kg · 65 kg'), findsOneWidget);
  });

  testWidgets('eigene Stufen und Rundung der Übung gelten', (tester) async {
    await _open(
      tester,
      history: _history(bench: 83),
      preferences: (v) => v.copyWith(
        warmupOverrides: {
          'bench': const ExerciseWarmupOverride(
            exerciseId: 'bench',
            steps: [WarmupStep(percent: 60)],
            rounding: 1,
          ),
        },
      ),
    );

    expect(find.text('Aufwärmen 50 kg'), findsOneWidget);
  });

  testWidgets('bereits vorhandene Aufwärmsätze unterdrücken den Hinweis', (
    tester,
  ) async {
    await _open(
      tester,
      history: _history(),
      current: [
        _block('bench', 'bench', const [
          LoggedSet(setId: 'w1', setType: SetType.warmup, weightKg: 40),
          LoggedSet(setId: 'b1'),
        ]),
      ],
    );

    expect(_hint, findsNothing);
  });

  testWidgets('in einem historischen Training erscheint kein Hinweis', (
    tester,
  ) async {
    await _open(tester, history: _history(), ended: true);

    expect(_hint, findsNothing);
  });

  testWidgets('der Hinweis allein verändert das gespeicherte Training nicht', (
    tester,
  ) async {
    final opened = await _open(tester, history: _history());

    final stored = await storedWorkout(
      tester,
      opened.harness,
      opened.workoutId,
    );

    expect(stored!.exercises.single.sets, hasLength(2));
    expect(
      stored.exercises.single.sets.any((s) => s.setType == SetType.warmup),
      isFalse,
    );
  });

  testWidgets('Eintragen legt Aufwärmsätze vor dem ersten Arbeitssatz an', (
    tester,
  ) async {
    final opened = await _open(tester, history: _history());

    await tester.tap(_hint);
    await settle(tester);
    expect(find.text('Als Aufwärmsätze eintragen'), findsOneWidget);
    await tester.tap(find.text('Als Aufwärmsätze eintragen'));
    await settle(tester);

    expect(_hint, findsNothing);
    final stored = await storedWorkout(
      tester,
      opened.harness,
      opened.workoutId,
    );
    final sets = stored!.exercises.single.sets;
    expect(
      [for (final s in sets) s.setType],
      [SetType.warmup, SetType.warmup, SetType.normal, SetType.normal],
    );
    expect([for (final s in sets.take(2)) s.weightKg], [40, 65]);
    expect([for (final s in sets) s.setId].skip(2), ['b1', 'b2']);
  });

  testWidgets('Eintragen übernimmt die Wiederholungen der Stufen', (
    tester,
  ) async {
    final opened = await _open(
      tester,
      history: _history(bench: 100),
      preferences: (v) => v.copyWith(
        warmup: const WarmupSettings(
          steps: [
            WarmupStep(percent: 50, repetitions: 8),
            WarmupStep(percent: 80, repetitions: 3),
          ],
        ),
      ),
    );

    await tester.tap(_hint);
    await settle(tester);
    await tester.tap(find.text('Als Aufwärmsätze eintragen'));
    await settle(tester);

    final stored = await storedWorkout(
      tester,
      opened.harness,
      opened.workoutId,
    );
    final sets = stored!.exercises.single.sets.take(2).toList();
    expect([for (final s in sets) s.weightKg], [50, 80]);
    expect([for (final s in sets) s.repetitions], [8, 3]);
  });

  testWidgets('Schließen des Sheets trägt nichts ein', (tester) async {
    final opened = await _open(tester, history: _history());

    await tester.tap(_hint);
    await settle(tester);
    await tester.tapAt(const Offset(195, 40));
    await settle(tester);

    final stored = await storedWorkout(
      tester,
      opened.harness,
      opened.workoutId,
    );
    expect(stored!.exercises.single.sets, hasLength(2));
    expect(_hint, findsOneWidget);
  });
}
