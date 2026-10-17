import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/ui/features/training/active_workout_controller.dart';
import 'package:gainer_mobile/ui/features/training/plan_editor_screen.dart';

import 'training_plans_test_support.dart';
import 'training_test_support.dart';

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

  Future<void> pumpEditor(WidgetTester tester, {String? planId}) async {
    usePhoneSize(tester);
    await tester.pumpWidget(
      trainingTestApp(
        home: PlanEditorScreen(
          repository: harness.repository,
          activeWorkout: activeWorkout,
          planId: planId,
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> addExercise(
    WidgetTester tester,
    String query,
    String name,
  ) async {
    await tester.tap(find.text('+ Übung hinzufügen'));
    await settle(tester);
    await tester.enterText(find.byType(CupertinoSearchTextField), query);
    await settle(tester);
    await tester.tap(pickerRow(name));
    await settle(tester);
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('Speichern'));
    await settle(tester);
  }

  testWidgets('Plan ohne Namen wird mit Feldfehler abgelehnt', (tester) async {
    await pumpEditor(tester);

    await save(tester);

    expect(
      find.text('Der Name muss zwischen 1 und 160 Zeichen lang sein.'),
      findsOneWidget,
    );
    final plans = await tester.runAsync(harness.repository.readPlans);
    expect(plans, isEmpty);
  });

  testWidgets('Neuer Plan entsteht mit stabiler ID am Ende der Liste', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seedPlan(harness, name: 'Pull');
      await seedExercise(harness, name: 'Bankdrücken');
    });
    await pumpEditor(tester);
    await tester.enterText(
      find.byKey(const ValueKey('plan-name-field')),
      'Push',
    );
    await addExercise(tester, 'Bankdr', 'Bankdrücken');

    await save(tester);

    final plans = await tester.runAsync(harness.repository.readPlans);
    expect(plans!.map((plan) => plan.name), ['Pull', 'Push']);
    final push = plans.last;
    expect(push.planId, isNotEmpty);
    final stored = await tester.runAsync(
      () => harness.repository.readPlan(push.planId),
    );
    expect(stored?.name, 'Push');
    expect(find.text('Gespeichert.'), findsOneWidget);
  });

  testWidgets('Neuer Eintrag hat 0 Aufwärm- und 3 Arbeitssätze', (
    tester,
  ) async {
    await tester.runAsync(() => seedExercise(harness, name: 'Seitheben'));
    await pumpEditor(tester);
    await tester.enterText(
      find.byKey(const ValueKey('plan-name-field')),
      'Schultern',
    );
    await addExercise(tester, 'Seitheb', 'Seitheben');

    expect(find.text('3 Sätze'), findsOneWidget);
    expect(find.textContaining('Aufwärmsätze'), findsNothing);

    await save(tester);
    final plans = await tester.runAsync(harness.repository.readPlans);
    final entry = plans!.single.entries.single;
    expect(entry.warmupSets, 0);
    expect(entry.workingSets, 3);
  });

  testWidgets('Eintrag ohne Sätze wird am Eintrag abgelehnt', (tester) async {
    await tester.runAsync(() => seedExercise(harness, name: 'Seitheben'));
    await pumpEditor(tester);
    await tester.enterText(
      find.byKey(const ValueKey('plan-name-field')),
      'Schultern',
    );
    await addExercise(tester, 'Seitheb', 'Seitheben');

    await tester.tap(find.byKey(const ValueKey('plan-entry-0')));
    await settle(tester);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byIcon(CupertinoIcons.minus_circle).last);
      await settle(tester);
    }
    await tester.tap(find.text('Fertig'));
    await settle(tester);
    await save(tester);

    expect(
      find.text('Ein Eintrag braucht mindestens einen Satz.'),
      findsOneWidget,
    );
    final plans = await tester.runAsync(harness.repository.readPlans);
    expect(plans, isEmpty);
  });

  testWidgets('Summe aus Aufwärm- und Arbeitssätzen über 50 wird abgelehnt', (
    tester,
  ) async {
    final plan = await tester.runAsync(() async {
      final exercise = await seedExercise(harness, name: 'Kreuzheben');
      return seedPlan(
        harness,
        name: 'Rücken',
        entries: [
          planEntry(
            harness,
            exerciseId: exercise.id,
            warmupSets: 20,
            workingSets: 30,
          ),
        ],
      );
    });
    await pumpEditor(tester, planId: plan!.planId);

    await tester.tap(find.byKey(const ValueKey('plan-entry-0')));
    await settle(tester);
    await tester.tap(find.byIcon(CupertinoIcons.plus_circle).last);
    await settle(tester);

    expect(
      find.text('Ein Eintrag darf höchstens 50 Sätze haben.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Fertig'));
    await settle(tester);
    await save(tester);

    expect(
      find.text('Ein Eintrag darf höchstens 50 Sätze haben.'),
      findsOneWidget,
    );
    final stored = await tester.runAsync(
      () => harness.repository.readPlan(plan.planId),
    );
    expect(stored!.entries.single.workingSets, 30);
  });

  testWidgets('Training beginnen übernimmt W, W, 1, 2, 3', (tester) async {
    final plan = await tester.runAsync(() async {
      final exercise = await seedExercise(harness, name: 'Bankdrücken');
      return seedPlan(
        harness,
        name: 'Push',
        entries: [
          planEntry(
            harness,
            exerciseId: exercise.id,
            warmupSets: 2,
            workingSets: 3,
          ),
        ],
      );
    });
    await pumpEditor(tester, planId: plan!.planId);

    await tester.tap(find.byKey(const ValueKey('plan-editor-start')));
    await settle(tester);

    final active = await tester.runAsync(harness.repository.readActiveWorkout);
    expect(active?.title, 'Push');
    expect(active?.sourcePlanId, plan.planId);
    expect(
      [for (final set in active!.exercises.single.sets) set.setType],
      [
        SetType.warmup,
        SetType.warmup,
        SetType.normal,
        SetType.normal,
        SetType.normal,
      ],
    );
  });

  testWidgets('Plan starten bei aktivem Training bietet Fortsetzen an', (
    tester,
  ) async {
    final plan = await tester.runAsync(() async {
      final exercise = await seedExercise(harness, name: 'Bankdrücken');
      await seedActiveWorkout(harness, 'Beine');
      await activeWorkout.load();
      return seedPlan(
        harness,
        name: 'Push',
        entries: [planEntry(harness, exerciseId: exercise.id)],
      );
    });
    await pumpEditor(tester, planId: plan!.planId);

    await tester.tap(find.byKey(const ValueKey('plan-editor-start')));
    await settle(tester);

    expect(find.text('Aktives Training fortsetzen'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await settle(tester);

    final diary = await tester.runAsync(harness.repository.readDiary);
    expect(diary!.map((workout) => workout.title), ['Beine']);
  });

  testWidgets('Verlassen mit ungespeicherten Änderungen fragt nach', (
    tester,
  ) async {
    await tester.pumpWidget(
      trainingTestApp(
        home: Builder(
          builder: (context) => Center(
            child: CupertinoButton(
              onPressed: () => Navigator.of(context).push<void>(
                CupertinoPageRoute<void>(
                  builder: (_) => PlanEditorScreen(
                    repository: harness.repository,
                    activeWorkout: activeWorkout,
                  ),
                ),
              ),
              child: const Text('Öffnen'),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Öffnen'));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('plan-name-field')),
      'Push',
    );
    await settle(tester);

    await tester.pageBack();
    await settle(tester);

    expect(find.text('Ungespeicherte Änderungen'), findsOneWidget);
    await tester.tap(find.text('Verwerfen'));
    await settle(tester);

    expect(find.text('Öffnen'), findsOneWidget);
    final plans = await tester.runAsync(harness.repository.readPlans);
    expect(plans, isEmpty);
  });
}
