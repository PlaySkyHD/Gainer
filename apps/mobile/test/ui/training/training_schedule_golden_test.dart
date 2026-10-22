import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/training_schedule.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';
import 'package:gainer_mobile/ui/features/training/active_workout_controller.dart';
import 'package:gainer_mobile/ui/features/training/training_plans_section.dart';
import 'package:gainer_mobile/ui/features/training/training_schedule_sheet.dart';

import 'training_plans_test_support.dart';
import 'training_test_support.dart';

void main() {
  Future<TrainingHarness> createHarness(WidgetTester tester) async {
    usePhoneSize(tester);
    final harness = await tester.runAsync(TrainingHarness.create);
    if (harness == null) throw StateError('Harness nicht erstellt.');
    addTearDown(() => tester.runAsync(harness.dispose));
    return harness;
  }

  Future<List<String>> seedPlans(
    WidgetTester tester,
    TrainingHarness harness,
    List<String> names,
  ) async {
    final ids = await tester.runAsync(() async {
      return [
        for (final name in names) (await seedPlan(harness, name: name)).planId,
      ];
    });
    return ids!;
  }

  Future<void> openEditor(
    WidgetTester tester,
    TrainingHarness harness, {
    required Brightness brightness,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      trainingTestApp(
        brightness: brightness,
        textScale: textScale,
        home: Builder(
          builder: (context) => Center(
            child: CupertinoButton(
              onPressed: () => showTrainingScheduleSheet(
                context,
                repository: harness.repository,
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
  }

  for (final brightness in [Brightness.light, Brightness.dark]) {
    final name = brightness.name;

    testWidgets('Rhythmus-Editor Zyklus $name', (tester) async {
      final harness = await createHarness(tester);
      final ids = await seedPlans(tester, harness, ['Push', 'Pull', 'Beine']);
      await tester.runAsync(() async {
        await harness.repository.schedule.saveRhythm(
          mode: TrainingScheduleMode.cycle,
          slots: [
            TrainingScheduleSlot(planId: ids[0]),
            TrainingScheduleSlot(planId: ids[1]),
            TrainingScheduleSlot(planId: ids[2]),
            const TrainingScheduleSlot.rest(),
          ],
          todaySlotIndex: 1,
        );
        await harness.repository.archivePlan(ids[2]);
      });
      await openEditor(tester, harness, brightness: brightness);

      await expectLater(
        find.byType(CupertinoApp),
        matchesGoldenFile('goldens/schedule_editor_cycle_$name.png'),
      );
    }, tags: ['golden']);

    testWidgets('Rhythmus-Editor feste Tage $name', (tester) async {
      final harness = await createHarness(tester);
      final ids = await seedPlans(tester, harness, [
        'Push',
        'Pull',
        'Beine',
        'Oberkörper',
      ]);
      await tester.runAsync(
        () => harness.repository.schedule.saveRhythm(
          mode: TrainingScheduleMode.weekly,
          slots: [
            TrainingScheduleSlot(planId: ids[0]),
            TrainingScheduleSlot(planId: ids[1]),
            TrainingScheduleSlot(planId: ids[2]),
            const TrainingScheduleSlot.rest(),
            TrainingScheduleSlot(planId: ids[3]),
            const TrainingScheduleSlot.rest(),
            const TrainingScheduleSlot.rest(),
          ],
        ),
      );
      await openEditor(tester, harness, brightness: brightness);

      await expectLater(
        find.byType(CupertinoApp),
        matchesGoldenFile('goldens/schedule_editor_weekly_$name.png'),
      );
    }, tags: ['golden']);

    testWidgets('Tagesaktionen für heute $name', (tester) async {
      final harness = await createHarness(tester);
      final ids = await seedPlans(tester, harness, ['Push', 'Pull']);
      await tester.runAsync(
        () => harness.repository.schedule.saveRhythm(
          mode: TrainingScheduleMode.cycle,
          slots: [
            TrainingScheduleSlot(planId: ids[0]),
            TrainingScheduleSlot(planId: ids[1]),
            const TrainingScheduleSlot.rest(),
          ],
        ),
      );
      final active = ActiveWorkoutController(harness.repository);
      addTearDown(active.dispose);
      await tester.pumpWidget(
        trainingTestApp(
          brightness: brightness,
          home: GainerScaffold(
            title: 'Training',
            children: [
              TrainingPlansSection(
                repository: harness.repository,
                activeWorkout: active,
              ),
            ],
          ),
        ),
      );
      await settle(tester);
      await tester.longPress(find.byKey(const ValueKey('training-today-card')));
      await settle(tester);

      await expectLater(
        find.byType(CupertinoApp),
        matchesGoldenFile('goldens/schedule_day_actions_$name.png'),
      );

      await tester.tap(find.text('Verschieben…'));
      await settle(tester);
      await expectLater(
        find.byType(CupertinoApp),
        matchesGoldenFile('goldens/schedule_day_actions_move_$name.png'),
      );
    }, tags: ['golden']);
  }

  testWidgets('Rhythmus-Editor Textgröße 2', (tester) async {
    final harness = await createHarness(tester);
    final ids = await seedPlans(tester, harness, ['Push', 'Pull', 'Beine']);
    await tester.runAsync(() => harness.repository.archivePlan(ids[2]));
    await openEditor(
      tester,
      harness,
      brightness: Brightness.light,
      textScale: 2,
    );
    expect(tester.takeException(), isNull);

    await expectLater(
      find.byType(CupertinoApp),
      matchesGoldenFile('goldens/schedule_editor_scale2_light.png'),
    );
  }, tags: ['golden']);

  testWidgets('Heute-Karte Ruhetag Textgröße 2', (tester) async {
    final harness = await createHarness(tester);
    final ids = await seedPlans(tester, harness, ['Oberkörper']);
    await tester.runAsync(
      () => harness.repository.schedule.saveRhythm(
        mode: TrainingScheduleMode.weekly,
        slots: [
          for (var i = 0; i < 7; i++)
            TrainingScheduleSlot(planId: i == 3 ? ids[0] : null),
        ],
      ),
    );
    final active = ActiveWorkoutController(harness.repository);
    addTearDown(active.dispose);
    await tester.pumpWidget(
      trainingTestApp(
        textScale: 2,
        home: GainerScaffold(
          title: 'Training',
          children: [
            TrainingPlansSection(
              repository: harness.repository,
              activeWorkout: active,
            ),
          ],
        ),
      ),
    );
    await settle(tester);
    expect(tester.takeException(), isNull);

    await expectLater(
      find.byType(CupertinoPageScaffold),
      matchesGoldenFile('goldens/training_today_rest_scale2_light.png'),
    );
  }, tags: ['golden']);
}
