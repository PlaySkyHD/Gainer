import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/ui/core/shell/mobile_tab_scaffold.dart';
import 'package:gainer_mobile/ui/core/view_models/mobile_shell_view_model.dart';
import 'package:gainer_mobile/ui/features/training/active_workout_controller.dart';
import 'package:gainer_mobile/ui/features/training/compact_training_bar.dart';
import 'package:gainer_mobile/ui/features/training/set_row.dart';
import 'package:gainer_mobile/ui/features/training/training_home_screen.dart';
import 'package:gainer_mobile/ui/features/training/workout_metadata_card.dart';
import 'package:gainer_mobile/ui/features/training/workout_screen.dart';

import 'training_test_support.dart';

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    final name = brightness.name;

    testWidgets('Tagebuch mit Trainings $name', (tester) async {
      _phoneSize(tester);
      final harness = await tester.runAsync(TrainingHarness.create);
      if (harness == null) throw StateError('Harness nicht erstellt.');
      addTearDown(() => tester.runAsync(harness.dispose));
      final active = ActiveWorkoutController(harness.repository);
      addTearDown(active.dispose);
      await tester.runAsync(() async {
        await harness.seedWorkout(
          title: 'Push',
          start: DateTime(2026, 10, 2, 7).toUtc(),
          end: DateTime(2026, 10, 2, 8, 2).toUtc(),
          blocks: [strengthBlock('Bankdrücken', 3, id: 'push')],
        );
        await harness.seedWorkout(
          title: 'Legs 2',
          start: DateTime(2026, 10, 15, 18).toUtc(),
          end: DateTime(2026, 10, 15, 20, 9).toUtc(),
          blocks: [
            strengthBlock('Beinbeuger', 2, id: 'legs-a'),
            strengthBlock('Beinstrecker', 3, id: 'legs-b'),
          ],
        );
        await harness.seedWorkout(
          title: 'Ganzkörper',
          start: DateTime(2026, 9, 28, 17).toUtc(),
          end: DateTime(2026, 9, 28, 18).toUtc(),
          blocks: [strengthBlock('Kniebeuge', 4, id: 'full')],
        );
        await active.load();
      });

      await tester.pumpWidget(
        trainingTestApp(
          brightness: brightness,
          home: TrainingHomeScreen(
            repository: harness.repository,
            activeWorkout: active,
          ),
        ),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(TrainingHomeScreen),
        matchesGoldenFile('goldens/training_diary_$name.png'),
      );
    });

    testWidgets('Tagebuch leer $name', (tester) async {
      _phoneSize(tester);
      final harness = await tester.runAsync(TrainingHarness.create);
      if (harness == null) throw StateError('Harness nicht erstellt.');
      addTearDown(() => tester.runAsync(harness.dispose));
      final active = ActiveWorkoutController(harness.repository);
      addTearDown(active.dispose);

      await tester.pumpWidget(
        trainingTestApp(
          brightness: brightness,
          home: TrainingHomeScreen(
            repository: harness.repository,
            activeWorkout: active,
          ),
        ),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(TrainingHomeScreen),
        matchesGoldenFile('goldens/training_diary_empty_$name.png'),
      );
    });

    for (final (variant, scale) in const [
      ('active', 1.0),
      ('historic', 1.0),
      ('active', 1.3),
    ]) {
      final label = scale == 1.0 ? variant : '${variant}_scale13';
      testWidgets('Trainingskopf $label $name', (tester) async {
        _phoneSize(tester);
        final harness = await tester.runAsync(TrainingHarness.create);
        if (harness == null) throw StateError('Harness nicht erstellt.');
        addTearDown(() => tester.runAsync(harness.dispose));
        final active = ActiveWorkoutController(harness.repository);
        addTearDown(active.dispose);
        final workout = await tester.runAsync(
          () => harness.seedWorkout(
            title: variant == 'active' ? 'Push' : 'Legs 2',
            start: DateTime(2026, 10, 16, 18).toUtc(),
            end: variant == 'active'
                ? null
                : DateTime(2026, 10, 16, 19, 10).toUtc(),
            blocks: [
              strengthBlock('Bankdrücken', 3, id: 'head'),
              strengthBlock('Beinbeuger', 2, id: 'head-b'),
            ],
          ),
        );
        if (workout == null) throw StateError('Training nicht angelegt.');
        await tester.runAsync(active.load);

        await tester.pumpWidget(
          trainingTestApp(
            brightness: brightness,
            textScale: scale,
            home: WorkoutScreen(
              repository: harness.repository,
              activeWorkout: active,
              workoutId: workout.workoutId,
            ),
          ),
        );
        await settle(tester);

        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(WorkoutScreen),
          matchesGoldenFile('goldens/workout_${label}_$name.png'),
        );
      });
    }

    testWidgets('Übungskarten mit Vorwerten und Superset $name', (
      tester,
    ) async {
      _phoneSize(tester);
      final harness = await tester.runAsync(TrainingHarness.create);
      if (harness == null) throw StateError('Harness nicht erstellt.');
      addTearDown(() => tester.runAsync(harness.dispose));
      final active = ActiveWorkoutController(harness.repository);
      addTearDown(active.dispose);
      final workoutId = await tester.runAsync(
        () => _seedPlanningWorkout(harness, active),
      );

      await tester.pumpWidget(
        trainingTestApp(
          brightness: brightness,
          home: WorkoutScreen(
            repository: harness.repository,
            activeWorkout: active,
            workoutId: workoutId!,
          ),
        ),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(WorkoutScreen),
        matchesGoldenFile('goldens/workout_blocks_$name.png'),
      );
    });

    testWidgets('Metadatenkarte $name', (tester) async {
      _phoneSize(tester);
      final harness = await tester.runAsync(TrainingHarness.create);
      if (harness == null) throw StateError('Harness nicht erstellt.');
      addTearDown(() => tester.runAsync(harness.dispose));
      final active = ActiveWorkoutController(harness.repository);
      addTearDown(active.dispose);
      final workoutId = await tester.runAsync(
        () => _seedPlanningWorkout(harness, active),
      );

      await tester.pumpWidget(
        trainingTestApp(
          brightness: brightness,
          home: WorkoutScreen(
            repository: harness.repository,
            activeWorkout: active,
            workoutId: workoutId!,
          ),
        ),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(WorkoutMetadataCard),
        matchesGoldenFile('goldens/workout_metadata_$name.png'),
      );
    });

    testWidgets('Satzzeile bei großer Schrift $name', (tester) async {
      _phoneSize(tester);
      final harness = await tester.runAsync(TrainingHarness.create);
      if (harness == null) throw StateError('Harness nicht erstellt.');
      addTearDown(() => tester.runAsync(harness.dispose));
      final active = ActiveWorkoutController(harness.repository);
      addTearDown(active.dispose);
      final workoutId = await tester.runAsync(
        () => _seedPlanningWorkout(harness, active),
      );

      await tester.pumpWidget(
        trainingTestApp(
          brightness: brightness,
          textScale: 1.3,
          home: WorkoutScreen(
            repository: harness.repository,
            activeWorkout: active,
            workoutId: workoutId!,
          ),
        ),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(SetRow).first,
        matchesGoldenFile('goldens/set_row_scale13_$name.png'),
      );
    });

    testWidgets('kompakte Trainingsleiste über der Tableiste $name', (
      tester,
    ) async {
      _phoneSize(tester);
      final harness = await tester.runAsync(TrainingHarness.create);
      if (harness == null) throw StateError('Harness nicht erstellt.');
      addTearDown(() => tester.runAsync(harness.dispose));
      final active = ActiveWorkoutController(harness.repository);
      addTearDown(active.dispose);
      await tester.runAsync(() async {
        await harness.seedWorkout(
          title: 'Push',
          start: DateTime.now().toUtc().subtract(
            const Duration(minutes: 12, seconds: 34),
          ),
        );
        await active.load();
      });
      final model = MobileShellViewModel();
      addTearDown(model.dispose);

      await tester.pumpWidget(
        trainingTestApp(
          brightness: brightness,
          home: MobileTabScaffold(
            model: model,
            compactTrainingBar: CompactTrainingBar(
              activeWorkout: active,
              repository: harness.repository,
            ),
            tabBuilder: (context, area) => const CupertinoPageScaffold(
              child: Center(child: Text('Heute-Inhalt')),
            ),
          ),
        ),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MobileTabScaffold),
        matchesGoldenFile('goldens/compact_training_bar_$name.png'),
      );
    });
  }
}

/// Vorjahr-Training mit 100 kg × 8 und 100 kg × 7 als Vorwerte, dazu ein
/// aktives Training mit einem Block ohne Eingaben, einem teilweise erfassten
/// Block und einem Superset.
Future<String> _seedPlanningWorkout(
  TrainingHarness harness,
  ActiveWorkoutController active,
) async {
  await harness.seedWorkout(
    title: 'Push A',
    start: DateTime.utc(2026, 10, 10, 8),
    end: DateTime.utc(2026, 10, 10, 9),
    blocks: [
      WorkoutBlock(
        workoutExerciseId: 'old-bench',
        sourceExerciseId: 'bench',
        exerciseNameSnapshot: 'Bankdrücken',
        exerciseTypeSnapshot: ExerciseKind.strength,
        sets: const [
          LoggedSet(setId: 'old-1', weightKg: 100, repetitions: 8),
          LoggedSet(setId: 'old-2', weightKg: 100, repetitions: 7),
        ],
      ),
    ],
  );
  final workout = await harness.seedWorkout(
    title: 'Push B',
    start: DateTime.utc(2026, 10, 16, 18),
    blocks: [
      WorkoutBlock(
        workoutExerciseId: 'bench',
        sourceExerciseId: 'bench',
        exerciseNameSnapshot: 'Bankdrücken',
        exerciseTypeSnapshot: ExerciseKind.strength,
        sets: const [
          LoggedSet(setId: 'bench-1'),
          LoggedSet(setId: 'bench-2', weightKg: 102.5, repetitions: 6),
        ],
      ),
      WorkoutBlock(
        workoutExerciseId: 'curl',
        sourceExerciseId: 'curl',
        exerciseNameSnapshot: 'Bizepscurl',
        exerciseTypeSnapshot: ExerciseKind.strength,
        supersetId: 'ss',
        sets: const [LoggedSet(setId: 'curl-1')],
      ),
      WorkoutBlock(
        workoutExerciseId: 'triceps',
        sourceExerciseId: 'triceps',
        exerciseNameSnapshot: 'Trizepsdrücken',
        exerciseTypeSnapshot: ExerciseKind.strength,
        supersetId: 'ss',
        sets: const [
          LoggedSet(setId: 'triceps-1', weightKg: 20, repetitions: 12),
        ],
      ),
    ],
  );
  await active.load();
  return workout.workoutId;
}

void _phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
