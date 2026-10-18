import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/training/training_preferences.dart';
import 'package:gainer_mobile/domain/models/training/exercise_catalog_model.dart';
import 'package:gainer_mobile/domain/models/training/warmup.dart';
import 'package:gainer_mobile/domain/models/training/workout_input.dart';
import 'package:gainer_mobile/ui/features/training/active_workout_controller.dart';
import 'package:gainer_mobile/ui/features/training/exercise_editor_screen.dart';
import 'package:gainer_mobile/ui/features/training/workout_screen.dart';

import 'exercise_catalog_test_support.dart';
import 'training_plans_test_support.dart';
import 'training_test_support.dart';
import 'workout_flow_test_support.dart';

Future<TrainingPreferenceValues> _stored(
  WidgetTester tester,
  TrainingPreferences preferences,
) async => (await tester.runAsync(preferences.read))!;

Future<void> _show(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<TrainingPreferences> _openSheet(WidgetTester tester) async {
  usePhoneSize(tester);
  final harness = await tester.runAsync(TrainingHarness.create);
  if (harness == null) throw StateError('Harness nicht erstellt.');
  addTearDown(() => tester.runAsync(harness.dispose));
  final active = ActiveWorkoutController(harness.repository);
  addTearDown(active.dispose);
  final workout = await tester.runAsync(
    () => harness.seedWorkout(
      title: 'Push',
      start: DateTime.utc(2026, 10, 17, 8),
      blocks: const [],
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
  await tester.tap(labelled('Weitere Aktionen'));
  await settle(tester);
  await tester.tap(find.text('Aufwärmhinweis'));
  await settle(tester);
  return harness.repository.preferences;
}

void main() {
  group('Einstellungs-Sheet im Trainingsmenü', () {
    testWidgets('zeigt Standardwerte', (tester) async {
      await _openSheet(tester);

      expect(find.byKey(const ValueKey('warmup-percent-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('warmup-percent-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('warmup-percent-2')), findsNothing);
      expect(find.text('50'), findsOneWidget);
      expect(find.text('80'), findsOneWidget);
      expect(find.text('Wiederholungen anzeigen'), findsOneWidget);
      final repetitions = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('warmup-show-repetitions')),
      );
      expect(repetitions.value, isFalse);
    });

    testWidgets('Schalter für Wiederholungen wird gespeichert', (tester) async {
      final preferences = await _openSheet(tester);

      await tester.tap(find.byKey(const ValueKey('warmup-show-repetitions')));
      await settle(tester);

      expect(
        (await _stored(tester, preferences)).warmup.showRepetitions,
        isTrue,
      );
    });

    testWidgets('Ausschalten blendet die Stufen aus und speichert', (
      tester,
    ) async {
      final preferences = await _openSheet(tester);

      await tester.tap(find.byKey(const ValueKey('warmup-enabled')));
      await settle(tester);

      expect((await _stored(tester, preferences)).warmup.enabled, isFalse);
      expect(find.byKey(const ValueKey('warmup-percent-0')), findsNothing);
      expect(find.text('Wiederholungen anzeigen'), findsNothing);
    });

    testWidgets('Prozent und Wiederholungen einer Stufe ändern', (
      tester,
    ) async {
      final preferences = await _openSheet(tester);

      await tester.enterText(
        find.byKey(const ValueKey('warmup-percent-0')),
        '40',
      );
      await tester.enterText(find.byKey(const ValueKey('warmup-reps-0')), '10');
      await settle(tester);

      expect((await _stored(tester, preferences)).warmup.steps, const [
        WarmupStep(percent: 40, repetitions: 10),
        WarmupStep(percent: 80),
      ]);
    });

    testWidgets('ungültige Eingaben behalten den letzten gültigen Wert', (
      tester,
    ) async {
      final preferences = await _openSheet(tester);

      await tester.enterText(
        find.byKey(const ValueKey('warmup-percent-0')),
        '0',
      );
      await tester.enterText(find.byKey(const ValueKey('warmup-reps-0')), '99');
      await settle(tester);

      expect(
        (await _stored(tester, preferences)).warmup.steps.first,
        const WarmupStep(percent: 50),
      );
    });

    testWidgets('Stufe hinzufügen bis fünf und löschen', (tester) async {
      final preferences = await _openSheet(tester);

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const ValueKey('warmup-add-step')));
        await settle(tester);
      }

      var steps = (await _stored(tester, preferences)).warmup.steps;
      expect([for (final s in steps) s.percent], [50, 80, 90, 100, 100]);
      expect(find.byKey(const ValueKey('warmup-add-step')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('warmup-delete-0')));
      await settle(tester);

      steps = (await _stored(tester, preferences)).warmup.steps;
      expect([for (final s in steps) s.percent], [80, 90, 100, 100]);
      expect(find.byKey(const ValueKey('warmup-add-step')), findsOneWidget);
    });

    testWidgets('alle Stufen lassen sich löschen', (tester) async {
      final preferences = await _openSheet(tester);

      await tester.tap(find.byKey(const ValueKey('warmup-delete-0')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('warmup-delete-0')));
      await settle(tester);

      expect((await _stored(tester, preferences)).warmup.steps, isEmpty);
    });
  });

  group('Abschnitt „Aufwärmen“ im Übungseditor', () {
    Future<(CatalogHarness, CatalogExercise)> openEditor(
      WidgetTester tester, {
      CatalogExercise? exercise,
      bool own = true,
    }) async {
      final harness = await tester.runAsync(CatalogHarness.create);
      if (harness == null) throw StateError('Harness nicht erstellt.');
      addTearDown(() => tester.runAsync(harness.dispose));
      final target = own
          ? (await tester.runAsync(
              () => seedOwnExercise(harness, name: 'Curl'),
            ))!
          : exercise!;
      usePhoneSize(tester);
      await tester.pumpWidget(
        catalogHost(
          buildRoute: (_) => ExerciseEditorScreen(
            repository: harness.repository,
            exercise: target,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open-under-test')));
      await settle(tester);
      return (harness, target);
    }

    Future<ExerciseWarmupOverride?> storedOverride(
      WidgetTester tester,
      CatalogHarness harness,
      String id,
    ) async =>
        (await tester.runAsync(harness.repository.preferences.read))!
            .warmupOverrides[id];

    testWidgets('neue Übung hat noch keinen Abschnitt', (tester) async {
      final harness = await tester.runAsync(CatalogHarness.create);
      addTearDown(() => tester.runAsync(harness!.dispose));
      usePhoneSize(tester);
      await tester.pumpWidget(
        catalogHost(
          buildRoute: (_) =>
              ExerciseEditorScreen(repository: harness!.repository),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open-under-test')));
      await settle(tester);

      expect(find.text('Aufwärmen'), findsNothing);
    });

    testWidgets('Standard ist vorgewählt und speichert nichts', (tester) async {
      final (harness, exercise) = await openEditor(tester);
      await _show(tester, find.text('Aufwärmen'));

      expect(find.text('Aufwärmen'), findsOneWidget);
      expect(find.text('Standard'), findsOneWidget);
      expect(find.byKey(const ValueKey('warmup-percent-0')), findsNothing);
      expect(find.text('2,5 kg'), findsOneWidget);
      expect(await storedOverride(tester, harness, exercise.id), isNull);
    });

    testWidgets(
      'Eigene Stufen starten mit den globalen und speichern Änderungen',
      (tester) async {
        final (harness, exercise) = await openEditor(tester);
        await _show(tester, find.text('Eigene Stufen'));

        await tester.tap(find.text('Eigene Stufen'));
        await settle(tester);
        expect(
          (await storedOverride(tester, harness, exercise.id))!.steps,
          defaultWarmupSteps,
        );

        await _show(tester, find.byKey(const ValueKey('warmup-percent-0')));
        await tester.enterText(
          find.byKey(const ValueKey('warmup-percent-0')),
          '60',
        );
        await settle(tester);

        expect(
          (await storedOverride(tester, harness, exercise.id))!.steps,
          const [WarmupStep(percent: 60), WarmupStep(percent: 80)],
        );
      },
    );

    testWidgets('Aus speichert, Standard entfernt die Abweichung wieder', (
      tester,
    ) async {
      final (harness, exercise) = await openEditor(tester);
      await _show(tester, find.text('Aus'));

      await tester.tap(find.text('Aus'));
      await settle(tester);
      expect(
        (await storedOverride(tester, harness, exercise.id))!.enabled,
        isFalse,
      );
      expect(find.byKey(const ValueKey('warmup-rounding')), findsNothing);

      await tester.tap(find.text('Standard'));
      await settle(tester);
      expect(await storedOverride(tester, harness, exercise.id), isNull);
    });

    testWidgets('Rundung wählen und auf Standard zurücksetzen', (tester) async {
      final (harness, exercise) = await openEditor(tester);
      await _show(tester, find.byKey(const ValueKey('warmup-rounding')));

      await tester.tap(find.byKey(const ValueKey('warmup-rounding')));
      await settle(tester);
      await tester.tap(find.text('1,25 kg'));
      await settle(tester);

      expect(
        (await storedOverride(tester, harness, exercise.id))!.rounding,
        1.25,
      );
      expect(find.text('1,25 kg'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('warmup-rounding')));
      await settle(tester);
      await tester.tap(find.text('2,5 kg (Standard)'));
      await settle(tester);

      expect(await storedOverride(tester, harness, exercise.id), isNull);
    });

    testWidgets('in lbs bietet die Rundung lbs-Stufen an', (tester) async {
      final harness = await tester.runAsync(CatalogHarness.create);
      addTearDown(() => tester.runAsync(harness!.dispose));
      final exercise = (await tester.runAsync(() async {
        await harness!.repository.preferences.update(
          (v) => v.copyWith(weightUnit: WeightUnit.lbs),
        );
        return seedOwnExercise(harness, name: 'Curl');
      }))!;
      usePhoneSize(tester);
      await tester.pumpWidget(
        catalogHost(
          buildRoute: (_) => ExerciseEditorScreen(
            repository: harness!.repository,
            exercise: exercise,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open-under-test')));
      await settle(tester);

      await _show(tester, find.byKey(const ValueKey('warmup-rounding')));
      expect(find.text('5 lbs'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('warmup-rounding')));
      await settle(tester);

      expect(find.text('10 lbs'), findsOneWidget);
      expect(find.text('1,25 lbs'), findsNothing);
    });

    testWidgets('eine Basisübung zeigt den Abschnitt trotz Schreibschutz', (
      tester,
    ) async {
      final (harness, _) = await openEditor(
        tester,
        exercise: baseBench,
        own: false,
      );
      await _show(tester, find.text('Eigene Stufen'));

      await tester.tap(find.text('Aus'));
      await settle(tester);

      expect(find.byKey(const ValueKey('exercise-save')), findsNothing);
      expect(
        (await storedOverride(tester, harness, baseBench.id))!.enabled,
        isFalse,
      );
    });
  });
}
