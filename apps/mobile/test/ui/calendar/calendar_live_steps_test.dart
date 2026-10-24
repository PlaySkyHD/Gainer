import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/health/check_in_health_coordinator.dart';
import 'package:gainer_mobile/data/repositories/health/health_steps_sync.dart';

import '../../support/fake_health_platform.dart';
import '../training/training_plans_test_support.dart';
import '../training/training_test_support.dart';
import 'calendar_test_support.dart';

void main() {
  HealthStepsSync stepsFor(
    CalendarHarness harness,
    FakeHealthPlatform health,
  ) => HealthStepsSync(
    health: CheckInHealthCoordinator(
      platform: health,
      accountId: 'acc',
      clock: () => harness.training.now.toLocal(),
    ),
    body: harness.body,
    clock: () => harness.training.now.toLocal(),
  );

  Finder checkInValue(String text) => find.descendant(
    of: find.byKey(const ValueKey('calendar-checkin-card')),
    matching: find.text(text),
  );

  testWidgets('today shows the live steps instead of the morning value', (
    tester,
  ) async {
    usePhoneSize(tester);
    final harness = await createCalendarHarness(tester);
    await tester.runAsync(() => harness.checkIn(calendarToday, steps: 1200));
    final health = FakeHealthPlatform()..steps = 8450;

    await pumpCalendar(tester, harness, steps: stepsFor(harness, health));
    await scrollIntoView(
      tester,
      find.byKey(const ValueKey('calendar-checkin-card')),
    );

    expect(checkInValue('8.450'), findsOneWidget);
    expect(checkInValue('1.200'), findsNothing);
    expect(health.checkInAuthorizations, 0);
  });

  testWidgets('today without a check-in still shows the steps', (tester) async {
    usePhoneSize(tester);
    final harness = await createCalendarHarness(tester);
    final health = FakeHealthPlatform()..steps = 3100;

    await pumpCalendar(tester, harness, steps: stepsFor(harness, health));
    await scrollIntoView(
      tester,
      find.byKey(const ValueKey('calendar-checkin-card')),
    );

    expect(checkInValue('Schritte'), findsOneWidget);
    expect(checkInValue('3.100'), findsOneWidget);
  });

  testWidgets('yesterday is updated to the full day total', (tester) async {
    usePhoneSize(tester);
    final harness = await createCalendarHarness(tester);
    final yesterday = calendarToday.addDays(-1);
    await tester.runAsync(() => harness.checkIn(yesterday, steps: 1200));
    final health = FakeHealthPlatform()
      ..stepsFor = (from) => from.toLocal().day == yesterday.day ? 11800 : null;

    await pumpCalendar(tester, harness, steps: stepsFor(harness, health));
    await tapDay(tester, yesterday);
    await scrollIntoView(
      tester,
      find.byKey(const ValueKey('calendar-checkin-card')),
    );

    expect(checkInValue('11.800'), findsOneWidget);
    expect(checkInValue('1.200'), findsNothing);
  });
}
