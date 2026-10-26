import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/training/training_log_repository.dart';
import 'package:gainer_mobile/domain/models/training/training_plan_model.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/ui/features/training/active_workout_controller.dart';
import 'package:gainer_mobile/ui/features/training/plan_editor_screen.dart';

import 'training_plans_test_support.dart';
import 'training_test_support.dart';
import 'workout_flow_test_support.dart';

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

  testWidgets('Doppeltipp auf Speichern legt den neuen Plan nur einmal an', (
    tester,
  ) async {
    await tester.runAsync(() => seedExercise(harness, name: 'Bankdrücken'));
    await pumpEditor(tester);
    await tester.enterText(
      find.byKey(const ValueKey('plan-name-field')),
      'Push',
    );
    await addExercise(tester, 'Bankdr', 'Bankdrücken');

    await tester.tap(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await settle(tester);

    final plans = await tester.runAsync(harness.repository.readPlans);
    expect(plans!.map((plan) => plan.name), ['Push']);
    expect(find.textContaining('konnte nicht gespeichert'), findsNothing);
    expect(find.text('Gespeichert.'), findsOneWidget);
    final outbox = await tester.runAsync(
      () => harness.repository.store.readOutbox(aggregateType: 'training-plan'),
    );
    expect(outbox, hasLength(1));
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

  testWidgets('Speichern beim Verlassen sichert Änderungen nach dem '
      'laufenden Speichern', (tester) async {
    final slow = _SlowPlans(harness.repository);
    await tester.pumpWidget(
      trainingTestApp(
        home: Builder(
          builder: (context) => Center(
            child: CupertinoButton(
              onPressed: () => Navigator.of(context).push<void>(
                CupertinoPageRoute<void>(
                  builder: (_) => PlanEditorScreen(
                    repository: slow,
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
    final name = find.byKey(const ValueKey('plan-name-field'));
    await tester.enterText(name, 'Push');
    await tester.pump();

    // Das Speichern hängt, während der Entwurf sich ändert und der Nutzer
    // zurückgeht.
    await tester.tap(find.text('Speichern'));
    await tester.pump();
    expect(slow.createCalls, 1);
    await tester.enterText(name, 'Push 2');
    await tester.pump();
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Ungespeicherte Änderungen'), findsOneWidget);
    await tester.tap(find.text('Speichern').last);
    await tester.pump();
    slow.gate.complete();
    await settle(tester);

    final plans = await tester.runAsync(harness.repository.readPlans);
    expect(plans!.map((plan) => plan.name), ['Push 2']);
    expect(find.text('Öffnen'), findsOneWidget);
  });

  Future<TrainingPlanModel> seedThreeEntryPlan(WidgetTester tester) async {
    final plan = await tester.runAsync(() async {
      final pulldown = await seedExercise(harness, name: 'Latzug');
      final tbar = await seedExercise(harness, name: 'TBar');
      final highRow = await seedExercise(harness, name: 'HighRow');
      await seedExercise(harness, name: 'Klimmzug');
      return seedPlan(
        harness,
        name: 'Pull',
        entries: [
          planEntry(harness, exerciseId: pulldown.id),
          planEntry(harness, exerciseId: tbar.id, supersetId: 'ss'),
          planEntry(harness, exerciseId: highRow.id, supersetId: 'ss'),
        ],
      );
    });
    return plan!;
  }

  Future<void> openEntryMenu(WidgetTester tester, int index) async {
    final button = find.descendant(
      of: find.byKey(ValueKey('plan-entry-$index')),
      matching: labelled('Übungsmenü'),
    );
    await tester.ensureVisible(button);
    await settle(tester);
    await tester.tap(button);
    await settle(tester);
  }

  Future<List<String>> storedNames(WidgetTester tester, String planId) async {
    final names = await tester.runAsync(() async {
      final plan = await harness.repository.readPlan(planId);
      final exercises = {
        for (final exercise in await harness.repository.readExercises())
          exercise.id: exercise.name,
      };
      return [for (final entry in plan!.entries) exercises[entry.exerciseId]!];
    });
    return names!;
  }

  testWidgets('Verschieben ordnet die Einträge nach dem Speichern neu', (
    tester,
  ) async {
    final plan = await seedThreeEntryPlan(tester);
    await pumpEditor(tester, planId: plan.planId);

    await openEntryMenu(tester, 2);
    await tester.tap(find.text('Verschieben'));
    await settle(tester);
    await tester.drag(
      labelled('Ziehen zum Umordnen').last,
      const Offset(0, -400),
    );
    await settle(tester);
    await tester.tap(find.text('Fertig'));
    await settle(tester);

    expect(await storedNames(tester, plan.planId), [
      'Latzug',
      'TBar',
      'HighRow',
    ]);
    await save(tester);

    final stored = await tester.runAsync(
      () => harness.repository.readPlan(plan.planId),
    );
    expect(await storedNames(tester, plan.planId), [
      'HighRow',
      'Latzug',
      'TBar',
    ]);
    expect(
      stored!.entries.map((entry) => entry.supersetId),
      everyElement(isNull),
    );
  });

  testWidgets('Ersetzen tauscht die Übung und behält die Sätze', (
    tester,
  ) async {
    final plan = await seedThreeEntryPlan(tester);
    await pumpEditor(tester, planId: plan.planId);

    await openEntryMenu(tester, 0);
    await tester.tap(find.text('Ersetzen'));
    await settle(tester);
    expect(find.text('Übung ersetzen'), findsOneWidget);
    await searchPicker(tester, 'klimm');
    await tester.tap(pickerRow('Klimmzug'));
    await settle(tester);

    expect(find.text('Klimmzug'), findsOneWidget);
    expect(find.text('Latzug'), findsNothing);
    await save(tester);

    final stored = await tester.runAsync(
      () => harness.repository.readPlan(plan.planId),
    );
    expect(await storedNames(tester, plan.planId), [
      'Klimmzug',
      'TBar',
      'HighRow',
    ]);
    expect(stored!.entries.first.entryId, plan.entries.first.entryId);
    expect(stored.entries.first.workingSets, 3);
  });

  testWidgets('Löschen entfernt den Eintrag und löst das Superset', (
    tester,
  ) async {
    final plan = await seedThreeEntryPlan(tester);
    await pumpEditor(tester, planId: plan.planId);

    await openEntryMenu(tester, 1);
    await tester.tap(find.text('Löschen'));
    await settle(tester);
    expect(find.text('TBar'), findsNothing);
    await save(tester);

    final stored = await tester.runAsync(
      () => harness.repository.readPlan(plan.planId),
    );
    expect(await storedNames(tester, plan.planId), ['Latzug', 'HighRow']);
    expect(stored!.entries.last.supersetId, isNull);
  });

  testWidgets('Verschieben fehlt bei nur einem Eintrag', (tester) async {
    final plan = await tester.runAsync(() async {
      final exercise = await seedExercise(harness, name: 'Latzug');
      return seedPlan(
        harness,
        name: 'Pull',
        entries: [planEntry(harness, exerciseId: exercise.id)],
      );
    });
    await pumpEditor(tester, planId: plan!.planId);

    await openEntryMenu(tester, 0);

    expect(find.text('Verschieben'), findsNothing);
    expect(find.text('Ersetzen'), findsOneWidget);
  });
}

/// Hält das Anlegen eines Plans an, damit der Test Änderungen währenddessen
/// machen kann.
class _SlowPlans extends TrainingLogRepository {
  _SlowPlans(TrainingLogRepository base)
    : super(store: base.store, catalog: base.catalog);

  final gate = Completer<void>();
  int createCalls = 0;

  @override
  Future<TrainingPlanModel> createPlan(TrainingPlanModel draft) async {
    createCalls++;
    await gate.future;
    return super.createPlan(draft);
  }
}
