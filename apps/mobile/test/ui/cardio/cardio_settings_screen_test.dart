import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/cardio/cardio_preferences.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_settings_screen.dart';

import '../training/training_test_support.dart';
import 'cardio_test_support.dart';

void main() {
  late CardioHarness harness;

  setUp(() async {
    harness = await CardioHarness.create();
  });

  tearDown(() async => harness.dispose());

  Future<void> openSettings(WidgetTester tester) async {
    phoneSize(tester, height: 1200);
    await tester.pumpWidget(
      trainingTestApp(
        home: CardioSettingsScreen(preferences: harness.repository.preferences),
      ),
    );
    await settle(tester);
  }

  Future<CardioPreferenceValues> stored(WidgetTester tester) async =>
      (await tester.runAsync(harness.repository.preferences.read))!;

  testWidgets('Alter zeigt den geschätzten Maximalpuls', (tester) async {
    await openSettings(tester);
    expect(find.text('optional'), findsNWidgets(3));

    await tester.enterText(
      find.byKey(const ValueKey('cardio-settings-age')),
      '40',
    );
    await settle(tester);

    expect(find.text('geschätzt 180'), findsOneWidget);
    expect((await stored(tester)).age, 40);
    // Zonen aus 180 bpm: Zone 2 = 108–126.
    expect(find.text('108–126 bpm'), findsOneWidget);
  });

  testWidgets('angegebener Maximalpuls und Ruhepuls bestimmen die Zonen', (
    tester,
  ) async {
    await openSettings(tester);
    expect(
      find.textContaining('Gib Maximalpuls oder Alter an'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('cardio-settings-max')),
      '190',
    );
    await settle(tester);
    expect(find.text('Zone 2'), findsOneWidget);
    expect(find.text('114–133 bpm'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('cardio-settings-rest')),
      '60',
    );
    await settle(tester);
    expect(find.text('138–151 bpm'), findsOneWidget);
    final values = await stored(tester);
    expect((values.maxHeartRate, values.restingHeartRate), (190, 60));
  });

  testWidgets('Werte außerhalb des Bereichs werden nicht gespeichert', (
    tester,
  ) async {
    await openSettings(tester);

    await tester.enterText(
      find.byKey(const ValueKey('cardio-settings-max')),
      '50',
    );
    await settle(tester);

    expect(find.text('Erlaubt sind 100 bis 250.'), findsOneWidget);
    expect((await stored(tester)).maxHeartRate, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('cardio-settings-max')),
      '',
    );
    await settle(tester);
    expect(find.text('Erlaubt sind 100 bis 250.'), findsNothing);
  });

  testWidgets('Alarm und Aufwärmzeit werden gespeichert', (tester) async {
    await openSettings(tester);

    await tester.tap(find.byKey(const ValueKey('cardio-settings-alerts')));
    await settle(tester);
    await tester.tap(find.text('5'));
    await settle(tester);

    final values = await stored(tester);
    expect(values.alertsEnabled, isFalse);
    expect(values.warmupSeconds, 300);
  });

  testWidgets('lädt vorhandene Werte in die Felder', (tester) async {
    await tester.runAsync(
      () => harness.repository.preferences.write(
        const CardioPreferenceValues(maxHeartRate: 185, restingHeartRate: 55),
      ),
    );
    await openSettings(tester);

    expect(find.text('185'), findsOneWidget);
    expect(find.text('55'), findsOneWidget);
  });
}
