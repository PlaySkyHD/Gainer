import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/ui/features/training/active_workout_controller.dart';
import 'package:gainer_mobile/ui/features/training/workout_screen.dart';
import 'package:gainer_mobile/ui/features/training/workout_summary_screen.dart';

import 'training_plans_test_support.dart';
import 'training_test_support.dart';
import 'workout_flow_test_support.dart';

WorkoutBlock _bench(List<LoggedSet> sets, {String source = 'bench'}) =>
    WorkoutBlock(
      workoutExerciseId: 'block-$source',
      sourceExerciseId: source,
      exerciseNameSnapshot: source == 'bench' ? 'Bankdrücken' : 'Kniebeuge',
      exerciseTypeSnapshot: ExerciseKind.strength,
      sets: sets,
    );

void main() {
  late TrainingHarness harness;
  late ActiveWorkoutController active;

  setUp(() async {
    harness = await TrainingHarness.create();
    active = ActiveWorkoutController(harness.repository);
  });

  tearDown(() async {
    active.dispose();
    await harness.dispose();
  });

  Future<void> pumpSummary(WidgetTester tester, String workoutId) async {
    usePhoneSize(tester);
    await tester.pumpWidget(
      trainingTestApp(
        home: WorkoutSummaryScreen(
          repository: harness.repository,
          workoutId: workoutId,
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets(
    'Zusammenfassung zeigt Sätze, Wiederholungen, Volumen und besten Satz',
    (tester) async {
      final workout = await tester.runAsync(
        () => harness.seedWorkout(
          title: 'Push',
          start: DateTime.utc(2026, 10, 17, 8),
          end: DateTime.utc(2026, 10, 17, 9),
          blocks: [
            _bench(const [
              LoggedSet(setId: 's1', weightKg: 20, repetitions: 6),
            ]),
          ],
        ),
      );

      await pumpSummary(tester, workout!.workoutId);

      expect(find.text('Stark gemacht!'), findsOneWidget);
      expect(find.text('Dein 1. Training · 1. diese Woche'), findsOneWidget);
      expect(find.text('Push'), findsOneWidget);
      expect(find.textContaining('· 60 min'), findsOneWidget);
      expect(find.text('120 kg'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
      expect(find.text('Bester Satz'), findsOneWidget);
      expect(find.text('Bankdrücken'), findsOneWidget);
      expect(find.text('20 kg × 6'), findsOneWidget);
    },
  );

  testWidgets('neuer 1RM-Rekord wird hervorgehoben', (tester) async {
    await tester.runAsync(
      () => harness.seedWorkout(
        title: 'Beine A',
        start: DateTime.utc(2026, 10, 10, 8),
        end: DateTime.utc(2026, 10, 10, 9),
        blocks: [
          _bench(const [
            LoggedSet(setId: 'o1', weightKg: 125, repetitions: 6),
          ], source: 'squat'),
        ],
      ),
    );
    final workout = await tester.runAsync(
      () => harness.seedWorkout(
        title: 'Beine B',
        start: DateTime.utc(2026, 10, 17, 8),
        end: DateTime.utc(2026, 10, 17, 9),
        blocks: [
          _bench(const [
            LoggedSet(setId: 'n1', weightKg: 130, repetitions: 6),
          ], source: 'squat'),
        ],
      ),
    );

    await pumpSummary(tester, workout!.workoutId);

    expect(find.text('Kniebeuge: Neuer Rekord: 1RM 156 kg'), findsOneWidget);
  });

  testWidgets('Wochenzähler zählt Trainings insgesamt und in der Woche', (
    tester,
  ) async {
    for (final start in [
      DateTime.utc(2026, 10, 2, 8),
      DateTime.utc(2026, 10, 13, 8),
    ]) {
      await tester.runAsync(
        () => harness.seedWorkout(
          title: 'Früher',
          start: start,
          end: start.add(const Duration(hours: 1)),
          blocks: [
            _bench(const [LoggedSet(setId: 'p', weightKg: 40, repetitions: 5)]),
          ],
        ),
      );
    }
    final workout = await tester.runAsync(
      () => harness.seedWorkout(
        title: 'Push',
        start: DateTime.utc(2026, 10, 17, 8),
        end: DateTime.utc(2026, 10, 17, 9),
        blocks: [
          _bench(const [LoggedSet(setId: 's', weightKg: 40, repetitions: 5)]),
        ],
      ),
    );

    await pumpSummary(tester, workout!.workoutId);

    expect(find.text('Dein 3. Training · 2. diese Woche'), findsOneWidget);
  });

  testWidgets('Training über Mitternacht zählt für die Woche des Starts', (
    tester,
  ) async {
    final workout = await tester.runAsync(
      () => harness.seedWorkout(
        title: 'Spät',
        // Sonntag 23:30 bis Montag 00:20 Ortszeit.
        start: DateTime(2026, 10, 18, 23, 30).toUtc(),
        end: DateTime(2026, 10, 19, 0, 20).toUtc(),
        blocks: [
          _bench(const [LoggedSet(setId: 's', weightKg: 40, repetitions: 5)]),
        ],
      ),
    );

    await pumpSummary(tester, workout!.workoutId);

    expect(find.text('Dein 1. Training · 1. diese Woche'), findsOneWidget);
  });

  testWidgets('Training fortsetzen öffnet das Training ohne Endzeit', (
    tester,
  ) async {
    final id = await startActiveWorkout(
      tester,
      harness,
      active,
      blocks: [
        _bench(const [LoggedSet(setId: 's', weightKg: 20, repetitions: 6)]),
      ],
    );
    await pumpWorkoutFromHost(tester, harness, active, id);
    await tester.tap(find.text('Beenden'));
    await settle(tester);
    expect(find.byType(WorkoutSummaryScreen), findsOneWidget);

    await tester.tap(find.text('Noch nicht fertig? Training fortsetzen'));
    await settle(tester);

    expect((await storedWorkout(tester, harness, id))!.endedAtUtc, isNull);
    expect(find.byType(WorkoutSummaryScreen), findsNothing);
    expect(find.byType(WorkoutScreen), findsOneWidget);
    expect(find.text('Beenden'), findsOneWidget);
  });

  testWidgets('Fortsetzen meldet ein bereits aktives Training verständlich', (
    tester,
  ) async {
    final finished = await tester.runAsync(
      () => harness.seedWorkout(
        title: 'Früher',
        start: DateTime.utc(2026, 10, 10, 8),
        end: DateTime.utc(2026, 10, 10, 9),
        blocks: [
          _bench(const [LoggedSet(setId: 'p', weightKg: 40, repetitions: 5)]),
        ],
      ),
    );
    await tester.runAsync(
      () => harness.seedWorkout(
        title: 'Aktiv',
        start: DateTime.utc(2026, 10, 17, 8),
      ),
    );

    await pumpSummary(tester, finished!.workoutId);
    await tester.tap(find.text('Noch nicht fertig? Training fortsetzen'));
    await settle(tester);

    expect(
      find.textContaining('Ein anderes Training ist bereits aktiv'),
      findsOneWidget,
    );
    expect(
      (await storedWorkout(tester, harness, finished.workoutId))!.endedAtUtc,
      isNotNull,
    );
  });
}
