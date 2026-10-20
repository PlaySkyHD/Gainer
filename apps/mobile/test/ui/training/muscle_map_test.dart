import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/exercise_catalog_model.dart';
import 'package:gainer_mobile/domain/models/training/muscles.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/ui/features/training/active_workout_controller.dart';
import 'package:gainer_mobile/ui/features/training/body_map.dart';
import 'package:gainer_mobile/ui/features/training/exercise_editor_screen.dart';
import 'package:gainer_mobile/ui/features/training/muscle_map_screen.dart';
import 'package:gainer_mobile/ui/features/training/plan_editor_screen.dart';
import 'package:gainer_mobile/ui/features/training/training_statistics_section.dart';

import 'muscle_map_test_support.dart';
import 'training_plans_test_support.dart';
import 'training_test_support.dart';

void main() {
  late TrainingHarness harness;
  late MuscleScenario scenario;

  setUp(() async {
    harness = await TrainingHarness.create(now: DateTime.utc(2026, 10, 20, 9));
    scenario = await seedMuscleScenario(harness);
  });

  tearDown(() => harness.dispose());

  Future<void> pumpScreen(WidgetTester tester, {String? planId}) async {
    usePhoneSize(tester);
    await tester.pumpWidget(
      trainingTestApp(
        home: MuscleMapScreen(
          repository: harness.repository,
          initialPlanId: planId,
        ),
      ),
    );
    await settle(tester);
  }

  String valueOf(WidgetTester tester, Muscle muscle) {
    final row = find.byKey(ValueKey('muscle-row-${muscle.name}'));
    final texts = tester.widgetList<Text>(
      find.descendant(of: row, matching: find.byType(Text)),
    );
    return texts.last.data!;
  }

  Future<void> showRow(WidgetTester tester, Muscle muscle) =>
      scrollIntoView(tester, find.byKey(ValueKey('muscle-row-${muscle.name}')));

  testWidgets('Statistik öffnet die Muskelübersicht', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(
      trainingTestApp(
        home: CupertinoPageScaffold(
          child: SingleChildScrollView(
            child: TrainingStatisticsSection(repository: harness.repository),
          ),
        ),
      ),
    );
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('statistics-muscles')));
    await settle(tester);

    expect(find.byType(MuscleMapScreen), findsOneWidget);
    expect(find.byType(BodyMap), findsOneWidget);
  });

  testWidgets('alle Pläne summieren, Hilfsmuskeln zählen halb', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Alle Pläne'), findsOneWidget);
    await showRow(tester, Muscle.chest);
    // Push: Bankdrücken 4 Sätze (Brust, Hilfs Trizeps), Trizepsdrücken 3.
    expect(valueOf(tester, Muscle.chest), '4 Sätze');
    expect(valueOf(tester, Muscle.triceps), '5 Sätze');
    // Pull: Klimmzüge 3 Sätze (Latissimus, Hilfs Bizeps).
    expect(valueOf(tester, Muscle.lats), '3 Sätze');
    expect(valueOf(tester, Muscle.biceps), '1,5 Sätze');
    await showRow(tester, Muscle.quads);
    expect(valueOf(tester, Muscle.quads), 'Nicht trainiert');
  });

  testWidgets('Übungen ohne Muskeln lassen sich direkt nachtragen', (
    tester,
  ) async {
    await pumpScreen(tester);
    final row = find.byKey(ValueKey('missing-muscles-${scenario.curlId}'));
    await scrollIntoView(tester, row);
    expect(find.text('Ohne Muskeln'), findsOneWidget);

    await tester.tap(row);
    await settle(tester);
    expect(find.byType(ExerciseEditorScreen), findsOneWidget);
    await scrollIntoView(
      tester,
      find.byKey(const ValueKey('exercise-primary-muscles')),
    );
    await tester.tap(find.byKey(const ValueKey('exercise-primary-muscles')));
    await settle(tester);
    await scrollIntoView(
      tester,
      find.byKey(const ValueKey('muscle-option-biceps')),
    );
    await tester.tap(find.byKey(const ValueKey('muscle-option-biceps')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('muscle-picker-done')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('exercise-save')));
    await settle(tester);

    expect(find.byType(MuscleMapScreen), findsOneWidget);
    expect(find.text('Ohne Muskeln'), findsNothing);
    await showRow(tester, Muscle.biceps);
    // Curls 3 Sätze als Hauptmuskel plus 1,5 aus Klimmzügen.
    expect(valueOf(tester, Muscle.biceps), '4,5 Sätze');
  });

  testWidgets('ein Plan zeigt nur seine Sätze', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byKey(const ValueKey('muscle-map-plan')));
    await settle(tester);
    await tester.tap(find.text('Pull').last);
    await settle(tester);

    expect(find.text('Pull'), findsOneWidget);
    await showRow(tester, Muscle.chest);
    expect(valueOf(tester, Muscle.lats), '3 Sätze');
    expect(valueOf(tester, Muscle.chest), 'Nicht trainiert');
  });

  testWidgets('Plan-ID aus dem Aufruf ist vorgewählt', (tester) async {
    await pumpScreen(tester, planId: scenario.pull.planId);

    expect(find.text('Pull'), findsOneWidget);
    expect(find.text('Alle Pläne'), findsNothing);
  });

  testWidgets('Trainiert zählt erfasste Arbeitssätze im Zeitraum', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Trainiert'));
    await settle(tester);
    await showRow(tester, Muscle.quads);
    // Zwei Trainings in 7 Tagen mit je 3 Arbeitssätzen, Aufwärmen zählt nicht.
    expect(valueOf(tester, Muscle.quads), '6 Sätze');

    await scrollIntoView(tester, find.text('Ø 28 Tage'));
    await tester.tap(find.text('Ø 28 Tage'));
    await settle(tester);
    await showRow(tester, Muscle.quads);
    // Dazu ein Training vor 20 Tagen: 9 Sätze / 4 Wochen.
    expect(valueOf(tester, Muscle.quads), '2,3 Sätze');
  });

  testWidgets('Tipp auf einen Muskel listet die Übungen', (tester) async {
    await pumpScreen(tester);
    await showRow(tester, Muscle.triceps);

    await tester.tap(find.byKey(const ValueKey('muscle-row-triceps')));
    await settle(tester);

    expect(find.text('Trizepsdrücken'), findsOneWidget);
    expect(find.text('Hauptmuskel'), findsOneWidget);
    expect(find.text('Hilfsmuskel'), findsOneWidget);
    expect(find.text('2 Sätze'), findsOneWidget);
  });

  testWidgets('Tipp auf die Karte öffnet den Muskel', (tester) async {
    await pumpScreen(tester);
    final map = find.byType(BodyMap);
    final box = tester.getRect(map);
    // Linke Brust der Vorderansicht bei (86, 102) im 408 × 430-Raster.
    await tester.tapAt(
      box.topLeft + Offset(86 * box.width / 408, 102 * box.height / 430),
    );
    await settle(tester);

    expect(find.text('Brust'), findsWidgets);
    expect(find.text('Bankdrücken'), findsOneWidget);
  });

  testWidgets('Textgröße 2 läuft nicht über', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(
      trainingTestApp(
        textScale: 2,
        home: MuscleMapScreen(repository: harness.repository),
      ),
    );
    await settle(tester);
    await showRow(tester, Muscle.calves);

    expect(tester.takeException(), isNull);
  });

  testWidgets('Plan-Editor zeigt die Karte des aktuellen Stands', (
    tester,
  ) async {
    usePhoneSize(tester);
    final active = ActiveWorkoutController(harness.repository);
    addTearDown(active.dispose);
    await tester.pumpWidget(
      trainingTestApp(
        home: PlanEditorScreen(
          repository: harness.repository,
          activeWorkout: active,
          planId: scenario.push.planId,
        ),
      ),
    );
    await settle(tester);

    await scrollIntoView(tester, find.byKey(const ValueKey('plan-muscle-map')));
    expect(find.byKey(const ValueKey('plan-muscle-map')), findsOneWidget);
    expect(
      find.text(
        'Arbeitssätze je Muskel. Hilfsmuskeln zählen einen halben Satz.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Übungseditor speichert Haupt- und Hilfsmuskeln', (tester) async {
    final exercise = await tester.runAsync(
      () => seedExercise(harness, name: 'Schrägbankdrücken'),
    );
    await openEditorFor(tester, harness, exercise!);

    await scrollIntoView(
      tester,
      find.byKey(const ValueKey('exercise-primary-muscles')),
    );
    await tester.tap(find.byKey(const ValueKey('exercise-primary-muscles')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('muscle-option-chest')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('muscle-picker-done')));
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('exercise-secondary-muscles')));
    await settle(tester);
    // Brust ist schon Hauptmuskel und hier gesperrt.
    expect(find.text('Hauptmuskel'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('muscle-option-chest')));
    await tester.pump();
    await scrollIntoView(
      tester,
      find.byKey(const ValueKey('muscle-option-triceps')),
    );
    await tester.tap(find.byKey(const ValueKey('muscle-option-triceps')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('muscle-picker-done')));
    await settle(tester);

    expect(find.text('Brust'), findsOneWidget);
    expect(find.text('Trizeps'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('exercise-save')));
    await settle(tester);

    final stored = await tester.runAsync(
      () => harness.repository.readExercises().then(
        (all) => all.singleWhere((item) => item.id == exercise.id),
      ),
    );
    expect(stored!.primaryMuscles, [Muscle.chest]);
    expect(stored.secondaryMuscles, [Muscle.triceps]);
  });

  testWidgets('Tipp auf die Karte im Editor: Haupt, Hilfs, keiner', (
    tester,
  ) async {
    final exercise = await tester.runAsync(
      () => seedExercise(harness, name: 'Schrägbankdrücken'),
    );
    await openEditorFor(tester, harness, exercise!);
    final map = find.byKey(const ValueKey('exercise-muscle-map'));
    await scrollIntoView(tester, map);

    Future<void> tapChest() async {
      final box = tester.getRect(map);
      await tester.tapAt(
        box.topLeft + Offset(86 * box.width / 408, 102 * box.height / 430),
      );
      await tester.pump();
    }

    String value(String key) {
      final texts = tester.widgetList<Text>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(Text),
        ),
      );
      return texts.last.data!;
    }

    await tapChest();
    expect(value('exercise-primary-muscles'), 'Brust');
    await tapChest();
    expect(value('exercise-primary-muscles'), 'Keine');
    expect(value('exercise-secondary-muscles'), 'Brust');
    await tapChest();
    expect(value('exercise-secondary-muscles'), 'Keine');
  });

  testWidgets('Basisübung zeigt ihre Muskeln nur an', (tester) async {
    const base = CatalogExercise(
      id: 'base-row',
      name: 'Rudern',
      exerciseType: ExerciseKind.strength,
      primaryMuscles: [Muscle.traps, Muscle.lats],
      secondaryMuscles: [Muscle.biceps],
      isBase: true,
    );
    await openEditorFor(tester, harness, base);
    await scrollIntoView(
      tester,
      find.byKey(const ValueKey('exercise-primary-muscles')),
    );

    expect(find.text('Oberer Rücken, Latissimus'), findsOneWidget);
    expect(find.text('Bizeps'), findsOneWidget);
    expect(find.byKey(const ValueKey('exercise-save')), findsNothing);
  });
}
