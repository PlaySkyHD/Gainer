import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/training/training_schedule_repository.dart';
import 'package:gainer_mobile/domain/models/training/training_plan_model.dart';
import 'package:gainer_mobile/domain/models/training/training_schedule.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';
import 'package:gainer_mobile/ui/features/training/active_workout_controller.dart';
import 'package:gainer_mobile/ui/features/training/training_plans_section.dart';
import 'package:gainer_mobile/ui/features/training/training_schedule_sheet.dart';

import 'training_plans_test_support.dart';
import 'training_test_support.dart';

// Die Harness-Uhr steht auf Samstag, 17.10.2026, 9:00 UTC.

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

  Future<void> pumpSection(WidgetTester tester, {double textScale = 1}) async {
    usePhoneSize(tester);
    await tester.pumpWidget(
      trainingTestApp(
        textScale: textScale,
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

  Future<List<TrainingPlanModel>> seedPlans(List<String> names) async => [
    for (final name in names) await seedPlan(harness, name: name),
  ];

  Future<void> saveCycle(List<String?> planIds, {int todaySlotIndex = 0}) =>
      harness.repository.schedule.saveRhythm(
        mode: TrainingScheduleMode.cycle,
        slots: [for (final id in planIds) TrainingScheduleSlot(planId: id)],
        todaySlotIndex: todaySlotIndex,
      );

  Future<void> openEditor(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('training-plans-schedule')));
    await settle(tester);
  }

  Finder saveButton() => find.byKey(const ValueKey('schedule-save'));

  bool saveEnabled(WidgetTester tester) =>
      tester.widget<GainerPillButton>(saveButton()).onPressed != null;

  Future<TrainingSchedule?> readSchedule(WidgetTester tester) =>
      tester.runAsync(harness.repository.schedule.read).then((s) => s);

  group('Karte Heute', () {
    testWidgets('Ohne Rhythmus: Rhythmus einrichten öffnet den Editor', (
      tester,
    ) async {
      await tester.runAsync(() => seedPlans(['Push']));
      await pumpSection(tester);

      expect(find.text('Rhythmus einrichten'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('training-today-setup')));
      await settle(tester);
      expect(find.text('Zyklus'), findsOneWidget);
      expect(find.text('Feste Tage'), findsOneWidget);
    });

    testWidgets('Geplantes Training startet wie aus der Planliste', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final plans = await seedPlans(['Push', 'Pull']);
        await saveCycle([plans[0].planId, plans[1].planId], todaySlotIndex: 1);
      });
      await pumpSection(tester);

      expect(find.text('Heute: Pull'), findsOneWidget);
      expect(find.text('0 Übungen · Im Rhythmus'), findsNWidgets(2));
      await tester.tap(find.byKey(const ValueKey('training-today-start')));
      await settle(tester);

      final active = await tester.runAsync(
        harness.repository.readActiveWorkout,
      );
      expect(active?.title, 'Pull');
    });

    testWidgets('Ruhetag zeigt das nächste Training mit Wochentag', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final pull = (await seedPlans(['Pull'])).single;
        // Feste Tage: nur Donnerstag Pull. Heute ist Samstag.
        await harness.repository.schedule.saveRhythm(
          mode: TrainingScheduleMode.weekly,
          slots: [
            for (var i = 0; i < 7; i++)
              TrainingScheduleSlot(planId: i == 3 ? pull.planId : null),
          ],
        );
      });
      await pumpSection(tester);

      expect(find.text('Ruhetag · Nächstes: Pull am Do'), findsOneWidget);
      expect(find.byKey(const ValueKey('training-today-start')), findsNothing);
    });

    testWidgets('Heute erledigt nach einem beendeten Training aus dem Plan', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final push = (await seedPlans(['Push'])).single;
        await saveCycle([push.planId, null]);
        await seedFinishedFromPlan(
          harness,
          push,
          DateTime.utc(2026, 10, 17, 7),
        );
      });
      harness.now = DateTime.utc(2026, 10, 17, 9);
      await pumpSection(tester);

      expect(find.text('Heute erledigt: Push'), findsOneWidget);
      expect(find.byKey(const ValueKey('training-today-start')), findsNothing);
    });

    testWidgets('Überspringen per langem Drücken und wieder aufheben', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final plans = await seedPlans(['Push', 'Pull']);
        await saveCycle([plans[0].planId, plans[1].planId, null]);
      });
      await pumpSection(tester);

      await tester.longPress(find.byKey(const ValueKey('training-today-card')));
      await settle(tester);
      expect(find.text('Verschieben…'), findsOneWidget);
      expect(find.text('Überspringen'), findsOneWidget);
      expect(find.text('Aufheben'), findsNothing);
      expect(find.text('Heute nachholen'), findsNothing);

      await tester.tap(find.text('Überspringen'));
      await settle(tester);
      expect(find.text('Ruhetag · Nächstes: Pull am So'), findsOneWidget);
      expect(find.text('Push: Übersprungen'), findsOneWidget);
      final outbox = await tester.runAsync(
        () => harness.store.readOutbox(
          aggregateType: trainingScheduleAggregateType,
        ),
      );
      expect(outbox, hasLength(1));

      await tester.longPress(find.byKey(const ValueKey('training-today-card')));
      await settle(tester);
      expect(find.text('Überspringen'), findsNothing);
      await tester.tap(find.text('Aufheben'));
      await settle(tester);
      expect(find.text('Heute: Push'), findsOneWidget);
    });

    testWidgets('Verschieben im Zyklus bietet Rhythmus und Einzeltermin', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final plans = await seedPlans(['Push', 'Pull']);
        await saveCycle([plans[0].planId, plans[1].planId]);
      });
      await pumpSection(tester);

      await tester.longPress(find.byKey(const ValueKey('training-today-card')));
      await settle(tester);
      await tester.tap(find.text('Verschieben…'));
      await settle(tester);
      expect(find.text('Rhythmus +1 Tag'), findsOneWidget);
      expect(find.text('Rhythmus +2 Tage'), findsOneWidget);
      expect(find.text('Nur dieses auf So'), findsOneWidget);
      expect(find.text('Nur dieses auf Mo'), findsOneWidget);

      await tester.tap(find.text('Rhythmus +1 Tag'));
      await settle(tester);
      expect(find.text('Ruhetag · Nächstes: Push am So'), findsOneWidget);
      final schedule = await readSchedule(tester);
      expect(schedule!.shifts.single.days, 1);
    });

    testWidgets('Feste Tage bieten kein Rhythmus verschieben an', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final push = (await seedPlans(['Push'])).single;
        await harness.repository.schedule.saveRhythm(
          mode: TrainingScheduleMode.weekly,
          slots: List.filled(7, TrainingScheduleSlot(planId: push.planId)),
        );
      });
      await pumpSection(tester);

      await tester.longPress(find.byKey(const ValueKey('training-today-card')));
      await settle(tester);
      await tester.tap(find.text('Verschieben…'));
      await settle(tester);
      expect(find.textContaining('Rhythmus +'), findsNothing);
      await tester.tap(find.text('Nur dieses auf So'));
      await settle(tester);
      final schedule = await readSchedule(tester);
      expect(schedule!.exceptions.single.movedToDate, LocalDay(2026, 10, 18));
      expect(find.text('Push: Verschoben auf So'), findsOneWidget);
    });
  });

  group('Rhythmus-Editor', () {
    testWidgets('Zyklus speichern mit gewähltem heutigen Slot', (tester) async {
      await tester.runAsync(() => seedPlans(['Push', 'Pull']));
      await pumpSection(tester);
      await openEditor(tester);

      // Vorschlag: alle Pläne und ein Ruhetag; heute ist Tag 1.
      expect(find.text('Heute ist: Tag 1 · Push'), findsOneWidget);
      expect(saveEnabled(tester), isTrue);
      await tester.tap(find.byKey(const ValueKey('schedule-today')));
      await settle(tester);
      await tester.tap(find.text('Tag 2 · Pull'));
      await settle(tester);
      expect(find.text('Heute ist: Tag 2 · Pull'), findsOneWidget);

      await tester.tap(saveButton());
      await settle(tester);

      final schedule = await readSchedule(tester);
      expect(schedule!.mode, TrainingScheduleMode.cycle);
      expect(schedule.slots.map((s) => s.isRest), [false, false, true]);
      expect(schedule.anchorDate, LocalDay(2026, 10, 16));
      expect(find.text('Heute: Pull'), findsOneWidget);
    });

    testWidgets('Nur Ruhetage: Speichern ist deaktiviert und erklärt', (
      tester,
    ) async {
      await tester.runAsync(() => seedPlans(['Push']));
      await pumpSection(tester);
      await openEditor(tester);

      final pushRow = find.ancestor(
        of: find
            .descendant(
              of: find.byType(TrainingScheduleEditor),
              matching: find.text('Push'),
            )
            .first,
        matching: find.byType(Dismissible),
      );
      await tester.drag(pushRow, const Offset(-600, 0));
      await settle(tester);

      expect(find.byKey(const ValueKey('schedule-validation')), findsOneWidget);
      expect(
        find.text('Mindestens ein Tag braucht einen Plan.'),
        findsOneWidget,
      );
      expect(saveEnabled(tester), isFalse);
      expect(find.text('Nächste 14 Tage'), findsNothing);
    });

    testWidgets('Plus Plan und Ruhetag ergänzen den Zyklus', (tester) async {
      await tester.runAsync(() => seedPlans(['Push', 'Beine']));
      await pumpSection(tester);
      await openEditor(tester);

      await tester.tap(find.byKey(const ValueKey('schedule-add-rest')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('schedule-add-plan')));
      await settle(tester);
      await tester.tap(find.text('Beine').last);
      await settle(tester);
      await tester.tap(saveButton());
      await settle(tester);

      final schedule = await readSchedule(tester);
      expect(schedule!.slots, hasLength(5));
      expect(schedule.slots[3].isRest, isTrue);
      expect(schedule.slots[4].isRest, isFalse);
    });

    testWidgets('Feste Tage: Montag Push zuordnen', (tester) async {
      final plans = await tester.runAsync(() => seedPlans(['Push']));
      await pumpSection(tester);
      await openEditor(tester);

      await tester.tap(find.text('Feste Tage'));
      await settle(tester);
      expect(saveEnabled(tester), isFalse);
      expect(
        find.text('Mindestens ein Tag braucht einen Plan.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('schedule-weekday-0')));
      await settle(tester);
      await tester.tap(find.text('Push').last);
      await settle(tester);
      expect(saveEnabled(tester), isTrue);
      await tester.tap(saveButton());
      await settle(tester);

      final schedule = await readSchedule(tester);
      expect(schedule!.mode, TrainingScheduleMode.weekly);
      expect(schedule.slots.first.planId, plans!.single.planId);
      expect(schedule.slots.skip(1).every((s) => s.isRest), isTrue);
    });

    testWidgets('Archivierter Plan im Rhythmus wird markiert', (tester) async {
      await tester.runAsync(() async {
        final plans = await seedPlans(['Push', 'Beine']);
        await saveCycle([plans[0].planId, plans[1].planId]);
        await harness.repository.archivePlan(plans[1].planId);
      });
      await pumpSection(tester);
      await openEditor(tester);

      expect(find.text('Tag 2 · Plan archiviert'), findsOneWidget);
      // Unverändert gibt es nichts zu speichern.
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('Rhythmus löschen über das Kontextmenü', (tester) async {
      await tester.runAsync(() async {
        final push = (await seedPlans(['Push'])).single;
        await saveCycle([push.planId]);
      });
      await pumpSection(tester);
      await openEditor(tester);

      await tester.tap(find.byKey(const ValueKey('schedule-menu')));
      await settle(tester);
      await tester.tap(find.text('Rhythmus löschen'));
      await settle(tester);
      expect(find.text('Rhythmus löschen?'), findsOneWidget);
      await tester.tap(find.text('Löschen'));
      await settle(tester);

      expect(await readSchedule(tester), isNull);
      expect(find.text('Rhythmus einrichten'), findsOneWidget);
    });

    testWidgets('Ohne Pläne erklärt der Editor, was fehlt', (tester) async {
      await pumpSection(tester);
      await openEditor(tester);

      expect(
        find.text('Lege zuerst einen Plan an, z. B. „Push“.'),
        findsOneWidget,
      );
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('Textgröße 2 läuft nicht über', (tester) async {
      await tester.runAsync(() => seedPlans(['Push', 'Pull', 'Beine']));
      await pumpSection(tester, textScale: 2);
      expect(tester.takeException(), isNull);
      await openEditor(tester);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Feste Tage'));
      await settle(tester);
      expect(tester.takeException(), isNull);

      // Der Editor ist eine Lazy-Liste: jeden Wochentag einzeln ins Bild holen.
      final editorList = find
          .byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.vertical)
          .last;
      for (var i = 0; i < 7; i++) {
        final row = find.byKey(ValueKey('schedule-weekday-$i'));
        await tester.scrollUntilVisible(row, 200, scrollable: editorList);
        expect(row, findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  });
}
