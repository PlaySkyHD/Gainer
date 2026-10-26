import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/body/body_repository.dart';
import 'package:gainer_mobile/data/repositories/cardio/cardio_preferences.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_feature.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_hrv_measurement_screen.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_settings_screen.dart';

import '../training/training_test_support.dart' hide testId;
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

    expect(find.text('Erlaubt sind 100 bis 230.'), findsOneWidget);
    expect((await stored(tester)).maxHeartRate, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('cardio-settings-max')),
      '',
    );
    await settle(tester);
    expect(find.text('Erlaubt sind 100 bis 230.'), findsNothing);
  });

  testWidgets('Maximalpuls über 230 wird abgelehnt und der Grund steht da', (
    tester,
  ) async {
    await openSettings(tester);
    expect(find.textContaining('höchstens mit 230 bpm'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('cardio-settings-max')),
      '240',
    );
    await settle(tester);

    expect(find.text('Erlaubt sind 100 bis 230.'), findsOneWidget);
    expect((await stored(tester)).maxHeartRate, isNull);
  });

  testWidgets('ein älterer Maximalpuls über 230 endet in Zone 5 bei 230', (
    tester,
  ) async {
    await tester.runAsync(
      () => harness.repository.preferences.write(
        const CardioPreferenceValues(maxHeartRate: 245),
      ),
    );
    await openSettings(tester);
    await scrollIntoView(tester, find.text('Zone 5'));

    expect(find.text('207–230 bpm'), findsOneWidget);
  });

  // Die Feldzeilen stapeln Beschriftung und Eingabe erst über 1,5.
  for (final scale in [1.3, 1.5, 2.0]) {
    testWidgets('Textgröße $scale läuft nicht über', (tester) async {
      await tester.runAsync(
        () => harness.repository.preferences.write(
          const CardioPreferenceValues(
            maxHeartRate: 190,
            age: 40,
            restingHeartRate: 60,
          ),
        ),
      );
      phoneSize(tester);
      await tester.pumpWidget(
        trainingTestApp(
          textScale: scale,
          home: CardioSettingsScreen(
            preferences: harness.repository.preferences,
          ),
        ),
      );
      await settle(tester);

      for (final finder in [
        find.byKey(const ValueKey('cardio-settings-max')),
        find.byKey(const ValueKey('cardio-settings-age')),
        find.byKey(const ValueKey('cardio-settings-rest')),
        find.byKey(const ValueKey('cardio-settings-templates')),
        find.byKey(const ValueKey('cardio-settings-offer')),
        find.byKey(const ValueKey('cardio-settings-weekly')),
        find.byKey(const ValueKey('cardio-settings-alerts')),
        find.byKey(const ValueKey('cardio-settings-voice')),
        find.byKey(const ValueKey('cardio-settings-voice-interval')),
        find.text('Zone 5'),
      ]) {
        await scrollIntoView(tester, finder);
        expect(finder, findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('Alarm und Aufwärmzeit werden gespeichert', (tester) async {
    await openSettings(tester);

    await tester.tap(find.byKey(const ValueKey('cardio-settings-alerts')));
    await settle(tester);
    // Die Aufwärmzeit steht vor der Sprach-Auswahl (die ebenfalls „5“ hat).
    await tester.tap(find.text('5').first);
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

  testWidgets('Wochenziel: 30 bis 600, Standard 150', (tester) async {
    await openSettings(tester);
    final field = find.byKey(const ValueKey('cardio-settings-weekly'));
    expect(tester.widget<CupertinoTextField>(field).controller!.text, '150');

    await tester.enterText(field, '240');
    await settle(tester);
    expect((await stored(tester)).weeklyTargetMinutes, 240);

    await tester.enterText(field, '10');
    await settle(tester);
    expect(find.text('Erlaubt sind 30 bis 600.'), findsOneWidget);
    expect((await stored(tester)).weeklyTargetMinutes, 240);

    await tester.enterText(field, '601');
    await settle(tester);
    expect(find.text('Erlaubt sind 30 bis 600.'), findsOneWidget);
    expect((await stored(tester)).weeklyTargetMinutes, 240);
  });

  testWidgets('HRV-Messung ist nur mit Check-in erreichbar', (tester) async {
    await openSettings(tester);
    expect(find.byKey(const ValueKey('cardio-settings-hrv')), findsNothing);

    var id = 900;
    final feature = CardioFeature(
      repository: harness.repository,
      session: harness.controller,
      health: harness.feature.health,
      body: BodyRepository(store: harness.store, ids: () => testId(id++)),
    );
    phoneSize(tester, height: 1400);
    await tester.pumpWidget(
      trainingTestApp(
        home: CardioSettingsScreen(
          preferences: harness.repository.preferences,
          feature: feature,
        ),
      ),
    );
    await settle(tester);
    expect(find.text('HRV-Messung'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cardio-settings-hrv')));
    await settle(tester);
    expect(find.byType(HrvMeasurementScreen), findsOneWidget);
  });
}
