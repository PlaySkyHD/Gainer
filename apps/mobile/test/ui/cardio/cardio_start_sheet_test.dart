import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/cardio/cardio_preferences.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_format.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_start_sheet.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_zone_fields.dart';

import '../training/training_test_support.dart';
import 'cardio_test_support.dart';

void main() {
  late CardioHarness harness;

  setUp(() async {
    harness = await CardioHarness.create();
  });

  tearDown(() async => harness.dispose());

  Future<void> openSheet(WidgetTester tester, {double textScale = 1}) async {
    phoneSize(tester);
    await tester.pumpWidget(
      trainingTestApp(
        textScale: textScale,
        home: Builder(
          builder: (context) => CupertinoPageScaffold(
            child: Center(
              child: CupertinoButton(
                onPressed: () => showCardioStartSheet(context, harness.feature),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await pumpUi(tester);
  }

  String fieldText(WidgetTester tester, String key) => tester
      .widget<CupertinoTextField>(find.byKey(ValueKey(key)))
      .controller!
      .text;

  testWidgets('belegt den zuletzt genutzten Bereich vor', (tester) async {
    await tester.runAsync(
      () => harness.repository.preferences.write(
        const CardioPreferenceValues(lastZoneLow: 125, lastZoneHigh: 145),
      ),
    );
    await openSheet(tester);

    expect(fieldText(tester, 'cardio-zone-low'), '125');
    expect(fieldText(tester, 'cardio-zone-high'), '145');
    expect(find.text('Cardio starten'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ungültiger Bereich zeigt den Grund und sperrt Starten', (
    tester,
  ) async {
    await openSheet(tester);

    await tester.enterText(
      find.byKey(const ValueKey('cardio-zone-high')),
      '110',
    );
    await tester.pump();
    expect(find.text(zoneRangeError), findsOneWidget);
    expect(
      tester
          .widget<GainerPillButton>(find.byKey(const ValueKey('cardio-start')))
          .onPressed,
      isNull,
    );

    await tester.enterText(find.byKey(const ValueKey('cardio-zone-low')), '30');
    await tester.enterText(
      find.byKey(const ValueKey('cardio-zone-high')),
      '150',
    );
    await tester.pump();
    expect(find.text(zoneRangeError), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('cardio-zone-low')), '40');
    await tester.enterText(
      find.byKey(const ValueKey('cardio-zone-high')),
      '231',
    );
    await tester.pump();
    expect(find.text(zoneRangeError), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('cardio-zone-high')),
      '230',
    );
    await tester.pump();
    expect(find.text(zoneRangeError), findsNothing);
    expect(
      tester
          .widget<GainerPillButton>(find.byKey(const ValueKey('cardio-start')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('Zonen-Chips füllen den Bereich', (tester) async {
    await tester.runAsync(
      () => harness.repository.preferences.write(
        const CardioPreferenceValues(maxHeartRate: 190),
      ),
    );
    await openSheet(tester);

    expect(find.text('Zone 1'), findsOneWidget);
    expect(find.text('Zone 5'), findsOneWidget);
    expect(find.byKey(const ValueKey('cardio-zone-hint')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('cardio-zone-chip-2')));
    await tester.pump();

    expect(fieldText(tester, 'cardio-zone-low'), '114');
    expect(fieldText(tester, 'cardio-zone-high'), '133');
  });

  testWidgets('ohne Maximalpuls steht ein Hinweis statt der Chips', (
    tester,
  ) async {
    await openSheet(tester);

    expect(find.byKey(const ValueKey('cardio-zone-chip-1')), findsNothing);
    expect(
      find.text(
        'Maximalpuls in den Cardio-Einstellungen angeben, um Zonen '
        'vorzuschlagen',
      ),
      findsOneWidget,
    );
  });

  testWidgets('ohne Gurt erklärt ein Hinweis, dass kein Puls erfasst wird', (
    tester,
  ) async {
    harness.platform.hasSensor = false;
    await openSheet(tester);

    expect(find.text('Gurt suchen'), findsOneWidget);
    expect(find.text('Ohne Gurt wird kein Puls erfasst.'), findsOneWidget);
  });

  testWidgets('gemerkter Gurt zeigt Zustand und Akku', (tester) async {
    await openSheet(tester);

    expect(find.text('Polar H10'), findsOneWidget);
    expect(find.text('Verbunden · Akku 80\u00A0%'), findsOneWidget);
    expect(find.text('Ohne Gurt wird kein Puls erfasst.'), findsNothing);
    expect(find.text('Anderen Gurt suchen'), findsOneWidget);
  });

  testWidgets('Suche listet Gurte und Tippen verbindet', (tester) async {
    harness.platform.hasSensor = false;
    await openSheet(tester);

    await tester.tap(find.text('Gurt suchen'));
    await pumpUi(tester);
    expect(harness.platform.scans, 1);
    expect(find.text('Polar H10'), findsOneWidget);

    await tester.tap(find.text('Polar H10'));
    await pumpUi(tester);
    expect(harness.platform.connected, ['sensor-1']);
  });

  testWidgets(
    'Bluetooth aus zeigt den Grund und den Weg in die Einstellungen',
    (tester) async {
      harness.platform.problem = BluetoothProblem.poweredOff;
      var opened = 0;
      harness.controller.openSettings = () async => opened++;
      await openSheet(tester);

      expect(
        find.text(bluetoothProblemText(BluetoothProblem.poweredOff)),
        findsOneWidget,
      );
      // Keine Suche anbieten, solange sie nicht funktionieren kann.
      expect(find.text('Gurt suchen'), findsNothing);
      await tester.tap(find.text('Einstellungen öffnen'));
      await tester.pump();
      expect(opened, 1);
      expect(harness.platform.scans, 0);
    },
  );

  testWidgets('nicht unterstütztes Bluetooth bietet keine Einstellungen an', (
    tester,
  ) async {
    harness.platform.problem = BluetoothProblem.unsupported;
    harness.controller.openSettings = () async {};
    await openSheet(tester);

    expect(
      find.text(bluetoothProblemText(BluetoothProblem.unsupported)),
      findsOneWidget,
    );
    expect(find.text('Einstellungen öffnen'), findsNothing);
  });

  testWidgets('Starten übernimmt Bereich und Aufwärmzeit', (tester) async {
    await openSheet(tester);

    await tester.enterText(
      find.byKey(const ValueKey('cardio-zone-low')),
      '125',
    );
    await tester.enterText(
      find.byKey(const ValueKey('cardio-zone-high')),
      '140',
    );
    await tester.tap(find.text('5'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('cardio-start')));
    await pumpUi(tester);

    expect(harness.controller.isRunning, isTrue);
    final config = harness.platform.started.single;
    expect((config.zoneLowBpm, config.zoneHighBpm), (125, 140));
    expect(config.warmupSeconds, 300);
    expect(find.text('Cardio starten'), findsNothing);
  });

  testWidgets('Sheet bei Textgröße 2 läuft nicht über', (tester) async {
    harness.platform.hasSensor = false;
    await openSheet(tester, textScale: 2);

    expect(tester.takeException(), isNull);
  });
}
