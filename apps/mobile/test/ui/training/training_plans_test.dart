import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/training_schedule.dart';
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

  testWidgets('Ohne Pläne erscheint der leere Zustand ohne Heute-Karte', (
    tester,
  ) async {
    await pumpSection(tester);

    expect(find.textContaining('Noch keine Pläne'), findsOneWidget);
    expect(find.byKey(const ValueKey('training-today-card')), findsNothing);
    expect(find.text('Rhythmus einrichten'), findsNothing);
  });

  testWidgets('Pläne aus dem Rhythmus sind markiert', (tester) async {
    await tester.runAsync(() async {
      final push = await seedPlan(harness, name: 'Push');
      await seedPlan(harness, name: 'Pull');
      await harness.repository.schedule.saveRhythm(
        mode: TrainingScheduleMode.cycle,
        slots: [
          TrainingScheduleSlot(planId: push.planId),
          const TrainingScheduleSlot.rest(),
        ],
      );
    });
    await pumpSection(tester);

    expect(find.text('Heute: Push'), findsOneWidget);
    expect(find.text('0 Übungen · Im Rhythmus'), findsOneWidget);
    expect(find.text('0 Übungen'), findsOneWidget);
    expect(find.text('Rhythmus'), findsOneWidget);
    expect(find.text('Rotation'), findsNothing);
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
    testWidgets('Laden liefert die Rhythmus-Vorschau für heute', (
      tester,
    ) async {
      final viewModel = TrainingPlansViewModel(repository: harness.repository);
      addTearDown(viewModel.dispose);
      await tester.runAsync(() async {
        final push = await seedPlan(harness, name: 'Push');
        final pull = await seedPlan(harness, name: 'Pull');
        await viewModel.load();
        expect(viewModel.projection?.schedule, isNull);
        expect(viewModel.scheduledPlanIds, isEmpty);

        await harness.repository.schedule.saveRhythm(
          mode: TrainingScheduleMode.cycle,
          slots: [
            TrainingScheduleSlot(planId: pull.planId),
            TrainingScheduleSlot(planId: push.planId),
          ],
        );
        await viewModel.load();
        final projection = viewModel.projection!;
        expect(
          projection.day(projection.today).effective.single.planId,
          pull.planId,
        );
        expect(viewModel.scheduledPlanIds, {push.planId, pull.planId});
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
