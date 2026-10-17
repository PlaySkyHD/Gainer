import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';
import 'package:gainer_mobile/ui/features/training/active_workout_controller.dart';
import 'package:gainer_mobile/ui/features/training/training_plans_section.dart';
import 'package:gainer_mobile/ui/features/training/training_plans_view_model.dart';

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

  Future<void> pumpSection(WidgetTester tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(
      trainingTestApp(
        home: GainerScaffold(
          title: 'Training',
          children: [
            TrainingPlansSection(
              repository: harness.repository,
              activeWorkout: activeWorkout,
            ),
          ],
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('Ohne Pläne erscheint der leere Zustand ohne Vorschlag', (
    tester,
  ) async {
    await pumpSection(tester);

    expect(find.textContaining('Noch keine Pläne'), findsOneWidget);
    expect(find.text('Nächstes Training'), findsNothing);
  });

  testWidgets(
    'Rotation schlägt nach dem letzten Training den nächsten Plan vor',
    (tester) async {
      await tester.runAsync(() async {
        final exercise = await seedExercise(harness, name: 'Bankdrücken');
        final push = await seedPlan(
          harness,
          name: 'Push',
          entries: [planEntry(harness, exerciseId: exercise.id)],
        );
        final pull = await seedPlan(
          harness,
          name: 'Pull',
          entries: [planEntry(harness, exerciseId: exercise.id)],
        );
        await seedPlan(harness, name: 'Beine');
        await harness.repository.saveRotation([
          push.planId,
          pull.planId,
          (await harness.repository.readPlans())[2].planId,
        ]);
        await seedFinishedFromPlan(
          harness,
          push,
          DateTime.utc(2026, 10, 14, 18),
        );
      });
      await pumpSection(tester);

      expect(find.text('Nächstes Training'), findsOneWidget);
      expect(find.text('Pull'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('training-plans-next-start')));
      await settle(tester);

      final active = await tester.runAsync(
        harness.repository.readActiveWorkout,
      );
      expect(active?.title, 'Pull');
    },
  );

  testWidgets('Leere Rotation schlägt keinen Plan vor', (tester) async {
    await tester.runAsync(() async {
      final exercise = await seedExercise(harness, name: 'Bankdrücken');
      await seedPlan(
        harness,
        name: 'Push',
        entries: [planEntry(harness, exerciseId: exercise.id)],
      );
    });
    await pumpSection(tester);

    expect(find.text('Nächstes Training'), findsNothing);
    expect(
      find.byKey(const ValueKey('training-plans-next-start')),
      findsNothing,
    );
  });

  testWidgets('Archivieren braucht eine Bestätigung', (tester) async {
    await tester.runAsync(() async {
      await seedPlan(harness, name: 'Push');
      await seedPlan(harness, name: 'Pull');
    });
    await pumpSection(tester);

    await tester.tap(find.text('Bearbeiten'));
    await settle(tester);
    await tester.tap(find.byIcon(CupertinoIcons.archivebox).first);
    await settle(tester);

    expect(find.text('Plan archivieren?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await settle(tester);
    var plans = await tester.runAsync(harness.repository.readPlans);
    expect(plans, hasLength(2));

    await tester.tap(find.byIcon(CupertinoIcons.archivebox).first);
    await settle(tester);
    await tester.tap(find.text('Archivieren'));
    await settle(tester);

    plans = await tester.runAsync(harness.repository.readPlans);
    expect(plans!.map((plan) => plan.name), ['Pull']);
  });

  testWidgets('Umordnen per Ziehgriff speichert die Reihenfolge', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seedSyncedPlan(harness, name: 'Push', sortOrder: 0);
      await seedSyncedPlan(harness, name: 'Pull', sortOrder: 1);
      await seedSyncedPlan(harness, name: 'Beine', sortOrder: 2);
    });
    await pumpSection(tester);

    await tester.tap(find.text('Bearbeiten'));
    await settle(tester);
    await tester.drag(
      find.byIcon(CupertinoIcons.line_horizontal_3).first,
      const Offset(0, 300),
    );
    await settle(tester);

    final plans = await tester.runAsync(harness.repository.readPlans);
    expect(plans!.map((plan) => plan.name), ['Pull', 'Beine', 'Push']);
  });

  group('TrainingPlansViewModel', () {
    testWidgets('Rotation speichern aktualisiert den Vorschlag', (
      tester,
    ) async {
      final viewModel = TrainingPlansViewModel(repository: harness.repository);
      addTearDown(viewModel.dispose);
      await tester.runAsync(() async {
        final push = await seedPlan(harness, name: 'Push');
        final pull = await seedPlan(harness, name: 'Pull');
        await viewModel.load();
        expect(viewModel.nextPlanId, isNull);

        final error = await viewModel.saveRotation([pull.planId, push.planId]);
        expect(error, isNull);
        expect(viewModel.nextPlanId, pull.planId);
      });
    });

    testWidgets(
      'Fehler beim Umordnen liefert eine Meldung statt eines Absturzes',
      (tester) async {
        final viewModel = TrainingPlansViewModel(
          repository: harness.repository,
        );
        addTearDown(viewModel.dispose);
        await tester.runAsync(() async {
          await seedPlan(harness, name: 'Push');
          await viewModel.load();
          final error = await viewModel.reorder(const ['unbekannt']);
          expect(error, isNotNull);
          expect(viewModel.plans.map((plan) => plan.name), ['Push']);
        });
      },
    );
  });
}
