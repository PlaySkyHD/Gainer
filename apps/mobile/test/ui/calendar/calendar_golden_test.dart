import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/training_schedule.dart';

import '../training/training_plans_test_support.dart';
import 'calendar_test_support.dart';

LocalDay _oct(int day) => LocalDay(2026, 10, day);

/// Hohe Ansicht, damit Raster und Tagesansicht ganz im Bild sind.
void _useTallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Oktober mit erledigten, verpassten und geplanten Trainings, Cardio,
/// Check-ins und Ernährung. Mo Push, Mi Pull, Do Beine seit dem 1.
Future<void> _seedMonth(WidgetTester tester, CalendarHarness harness) =>
    tester.runAsync(() async {
      final push = await harness.plan('Push');
      final pull = await harness.plan('Pull');
      final legs = await harness.plan('Beine');
      await harness.weekly([
        push.planId,
        null,
        pull.planId,
        legs.planId,
        null,
        null,
        null,
      ], validFrom: _oct(1));
      await harness.target(from: '2026-10-01');
      for (final day in [5, 12, 19]) {
        await harness.finishedFromPlan(push, _oct(day));
      }
      for (final day in [7, 14]) {
        await harness.finishedFromPlan(pull, _oct(day));
      }
      await harness.finishedFromPlan(legs, _oct(8));
      await harness.finishedEmpty('Oberkörper', _oct(16));
      for (final day in [10, 17, 20]) {
        await harness.cardioOn(_oct(day));
      }
      for (final day in [6, 12, 14, 18, 21, 22]) {
        await harness.checkIn(
          _oct(day),
          weightKg: day == 22 ? 82.4 : 83.4 - day * 0.05,
          steps: 6000 + day * 150,
          sleepMinutes: 420 + day,
        );
      }
      for (final day in [12, 13, 14, 21, 22]) {
        await harness.food(
          _oct(day),
          kcal: 2100 + day * 10,
          protein: 140,
          carbs: 240,
          fat: 70,
        );
      }
    });

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    final name = brightness.name;

    testWidgets('Kalender heute $name', (tester) async {
      _useTallPhone(tester);
      final harness = await createCalendarHarness(tester);
      await _seedMonth(tester, harness);

      await pumpCalendar(
        tester,
        harness,
        brightness: brightness,
        overview: fakeOverview(),
      );

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(CupertinoApp),
        matchesGoldenFile('goldens/calendar_today_$name.png'),
      );
    }, tags: ['golden']);
  }

  testWidgets('Kalender vergangener Tag', (tester) async {
    _useTallPhone(tester);
    final harness = await createCalendarHarness(tester);
    await _seedMonth(tester, harness);
    await pumpCalendar(tester, harness);

    await tapDay(tester, _oct(14));

    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(CupertinoApp),
      matchesGoldenFile('goldens/calendar_past_day_light.png'),
    );
  }, tags: ['golden']);

  testWidgets('Kalender künftiger Tag dunkel', (tester) async {
    _useTallPhone(tester);
    final harness = await createCalendarHarness(tester);
    await _seedMonth(tester, harness);
    await pumpCalendar(tester, harness, brightness: Brightness.dark);

    await tapDay(tester, _oct(26));

    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(CupertinoApp),
      matchesGoldenFile('goldens/calendar_future_day_dark.png'),
    );
  }, tags: ['golden']);

  for (final day in [22, 14]) {
    testWidgets('Kalender Textgröße 2 am $day.', (tester) async {
      _useTallPhone(tester);
      final harness = await createCalendarHarness(tester);
      await _seedMonth(tester, harness);
      await pumpCalendar(
        tester,
        harness,
        textScale: 2,
        overview: fakeOverview(),
      );
      if (day != 22) await tapDay(tester, _oct(day));

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(CupertinoApp),
        matchesGoldenFile('goldens/calendar_scale2_${day}_light.png'),
      );
    }, tags: ['golden']);
  }

  testWidgets('Kalender ohne Rhythmus', (tester) async {
    usePhoneSize(tester);
    final harness = await createCalendarHarness(tester);
    await pumpCalendar(tester, harness);

    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(CupertinoApp),
      matchesGoldenFile('goldens/calendar_no_schedule_light.png'),
    );
  }, tags: ['golden']);
}
