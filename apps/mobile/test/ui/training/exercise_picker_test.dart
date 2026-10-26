import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';
import 'package:gainer_mobile/ui/features/training/exercise_picker_sheet.dart';

import 'training_plans_test_support.dart';
import 'training_test_support.dart';

void main() {
  late TrainingHarness harness;

  setUp(() async {
    harness = await TrainingHarness.create();
  });

  tearDown(() async {
    await harness.dispose();
  });

  /// Öffnet die Übungsauswahl über einen Knopf und merkt sich das Ergebnis.
  Future<List<ExercisePickerResult?>> pumpPicker(
    WidgetTester tester, {
    bool allowSuperset = true,
    String? excludedExerciseId,
  }) async {
    usePhoneSize(tester);
    final results = <ExercisePickerResult?>[];
    await tester.pumpWidget(
      trainingTestApp(
        home: Builder(
          builder: (context) => Center(
            child: CupertinoButton(
              onPressed: () async {
                final result = await showExercisePicker(
                  context,
                  repository: harness.repository,
                  allowSuperset: allowSuperset,
                  excludedExerciseId: excludedExerciseId,
                );
                results.add(result);
              },
              child: const Text('Öffnen'),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Öffnen'));
    await settle(tester);
    return results;
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(CupertinoSearchTextField), query);
    await settle(tester);
  }

  testWidgets('Suche findet Kniebeuge und Bulgarische Kniebeuge', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seedExercise(harness, name: 'Kniebeuge');
      await seedExercise(harness, name: 'Bulgarische Kniebeuge');
      await seedExercise(harness, name: 'Bankdrücken');
    });
    await pumpPicker(tester);

    await search(tester, 'kniebeu');

    expect(pickerRow('Kniebeuge'), findsOneWidget);
    expect(pickerRow('Bulgarische Kniebeuge'), findsOneWidget);
    expect(pickerRow('Bankdrücken'), findsNothing);
  });

  testWidgets('ausgeschlossene Übung ist nicht wählbar', (tester) async {
    final source = (await tester.runAsync(
      () => seedExercise(harness, name: 'Kniebeuge LH'),
    ))!;
    await tester.runAsync(() => seedExercise(harness, name: 'Kniebeuge'));
    await pumpPicker(tester, excludedExerciseId: source.id);

    await search(tester, 'kniebeu');

    expect(pickerRow('Kniebeuge'), findsOneWidget);
    expect(pickerRow('Kniebeuge LH'), findsNothing);
  });

  testWidgets('Umlaut-Schreibweise findet Rücken und Ruecken gleichermaßen', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final back = await seedCategory(harness, 'Rücken');
      await seedExercise(
        harness,
        name: 'Rückenstrecker',
        categoryIds: [back.id],
      );
      await seedExercise(harness, name: 'Kniebeuge');
    });
    await pumpPicker(tester);

    await search(tester, 'Ruecken');
    expect(pickerRow('Rückenstrecker'), findsOneWidget);

    await search(tester, 'RÜCKEN');
    expect(pickerRow('Rückenstrecker'), findsOneWidget);
    expect(pickerRow('Kniebeuge'), findsNothing);
  });

  testWidgets('Archivierte Übungen erscheinen nicht', (tester) async {
    await tester.runAsync(() async {
      await seedExercise(harness, name: 'Altübung', archived: true);
      await seedExercise(harness, name: 'Aktuelle Übung');
    });
    await pumpPicker(tester);

    await search(tester, 'übung');

    expect(pickerRow('Aktuelle Übung'), findsOneWidget);
    expect(pickerRow('Altübung'), findsNothing);
  });

  testWidgets('Normalmodus: Tipp wählt genau eine Übung und schließt', (
    tester,
  ) async {
    await tester.runAsync(() => seedExercise(harness, name: 'Kniebeuge'));
    final results = await pumpPicker(tester);

    await search(tester, 'Kniebeuge');
    await tester.tap(pickerRow('Kniebeuge'));
    await settle(tester);

    expect(results, hasLength(1));
    expect(results.single?.asSuperset, isFalse);
    expect(results.single?.exercises.map((e) => e.name), ['Kniebeuge']);
    expect(find.text('Übung auswählen'), findsNothing);
  });

  testWidgets('Supersatz-Mehrfachauswahl liefert asSuperset mit zwei Übungen', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final arms = await seedCategory(harness, 'Arme');
      await seedExercise(harness, name: 'Bizeps Curl', categoryIds: [arms.id]);
      await seedExercise(
        harness,
        name: 'Trizeps Drücken',
        categoryIds: [arms.id],
      );
    });
    final results = await pumpPicker(tester);

    await tester.tap(find.text('Supersatz'));
    await settle(tester);
    await search(tester, 'curl');
    await tester.tap(pickerRow('Bizeps Curl'));
    await settle(tester);
    await search(tester, 'trizeps');
    await tester.tap(pickerRow('Trizeps Drücken'));
    await settle(tester);
    await tester.tap(find.text('Als Superset hinzufügen'));
    await settle(tester);

    expect(results, hasLength(1));
    final result = results.single!;
    expect(result.asSuperset, isTrue);
    expect(result.exercises.map((exercise) => exercise.name), [
      'Bizeps Curl',
      'Trizeps Drücken',
    ]);
  });

  testWidgets('Supersatz-Bestätigung ist erst ab zwei Übungen aktiv', (
    tester,
  ) async {
    await tester.runAsync(() => seedExercise(harness, name: 'Kniebeuge'));
    final results = await pumpPicker(tester);

    await tester.tap(find.text('Supersatz'));
    await settle(tester);
    await search(tester, 'Kniebeuge');
    await tester.tap(pickerRow('Kniebeuge'));
    await settle(tester);
    await tester.tap(find.text('Als Superset hinzufügen'));
    await settle(tester);

    expect(results, isEmpty);
    expect(find.text('Als Superset hinzufügen'), findsOneWidget);
  });

  testWidgets('Zuletzt verwendet kommt aus dem Tagebuch und steht oben', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final kneeling = await seedExercise(harness, name: 'Kniebeuge');
      await seedExercise(harness, name: 'Bankdrücken');
      await harness.seedWorkout(
        title: 'Beine',
        start: DateTime.utc(2026, 10, 15, 18),
        end: DateTime.utc(2026, 10, 15, 19),
        blocks: [
          WorkoutBlock(
            workoutExerciseId: harness.repository.newId(),
            sourceExerciseId: kneeling.id,
            exerciseNameSnapshot: kneeling.name,
            exerciseTypeSnapshot: ExerciseKind.strength,
            sets: [
              LoggedSet(
                setId: harness.repository.newId(),
                weightKg: 60,
                repetitions: 8,
              ),
            ],
          ),
        ],
      );
    });
    await pumpPicker(tester);

    expect(find.text('Zuletzt verwendet'), findsOneWidget);
    expect(find.text('Kategorien'), findsOneWidget);
    expect(pickerRow('Kniebeuge'), findsOneWidget);
    expect(pickerRow('Bankdrücken'), findsNothing);
  });

  testWidgets('Eigene Übung schnell anlegen wählt sie direkt aus', (
    tester,
  ) async {
    final results = await pumpPicker(tester, allowSuperset: false);

    await tester.tap(find.byIcon(CupertinoIcons.add));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('quick-create-name')),
      'Landmine Press',
    );
    await settle(tester);
    await tester.tap(find.text('Anlegen'));
    await settle(tester);

    expect(results, hasLength(1));
    expect(results.single?.exercises.single.name, 'Landmine Press');
    expect(
      results.single?.exercises.single.exerciseType,
      ExerciseKind.strength,
    );
  });

  testWidgets('Kategorie öffnet ihre Übungen', (tester) async {
    await tester.runAsync(() async {
      final legs = await seedCategory(harness, 'Beine');
      await seedExercise(harness, name: 'Beinpresse', categoryIds: [legs.id]);
      await seedExercise(harness, name: 'Bankdrücken');
    });
    await pumpPicker(tester);

    await tester.tap(find.widgetWithText(GainerListRow, 'Beine'));
    await settle(tester);

    expect(pickerRow('Beinpresse'), findsOneWidget);
    expect(pickerRow('Bankdrücken'), findsNothing);
  });
}
