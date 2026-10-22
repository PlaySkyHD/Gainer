import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/training_schedule.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';
import 'package:gainer_mobile/ui/features/training/active_workout_controller.dart';
import 'package:gainer_mobile/ui/features/training/training_plans_section.dart';
import 'package:gainer_mobile/ui/features/training/training_plans_view_model.dart';
import 'package:gainer_mobile/ui/features/training/workout_screen.dart';

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

  testWidgets(
    'Start öffnet das Training, auch wenn der Bereich währenddessen verschwindet',
    (tester) async {
      final gated = _GatedActiveWorkout(harness);
      addTearDown(gated.dispose);
      await tester.runAsync(() async {
        final exercise = await seedExercise(harness, name: 'Bankdrücken');
        final push = await seedPlan(
          harness,
          name: 'Push',
          entries: [planEntry(harness, exerciseId: exercise.id)],
        );
        await harness.repository.schedule.saveRhythm(
          mode: TrainingScheduleMode.cycle,
          slots: [TrainingScheduleSlot(planId: push.planId)],
        );
      });
      usePhoneSize(tester);
      await tester.pumpWidget(
        trainingTestApp(
          home: GainerScaffold(
            title: 'Training',
            children: [
              TrainingPlansSection(
                repository: harness.repository,
                activeWorkout: gated,
              ),
            ],
          ),
        ),
      );
      await settle(tester);

      gated.hold();
      await tester.tap(find.byKey(const ValueKey('training-today-start')));
      await settle(tester);
      // Neuaufbau mitten im Start, etwa durch Sync oder Segmentwechsel.
      await tester.pumpWidget(trainingTestApp(home: const SizedBox.shrink()));
      expect(find.byType(TrainingPlansSection), findsNothing);
      gated.release();
      await settle(tester);

      expect(find.byType(WorkoutScreen), findsOneWidget);
    },
  );

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

  testWidgets('Duplizieren legt eine Kopie an und öffnet sie im Editor', (
    tester,
  ) async {
    final source = await tester.runAsync(() async {
      final pulldown = await seedExercise(harness, name: 'Latzug');
      final row = await seedExercise(harness, name: 'Rudern');
      await seedPlan(harness, name: 'Push');
      return seedPlan(
        harness,
        name: 'Pull',
        entries: [
          planEntry(
            harness,
            exerciseId: pulldown.id,
            warmupSets: 1,
            supersetId: 'ss',
          ),
          planEntry(harness, exerciseId: row.id, supersetId: 'ss'),
        ],
      );
    });
    await pumpSection(tester);

    await tester.longPress(find.text('Pull'));
    await settle(tester);
    await tester.tap(find.text('Duplizieren'));
    await settle(tester);

    expect(
      find.byKey(const ValueKey('plan-name-field')),
      findsOneWidget,
      reason: 'Die Kopie öffnet sich im Planeditor.',
    );
    expect(find.text('Pull Kopie'), findsWidgets);

    final plans = (await tester.runAsync(harness.repository.readPlans))!;
    expect(plans.map((plan) => plan.name), ['Push', 'Pull', 'Pull Kopie']);
    final copy = plans.last;
    expect(copy.planId, isNot(source!.planId));
    expect(
      copy.entries.map((entry) => entry.exerciseId),
      source.entries.map((entry) => entry.exerciseId),
    );
    expect(copy.entries.first.warmupSets, 1);
    expect(
      copy.entries
          .map((entry) => entry.entryId)
          .toSet()
          .intersection(source.entries.map((entry) => entry.entryId).toSet()),
      isEmpty,
    );
    expect(copy.entries.first.supersetId, isNotNull);
    expect(copy.entries.first.supersetId, isNot('ss'));
    expect(copy.entries.last.supersetId, copy.entries.first.supersetId);
  });

  test('Kopie eines Plans mit sehr langem Namen bleibt gültig', () async {
    final source = await seedPlan(harness, name: 'P' * 160);

    final copy = await harness.repository.duplicatePlan(source.planId);

    expect(copy.name, hasLength(160));
    expect(copy.name, endsWith(' Kopie'));
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

/// Hält das Laden des aktiven Trainings an, bis der Test es freigibt.
class _GatedActiveWorkout extends ActiveWorkoutController {
  _GatedActiveWorkout(TrainingHarness harness) : super(harness.repository);

  Completer<void>? _gate;

  void hold() => _gate = Completer<void>();

  void release() => _gate?.complete();

  @override
  Future<void> load() async {
    await _gate?.future;
    await super.load();
  }
}
