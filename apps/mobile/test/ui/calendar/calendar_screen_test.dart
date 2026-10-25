import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/nutrition/nutrition_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/domain/models/nutrition/nutrition.dart';
import 'package:gainer_mobile/domain/models/training/training_schedule.dart';
import 'package:gainer_mobile/ui/core/view_models/mobile_shell_view_model.dart';
import 'package:gainer_mobile/ui/features/calendar/calendar_format.dart';
import 'package:gainer_mobile/ui/features/calendar/calendar_screen.dart';

import '../training/training_plans_test_support.dart';
import '../training/training_test_support.dart';
import 'calendar_test_support.dart';

LocalDay _oct(int day) => LocalDay(2026, 10, day);

void main() {
  testWidgets('opens on today with title, month and weekday names', (
    tester,
  ) async {
    usePhoneSize(tester);
    final harness = await createCalendarHarness(tester);

    await pumpCalendar(tester, harness);

    expect(find.text('Übersicht'), findsWidgets);
    // Oben die Tages-Pille, ohne zusätzliches „Heute“ für den heutigen Tag.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('calendar-date-pill')),
        matching: find.text('Heute'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('calendar-today')), findsNothing);
    expect(find.text('Oktober 2026'), findsOneWidget);
    for (final name in ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(dayLabel(tester, calendarToday), 'Heute, Donnerstag, 22. Oktober');
    final today = tester.widget<Semantics>(
      find.byKey(ValueKey('calendar-day-${calendarToday.toIso()}')),
    );
    expect(today.properties.selected, isTrue);
    expect(find.text('Donnerstag, 22. Oktober'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the day pill steps days, jumps to the calendar and back', (
    tester,
  ) async {
    usePhoneSize(tester);
    final harness = await createCalendarHarness(tester);
    await pumpCalendar(tester, harness);
    final pill = find.byKey(const ValueKey('calendar-date-pill'));
    String pillText() => tester
        .widget<Text>(find.descendant(of: pill, matching: find.byType(Text)))
        .data!;
    final scroll = find
        .descendant(
          of: find.byType(CalendarScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    double offset() => tester.state<ScrollableState>(scroll).position.pixels;

    // Ein Tipp auf den Text scrollt zum Kalender unten.
    await tester.tap(pill);
    await settle(tester);
    expect(offset(), greaterThan(0));
    expect(find.text('Oktober 2026').hitTestable(), findsOneWidget);

    // Ein Tag im Kalender führt zurück nach oben zu seinen Werten.
    await tapDay(tester, LocalDay(2026, 10, 14));
    expect(offset(), 0);
    expect(pillText(), 'Mi. 14. Okt.');
    expect(find.text('Mittwoch, 14. Oktober'), findsOneWidget);

    // Pfeile wechseln den Tag, auch über die Monatsgrenze.
    await tester.tap(find.bySemanticsLabel('Vorheriger Tag'));
    await settle(tester);
    expect(find.text('Dienstag, 13. Oktober'), findsOneWidget);
    for (var i = 0; i < 19; i++) {
      await tester.tap(find.bySemanticsLabel('Nächster Tag'));
      await settle(tester);
    }
    expect(pillText(), 'So. 1. Nov.');
    expect(find.text('Sonntag, 1. November'), findsOneWidget);
    await scrollIntoView(tester, find.text('November 2026'));
    expect(find.text('November 2026'), findsOneWidget);

    // „Zu heute“ steht nur bei einem anderen Tag.
    await scrollIntoView(tester, find.byKey(const ValueKey('calendar-today')));
    await tester.tap(find.byKey(const ValueKey('calendar-today')));
    await settle(tester);
    expect(pillText(), 'Heute');
    expect(find.byKey(const ValueKey('calendar-today')), findsNothing);
    expect(find.text('Donnerstag, 22. Oktober'), findsOneWidget);
  });

  testWidgets('without a schedule today points to the rhythm editor', (
    tester,
  ) async {
    usePhoneSize(tester);
    final harness = await createCalendarHarness(tester);

    await pumpCalendar(tester, harness);

    expect(find.text('Rhythmus einrichten'), findsOneWidget);
    await tester.tap(find.text('Rhythmus einrichten'));
    await settle(tester);
    expect(find.text('Zyklus'), findsWidgets);
  });

  testWidgets('the toolbar opens the rhythm editor', (tester) async {
    usePhoneSize(tester);
    final harness = await createCalendarHarness(tester);
    await pumpCalendar(tester, harness);

    await tester.tap(find.byKey(const ValueKey('calendar-schedule')));
    await settle(tester);

    expect(find.text('Feste Tage'), findsWidgets);
  });

  testWidgets('VoiceOver names all markers of a day', (tester) async {
    usePhoneSize(tester);
    final harness = await createCalendarHarness(tester);
    late String pullId;
    await tester.runAsync(() async {
      final push = await harness.plan('Push');
      final pull = await harness.plan('Pull');
      pullId = pull.planId;
      await harness.weekly([
        null,
        null,
        push.planId,
        null,
        pull.planId,
        null,
        null,
      ]);
      await harness.finishedFromPlan(push, _oct(21));
      await harness.checkIn(_oct(21));
      await harness.food(_oct(21), kcal: 2000);
    });
    expect(pullId, isNotEmpty);

    await pumpCalendar(tester, harness);

    expect(
      dayLabel(tester, _oct(21)),
      'Mittwoch, 21. Oktober, Krafttraining, Check-in',
    );
    expect(
      dayLabel(tester, _oct(23)),
      'Freitag, 23. Oktober, Training geplant',
    );
    expect(dayLabel(tester, _oct(20)), 'Dienstag, 20. Oktober');
  });

  testWidgets('a future day shows only the plan card with its actions', (
    tester,
  ) async {
    usePhoneSize(tester);
    final harness = await createCalendarHarness(tester);
    await tester.runAsync(() async {
      final legs = await harness.plan('Beine');
      await harness.cycle([legs.planId, null], todayIndex: 1);
    });
    await pumpCalendar(tester, harness);

    await tapDay(tester, _oct(23));

    expect(find.text('Freitag, 23. Oktober'), findsOneWidget);
    expect(find.text('Plan'), findsOneWidget);
    expect(find.text('Beine'), findsOneWidget);
    expect(find.text('Geplant'), findsOneWidget);
    expect(find.text('Starten'), findsNothing);
    expect(find.text('Training'), findsNothing);
    expect(find.text('Ernährung'), findsNothing);
    expect(find.text('Check-in'), findsNothing);

    await tester.tap(find.text('Beine'));
    await settle(tester);
    expect(find.text('Verschieben…'), findsOneWidget);
    expect(find.text('Überspringen'), findsOneWidget);
    expect(find.text('Starten'), findsNothing);
  });

  testWidgets('skipping a future training updates day view and marker', (
    tester,
  ) async {
    usePhoneSize(tester);
    final harness = await createCalendarHarness(tester);
    await tester.runAsync(() async {
      final legs = await harness.plan('Beine');
      await harness.cycle([legs.planId, null], todayIndex: 1);
    });
    await pumpCalendar(tester, harness);
    await tapDay(tester, _oct(23));
    expect(dayLabel(tester, _oct(23)), contains('Training geplant'));

    await tester.tap(find.text('Beine'));
    await settle(tester);
    await tester.tap(find.text('Überspringen'));
    await settle(tester);

    expect(find.text('Übersprungen'), findsOneWidget);
    expect(dayLabel(tester, _oct(23)), isNot(contains('Training geplant')));
  });

  testWidgets('an empty past day reads "Keine Einträge"', (tester) async {
    usePhoneSize(tester);
    final harness = await createCalendarHarness(tester);
    await pumpCalendar(tester, harness);

    await tapDay(tester, _oct(3));

    expect(find.text('Samstag, 3. Oktober'), findsOneWidget);
    expect(find.text('Keine Einträge'), findsOneWidget);
    expect(find.text('Plan'), findsNothing);
  });

  testWidgets('a past day shows done plan, training and nutrition', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = await createCalendarHarness(tester);
    await tester.runAsync(() async {
      final pull = await harness.plan('Pull');
      // Mittwoch Pull, gültig seit 1. Oktober.
      await harness.weekly([
        null,
        null,
        pull.planId,
        null,
        null,
        null,
        null,
      ], validFrom: _oct(1));
      await harness.target(from: '2026-10-01');
      await harness.finishedFromPlan(pull, _oct(14));
      await harness.food(_oct(14), kcal: 2350, protein: 142);
      await harness.checkIn(_oct(14), steps: 8432, sleepMinutes: 455);
    });
    final areas = <MobileArea>[];
    final days = <String>[];
    final checkInDays = <String>[];
    await pumpCalendar(
      tester,
      harness,
      onOpenArea: areas.add,
      onOpenNutritionDay: days.add,
      onOpenCheckInDay: checkInDays.add,
    );

    await tapDay(tester, _oct(14));

    expect(find.text('Erledigt'), findsOneWidget);
    expect(find.text('Pull'), findsNWidgets(2));
    expect(find.text('58 min · Volumen 1.200 kg'), findsOneWidget);
    expect(find.text('2.350'), findsOneWidget);
    expect(find.text('Übrig'), findsOneWidget);
    expect(find.text('142 / 180 g'), findsOneWidget);
    expect(find.text('82,4 kg'), findsOneWidget);
    expect(find.text('8.432'), findsOneWidget);
    expect(find.text('7 h 35 min'), findsOneWidget);
    expect(find.text('Keine Einträge'), findsNothing);

    await tester.tap(find.text('2.350'));
    await settle(tester);
    expect(days, ['2026-10-14']);

    // Der Check-in öffnet den gewählten Tag, nicht nur den Tab.
    await tester.tap(find.text('82,4 kg'));
    await settle(tester);
    expect(checkInDays, ['2026-10-14']);
    expect(areas, isEmpty);
  });

  testWidgets('swiping changes the month and "Heute" returns', (tester) async {
    usePhoneSize(tester);
    final harness = await createCalendarHarness(tester);
    await pumpCalendar(tester, harness);
    final grid = find.byKey(const ValueKey('calendar-month-grid'));

    await tester.fling(grid, const Offset(300, 0), 1000);
    await settle(tester);
    expect(find.text('September 2026'), findsOneWidget);
    await tester.fling(grid, const Offset(300, 0), 1000);
    await settle(tester);
    expect(find.text('August 2026'), findsOneWidget);
    expect(find.text('Samstag, 1. August'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('calendar-today')));
    await settle(tester);
    expect(find.text('Oktober 2026'), findsOneWidget);
    expect(find.text('Donnerstag, 22. Oktober'), findsOneWidget);

    await tester.fling(grid, const Offset(-300, 0), 1000);
    await settle(tester);
    expect(find.text('November 2026'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Vorheriger Monat'));
    await settle(tester);
    expect(find.text('Oktober 2026'), findsOneWidget);
  });

  testWidgets('today shows the plan, then the weight trend, without '
      'repeating the weight in the check-in card', (tester) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = await createCalendarHarness(tester);
    await tester.runAsync(() async {
      final push = await harness.plan('Push');
      await harness.cycle([push.planId, null]);
      await harness.checkIn(calendarToday, steps: 9000);
      await harness.food(calendarToday, kcal: 1280, protein: 42);
    });
    final overview = fakeOverview();
    final areas = <MobileArea>[];

    await pumpCalendar(
      tester,
      harness,
      overview: overview,
      onOpenArea: areas.add,
    );

    expect(find.text('Heute: Push'), findsOneWidget);
    expect(find.text('Starten'), findsOneWidget);
    expect(find.text('Gewicht'), findsOneWidget);
    expect(find.text('82,4 kg', findRichText: true), findsOneWidget);
    expect(find.text('−0,4 kg/Woche'), findsOneWidget);
    expect(find.text('Trainingsübersicht'), findsOneWidget);
    expect(find.text('1.280'), findsOneWidget);
    expect(find.text('42 g'), findsOneWidget);
    expect(find.text('9.000'), findsOneWidget);
    // Das Gewicht steht nur in der Gewichtskarte.
    final checkIn = find.byKey(const ValueKey('calendar-checkin-card'));
    expect(checkIn, findsOneWidget);
    expect(
      find.descendant(of: checkIn, matching: find.text('Gewicht')),
      findsNothing,
    );

    final plan = tester.getTopLeft(find.text('Heute: Push')).dy;
    final weight = tester.getTopLeft(find.text('Gewicht')).dy;
    final nutrition = tester.getTopLeft(find.text('Ernährung')).dy;
    final training = tester.getTopLeft(find.text('Trainingsübersicht')).dy;
    // Plan, dann Ernährung, Gewicht und Trainingsübersicht.
    expect(plan, lessThan(nutrition));
    expect(nutrition, lessThan(weight));
    expect(weight, lessThan(training));

    await tester.tap(find.text('Trainingsübersicht'));
    await settle(tester);
    expect(areas, [MobileArea.training]);
  });

  testWidgets('today without food still offers the nutrition tab', (
    tester,
  ) async {
    usePhoneSize(tester);
    final harness = await createCalendarHarness(tester);
    final days = <String>[];
    await pumpCalendar(tester, harness, onOpenNutritionDay: days.add);

    final card = find.byKey(const ValueKey('calendar-nutrition-card'));
    await scrollIntoView(tester, card);
    expect(find.text('Gegessen'), findsOneWidget);
    await tester.tap(card);
    await settle(tester);

    expect(days, ['2026-10-22']);
  });

  testWidgets('returning to the tab reloads local data', (tester) async {
    usePhoneSize(tester);
    final harness = await createCalendarHarness(tester);
    final tab = ValueNotifier<int>(0);
    addTearDown(tab.dispose);
    await pumpCalendar(
      tester,
      harness,
      visibility: tab,
      isVisible: () => tab.value == 0,
    );
    expect(dayLabel(tester, calendarToday), isNot(contains('Krafttraining')));

    tab.value = 1;
    await settle(tester);
    await tester.runAsync(
      () => harness.finishedEmpty('Abendtraining', calendarToday),
    );
    tab.value = 0;
    await settle(tester);

    expect(dayLabel(tester, calendarToday), contains('Krafttraining'));
    expect(find.text('Abendtraining'), findsOneWidget);
  });

  testWidgets('a day requested from outside is shown once', (tester) async {
    usePhoneSize(tester);
    final harness = await createCalendarHarness(tester);
    final tab = ValueNotifier<int>(1);
    addTearDown(tab.dispose);
    LocalDay? requested = LocalDay(2026, 9, 15);
    await tester.runAsync(
      () => harness.finishedEmpty('Septembertraining', requested!),
    );
    LocalDay? take() {
      final day = requested;
      requested = null;
      return day;
    }

    await pumpCalendar(
      tester,
      harness,
      visibility: tab,
      isVisible: () => tab.value == 0,
      takeRequestedDay: take,
    );

    // Beim ersten Bild angefragt: der Tag aus einem anderen Monat.
    expect(find.text(calendarDayLabel(LocalDay(2026, 9, 15))), findsOneWidget);
    expect(find.text('Septembertraining'), findsOneWidget);

    await tester.runAsync(
      () => harness.finishedEmpty('Oktobertraining', _oct(5)),
    );
    requested = _oct(5);
    tab.value = 0;
    await settle(tester);

    expect(find.text(calendarDayLabel(_oct(5))), findsOneWidget);
    expect(find.text('Oktobertraining'), findsOneWidget);
    expect(requested, isNull);
  });

  testWidgets('a requested day is taken once the tab shows and ticks', (
    tester,
  ) async {
    usePhoneSize(tester);
    final harness = await createCalendarHarness(tester);
    final tab = ValueNotifier<int>(1);
    addTearDown(tab.dispose);
    LocalDay? requested;
    final tickersAtTake = <bool>[];
    LocalDay? take() {
      final day = requested;
      requested = null;
      if (day != null) {
        final calendar = tester.element(find.byType(CalendarScreen));
        tickersAtTake.add(TickerMode.getValuesNotifier(calendar).value.enabled);
      }
      return day;
    }

    await pumpCalendar(
      tester,
      harness,
      visibility: tab,
      isVisible: () => tab.value == 0,
      takeRequestedDay: take,
      // Wie CupertinoTabScaffold: TickerMode folgt dem Tab erst im
      // nächsten Bild.
      wrap: (calendar) => ValueListenableBuilder<int>(
        valueListenable: tab,
        builder: (context, index, child) =>
            TickerMode(enabled: index == 0, child: child!),
        child: calendar,
      ),
    );

    requested = _oct(5);
    tab.value = 0;
    // Beim Umschalten selbst bleibt die Anfrage liegen.
    expect(requested, _oct(5));
    await settle(tester);

    expect(tickersAtTake, [true]);
    expect(requested, isNull);
    expect(find.text(calendarDayLabel(_oct(5))), findsOneWidget);
  });

  testWidgets('a refresh signal reloads while visible', (tester) async {
    usePhoneSize(tester);
    final harness = await createCalendarHarness(tester);
    final sync = ValueNotifier<int>(0);
    addTearDown(sync.dispose);
    await pumpCalendar(tester, harness, refresh: sync);

    await tester.runAsync(() => harness.checkIn(_oct(20)));
    sync.value++;
    await settle(tester);

    expect(dayLabel(tester, _oct(20)), contains('Check-in'));
  });

  testWidgets('failing nutrition keeps grid, plan and "Starten"', (
    tester,
  ) async {
    usePhoneSize(tester);
    final harness = await createCalendarHarness(tester);
    await tester.runAsync(() async {
      final push = await harness.plan('Push');
      await harness.cycle([push.planId, null]);
    });

    await pumpCalendar(
      tester,
      harness,
      nutrition: _FailingNutrition(harness.training.store),
    );

    expect(find.byKey(const ValueKey('calendar-month-grid')), findsOneWidget);
    expect(find.text('Heute: Push'), findsOneWidget);
    expect(find.text('Starten'), findsOneWidget);
    expect(find.text('Nicht geladen: Ernährung.'), findsOneWidget);
  });

  testWidgets('today shows the local weight even if the dashboard is older', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = await createCalendarHarness(tester);
    await tester.runAsync(
      () => harness.checkIn(calendarToday, weightKg: 81.2, steps: 7000),
    );

    await pumpCalendar(tester, harness, overview: fakeOverview());

    expect(find.text('81,2 kg', findRichText: true), findsOneWidget);
    expect(find.text('82,4 kg', findRichText: true), findsNothing);
    final checkIn = find.byKey(const ValueKey('calendar-checkin-card'));
    expect(
      find.descendant(of: checkIn, matching: find.text('Gewicht')),
      findsNothing,
    );
  });

  testWidgets('showing the tab again also reloads the dashboard', (
    tester,
  ) async {
    usePhoneSize(tester);
    final harness = await createCalendarHarness(tester);
    final api = FakeDashboardApi();
    final tab = ValueNotifier<int>(0);
    addTearDown(tab.dispose);
    await pumpCalendar(
      tester,
      harness,
      overview: fakeOverview(api),
      visibility: tab,
      isVisible: () => tab.value == 0,
    );
    expect(api.calls, 1);

    tab.value = 1;
    await settle(tester);
    tab.value = 0;
    await settle(tester);

    expect(api.calls, 2);
  });

  testWidgets('resuming the app on a new day moves today', (tester) async {
    usePhoneSize(tester);
    final harness = await createCalendarHarness(tester);
    await pumpCalendar(tester, harness);
    expect(find.text('Donnerstag, 22. Oktober'), findsOneWidget);

    harness.training.now = DateTime.utc(2026, 10, 23, 10);
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await settle(tester);

    expect(find.text('Freitag, 23. Oktober'), findsOneWidget);
    expect(dayLabel(tester, _oct(23)), startsWith('Heute'));
  });

  testWidgets('a very narrow grid does not throw', (tester) async {
    tester.view.physicalSize = const Size(200, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = await createCalendarHarness(tester);

    await pumpCalendar(tester, harness);

    final exception = tester.takeException();
    expect(exception, isNot(isA<ArgumentError>()));
    expect(find.byKey(const ValueKey('calendar-month-grid')), findsOneWidget);
  });
}

class _FailingNutrition extends NutritionRepository {
  _FailingNutrition(LocalSyncStore store) : super(store: store);

  @override
  Future<({List<NutritionDay> days, NutritionTargetSchedule? targets})>
  readDays(String from, String to) async => throw StateError('kaputt');
}
