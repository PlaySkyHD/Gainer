import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';
import 'package:gainer_mobile/ui/features/training/active_workout_controller.dart';
import 'package:gainer_mobile/ui/features/training/exercise_editor_screen.dart';
import 'package:gainer_mobile/ui/features/training/exercise_statistics_screen.dart';
import 'package:gainer_mobile/ui/features/training/workout_block_card.dart';

import 'training_plans_test_support.dart';
import 'training_test_support.dart';
import 'workout_flow_test_support.dart';

WorkoutBlock _block(
  String id,
  String name, {
  List<LoggedSet> sets = const [LoggedSet(setId: 's')],
}) => WorkoutBlock(
  workoutExerciseId: id,
  sourceExerciseId: 'src-$id',
  exerciseNameSnapshot: name,
  exerciseTypeSnapshot: ExerciseKind.strength,
  sets: sets,
);

/// Aktion im geöffneten Bestätigungsdialog, nicht im darunter liegenden Sheet.
Finder _dialogAction(String label) => find.descendant(
  of: find.byType(GainerStackedDialog<bool>),
  matching: find.text(label),
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

  Future<void> openBlockMenu(WidgetTester tester, String exerciseName) async {
    final card = find.ancestor(
      of: find.text(exerciseName),
      matching: find.byType(WorkoutBlockCard),
    );
    await tester.tap(
      find.descendant(of: card.first, matching: labelled('Übungsmenü')),
    );
    await settle(tester);
  }

  testWidgets('Übungsmenü zeigt Aktionsreihe und Gruppen', (tester) async {
    final id = await startActiveWorkout(
      tester,
      harness,
      active,
      blocks: [_block('bench', 'Bankdrücken')],
    );
    await pumpWorkoutFromHost(tester, harness, active, id);

    await openBlockMenu(tester, 'Bankdrücken');

    for (final label in [
      'Verschieben',
      'Ersetzen',
      'Löschen',
      'Notiz bearbeiten',
      'Verlauf',
      'Graphen',
      'Persönliche Rekorde',
      'Gewichtseinheit: kg',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('Graphen im Menü öffnet die Statistik der Übung', (tester) async {
    final id = await startActiveWorkout(
      tester,
      harness,
      active,
      blocks: [_block('bench', 'Bankdrücken')],
    );
    await pumpWorkoutFromHost(tester, harness, active, id);

    await openBlockMenu(tester, 'Bankdrücken');
    await tester.tap(find.text('Graphen'));
    await settle(tester);

    expect(find.byType(ExerciseStatisticsScreen), findsOneWidget);
  });

  testWidgets('Rekord-Icon in der Fußzeile öffnet die Rekorde', (tester) async {
    final id = await startActiveWorkout(
      tester,
      harness,
      active,
      blocks: [_block('bench', 'Bankdrücken')],
    );
    await pumpWorkoutFromHost(tester, harness, active, id);

    await tester.tap(labelled('Rekorde'));
    await settle(tester);

    final screen = tester.widget<ExerciseStatisticsScreen>(
      find.byType(ExerciseStatisticsScreen),
    );
    expect(screen.initialTab, ExerciseStatisticsTab.records);
  });

  testWidgets('Löschen im Blockmenü entfernt die Übung erst nach Bestätigung', (
    tester,
  ) async {
    final id = await startActiveWorkout(
      tester,
      harness,
      active,
      blocks: [_block('bench', 'Bankdrücken'), _block('row', 'Rudern')],
    );
    await pumpWorkoutFromHost(tester, harness, active, id);

    await openBlockMenu(tester, 'Bankdrücken');
    await tester.tap(find.text('Löschen'));
    await settle(tester);
    await tester.tap(find.text('Abbrechen'));
    await settle(tester);
    expect((await storedWorkout(tester, harness, id))!.exercises, hasLength(2));

    await openBlockMenu(tester, 'Bankdrücken');
    await tester.tap(find.text('Löschen'));
    await settle(tester);
    await tester.tap(find.text('Löschen'));
    await settle(tester);

    final stored = (await storedWorkout(tester, harness, id))!;
    expect(stored.exercises.map((block) => block.exerciseNameSnapshot), [
      'Rudern',
    ]);
  });

  testWidgets('Ersetzen tauscht die Übung und behält die Satzwerte', (
    tester,
  ) async {
    await tester.runAsync(
      () => seedExercise(harness, name: 'Kurzhantel-Bankdrücken'),
    );
    final id = await startActiveWorkout(
      tester,
      harness,
      active,
      blocks: [
        _block(
          'bench',
          'Langhantel-Bankdrücken',
          sets: const [LoggedSet(setId: 's1', weightKg: 80, repetitions: 8)],
        ),
      ],
    );
    await pumpWorkoutFromHost(tester, harness, active, id);

    await openBlockMenu(tester, 'Langhantel-Bankdrücken');
    await tester.tap(find.text('Ersetzen'));
    await settle(tester);
    expect(find.text('Übung ersetzen'), findsOneWidget);
    await searchPicker(tester, 'Kurzhantel');
    await tester.tap(pickerRow('Kurzhantel-Bankdrücken'));
    await settle(tester);

    expect(find.text('Kurzhantel-Bankdrücken'), findsOneWidget);
    final block = (await storedWorkout(tester, harness, id))!.exercises.single;
    expect(block.exerciseNameSnapshot, 'Kurzhantel-Bankdrücken');
    expect(block.sets.single.weightKg, 80);
    expect(block.sets.single.repetitions, 8);
  });

  testWidgets('„+ Übung hinzufügen“ hängt eine Einzelübung an', (tester) async {
    await tester.runAsync(() => seedExercise(harness, name: 'Kniebeuge'));
    final id = await startActiveWorkout(
      tester,
      harness,
      active,
      blocks: [_block('bench', 'Bankdrücken')],
    );
    await pumpWorkoutFromHost(tester, harness, active, id);

    await tester.tap(find.text('Übung hinzufügen'));
    await settle(tester);
    await searchPicker(tester, 'Kniebeuge');
    await tester.tap(pickerRow('Kniebeuge'));
    await settle(tester);

    final stored = (await storedWorkout(tester, harness, id))!;
    final added = stored.exercises.last;
    expect(added.exerciseNameSnapshot, 'Kniebeuge');
    expect(added.supersetId, isNull);
    expect(added.sets, hasLength(1));
    expect(added.sets.single.setType, SetType.normal);
    expect(added.sets.single.weightKg, isNull);
  });

  testWidgets('Archivierte Übung wird im Picker nicht angeboten', (
    tester,
  ) async {
    await tester.runAsync(
      () => seedExercise(harness, name: 'Altübung', archived: true),
    );
    await tester.runAsync(() => seedExercise(harness, name: 'Kniebeuge'));
    final id = await startActiveWorkout(tester, harness, active);
    await pumpWorkoutFromHost(tester, harness, active, id);

    await tester.tap(find.text('Übung hinzufügen'));
    await settle(tester);
    await searchPicker(tester, 'Alt');

    expect(pickerRow('Altübung'), findsNothing);
  });

  testWidgets('Superset-Auswahl hängt zwei benachbarte Blöcke mit A und B an', (
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
    final id = await startActiveWorkout(
      tester,
      harness,
      active,
      blocks: [_block('bench', 'Bankdrücken')],
    );
    await pumpWorkoutFromHost(tester, harness, active, id);

    await tester.tap(find.text('Übung hinzufügen'));
    await settle(tester);
    await tester.tap(find.text('Supersatz'));
    await settle(tester);
    await searchPicker(tester, 'curl');
    await tester.tap(pickerRow('Bizeps Curl'));
    await settle(tester);
    await searchPicker(tester, 'trizeps');
    await tester.tap(pickerRow('Trizeps Drücken'));
    await settle(tester);
    await tester.tap(find.text('Als Superset hinzufügen'));
    await settle(tester);

    final blocks = (await storedWorkout(tester, harness, id))!.exercises;
    expect(blocks, hasLength(3));
    expect(blocks[1].exerciseNameSnapshot, 'Bizeps Curl');
    expect(blocks[2].exerciseNameSnapshot, 'Trizeps Drücken');
    expect(blocks[1].supersetId, isNotNull);
    expect(blocks[2].supersetId, blocks[1].supersetId);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('Neuordnen speichert erst mit „Fertig“', (tester) async {
    final id = await startActiveWorkout(
      tester,
      harness,
      active,
      blocks: [
        _block('bench', 'Bankdrücken'),
        _block('row', 'Rudern'),
        _block('squat', 'Kniebeuge'),
      ],
    );
    await pumpWorkoutFromHost(tester, harness, active, id);

    await tester.tap(labelled('Weitere Aktionen'));
    await settle(tester);
    await tester.tap(find.text('Übungen neu anordnen'));
    await settle(tester);
    await tester.drag(
      labelled('Ziehen zum Umordnen').last,
      const Offset(0, -400),
    );
    await settle(tester);

    expect(
      (await storedWorkout(
        tester,
        harness,
        id,
      ))!.exercises.map((block) => block.exerciseNameSnapshot),
      ['Bankdrücken', 'Rudern', 'Kniebeuge'],
    );

    await tester.tap(find.text('Fertig'));
    await settle(tester);

    expect(
      (await storedWorkout(
        tester,
        harness,
        id,
      ))!.exercises.map((block) => block.exerciseNameSnapshot),
      ['Kniebeuge', 'Bankdrücken', 'Rudern'],
    );
  });

  testWidgets('Entfernen im Neuordnen-Sheet braucht Bestätigung', (
    tester,
  ) async {
    final id = await startActiveWorkout(
      tester,
      harness,
      active,
      blocks: [_block('bench', 'Bankdrücken'), _block('row', 'Rudern')],
    );
    await pumpWorkoutFromHost(tester, harness, active, id);

    await tester.tap(labelled('Weitere Aktionen'));
    await settle(tester);
    await tester.tap(find.text('Übungen neu anordnen'));
    await settle(tester);
    await tester.tap(labelled('Entfernen Rudern'));
    await settle(tester);
    await tester.tap(_dialogAction('Abbrechen'));
    await settle(tester);
    expect(find.text('Übung entfernen?'), findsNothing);

    await tester.tap(labelled('Entfernen Rudern'));
    await settle(tester);
    await tester.tap(_dialogAction('Entfernen'));
    await settle(tester);
    await tester.tap(find.text('Fertig'));
    await settle(tester);

    final stored = (await storedWorkout(tester, harness, id))!;
    expect(stored.exercises.map((block) => block.exerciseNameSnapshot), [
      'Bankdrücken',
    ]);
  });

  testWidgets('Übung bearbeiten öffnet den Übungseditor', (tester) async {
    final exercise = await tester.runAsync(
      () => seedExercise(harness, name: 'Schrägbankdrücken'),
    );
    final id = await startActiveWorkout(
      tester,
      harness,
      active,
      blocks: [
        WorkoutBlock(
          workoutExerciseId: 'incline',
          sourceExerciseId: exercise!.id,
          exerciseNameSnapshot: 'Schrägbankdrücken',
          exerciseTypeSnapshot: ExerciseKind.strength,
          sets: const [LoggedSet(setId: 's')],
        ),
      ],
    );
    await pumpWorkoutFromHost(tester, harness, active, id);

    await openBlockMenu(tester, 'Schrägbankdrücken');
    await tester.tap(find.text('Übung bearbeiten'));
    await settle(tester);

    expect(find.byType(ExerciseEditorScreen), findsOneWidget);
    await scrollIntoView(
      tester,
      find.byKey(const ValueKey('exercise-primary-muscles')),
    );
    expect(
      find.byKey(const ValueKey('exercise-primary-muscles')),
      findsOneWidget,
    );
  });

  testWidgets('ohne bekannte Übung fehlt „Übung bearbeiten“', (tester) async {
    final id = await startActiveWorkout(
      tester,
      harness,
      active,
      blocks: [_block('bench', 'Bankdrücken')],
    );
    await pumpWorkoutFromHost(tester, harness, active, id);

    await openBlockMenu(tester, 'Bankdrücken');

    expect(find.text('Übung bearbeiten'), findsNothing);
    expect(find.text('Übung anzeigen'), findsNothing);
  });
}
