import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_session.dart';
import 'package:gainer_mobile/ui/core/theme.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_detail_screen.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_live_screen.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_running_card.dart';

import '../training/training_test_support.dart';
import 'cardio_test_support.dart';

void main() {
  late CardioHarness harness;
  final t0 = DateTime.utc(2026, 10, 18, 10);

  setUp(() async {
    harness = await CardioHarness.create(now: t0);
  });

  tearDown(() async => harness.dispose());

  /// Startet eine Einheit mit Zielbereich 125–140 und liest den Puls [bpm].
  Future<void> startRunning(
    WidgetTester tester, {
    int? bpm,
    Duration after = const Duration(seconds: 90),
  }) async {
    await tester.runAsync(() async {
      await harness.controller.start(
        zone: const CardioTargetZone(lowBpm: 125, highBpm: 140),
      );
      harness.now = t0.add(after);
      harness.platform.latestBpm = bpm;
      harness.platform.latestAt = harness.now;
      await harness.controller.poll();
    });
  }

  Future<void> openLive(WidgetTester tester, {double textScale = 1}) async {
    phoneSize(tester);
    await tester.pumpWidget(
      trainingTestApp(
        textScale: textScale,
        home: Builder(
          builder: (context) => CupertinoPageScaffold(
            child: Center(
              child: CupertinoButton(
                onPressed: () => openCardioLive(context, harness.feature),
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

  String stateLabel(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('cardio-live-state')))
      .data!;

  Color? stateColor(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('cardio-live-state')))
      .style
      ?.color;

  testWidgets('im Zielbereich: Puls, grüner Status, Kennzahlen', (
    tester,
  ) async {
    await startRunning(tester, bpm: 130);
    await openLive(tester);

    expect(find.text('Rad-Ergometer'), findsWidgets);
    expect(find.text('130'), findsOneWidget);
    expect(stateLabel(tester), 'Im Zielbereich');
    expect(stateColor(tester), GainerStatusColors.success(Brightness.light));
    expect(find.text('Ziel'), findsOneWidget);
    expect(find.text('125–140 bpm'), findsOneWidget);
    expect(find.text('01:30'), findsOneWidget);
    expect(find.text('Polar H10'), findsOneWidget);
    expect(find.text('Verbunden · Akku 80\u00A0%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zu hoch ist rot, zu niedrig blau', (tester) async {
    await startRunning(tester, bpm: 150);
    await openLive(tester);
    expect(stateLabel(tester), 'Zu hoch');
    expect(stateColor(tester), GainerColors.light.destructive);

    harness.platform.latestBpm = 100;
    harness.platform.latestAt = harness.now;
    await tester.runAsync(harness.controller.poll);
    await tester.pump();
    expect(stateLabel(tester), 'Zu niedrig');
    expect(find.text('100'), findsOneWidget);
    expect(stateColor(tester), GainerStatusColors.info(Brightness.light));
  });

  testWidgets('ohne Signal steht ein Strich und „Kein Signal“', (tester) async {
    await startRunning(tester);
    await openLive(tester);

    expect(find.text('–'), findsWidgets);
    expect(stateLabel(tester), 'Kein Signal');
    expect(stateColor(tester), GainerColors.light.secondaryText);
  });

  testWidgets('ohne Gurt steht „Kein Gurt“ und der Hinweis', (tester) async {
    harness.platform
      ..hasSensor = false
      ..connection = HeartRateConnectionState.idle;
    await startRunning(tester);
    await openLive(tester);

    expect(stateLabel(tester), 'Kein Gurt');
    expect(find.text('Kein Gurt'), findsWidgets);
    expect(find.text('Es wird kein Puls erfasst.'), findsOneWidget);
  });

  testWidgets('die Dauer läuft jede Sekunde weiter', (tester) async {
    await startRunning(tester, bpm: 130, after: const Duration(seconds: 10));
    await openLive(tester);
    expect(find.text('00:10'), findsOneWidget);

    harness.now = t0.add(const Duration(seconds: 12));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('00:12'), findsOneWidget);
  });

  testWidgets('Zielbereich ändern gilt sofort', (tester) async {
    await startRunning(tester, bpm: 130);
    await openLive(tester);

    await tester.tap(find.byKey(const ValueKey('cardio-live-zone')));
    await pumpUi(tester);
    expect(find.text('Zielbereich ändern'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('cardio-zone-high')),
      '150',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('cardio-zone-save')));
    await pumpUi(tester);

    expect(harness.controller.active!.targetZone!.highBpm, 150);
    expect(find.text('125–150 bpm'), findsOneWidget);
    expect(harness.platform.updated.single.zoneHighBpm, 150);
  });

  testWidgets('unter 60 s fragt Beenden nach Verwerfen oder Speichern', (
    tester,
  ) async {
    await startRunning(tester, bpm: 130, after: const Duration(seconds: 40));
    await openLive(tester);

    await tester.tap(find.byKey(const ValueKey('cardio-finish')));
    await pumpUi(tester);
    expect(find.text('Sehr kurze Einheit'), findsOneWidget);
    expect(inDialog('Speichern'), findsOneWidget);
    expect(inDialog('Verwerfen'), findsOneWidget);
    expect(inDialog('Abbrechen'), findsOneWidget);

    await tester.tap(inDialog('Abbrechen'));
    await pumpUi(tester);
    expect(harness.controller.isRunning, isTrue);

    await tester.tap(find.byKey(const ValueKey('cardio-finish')));
    await pumpUi(tester);
    await tester.tap(inDialog('Verwerfen'));
    await pumpUi(tester);
    await pumpUi(tester);
    expect(harness.controller.isRunning, isFalse);
    expect(find.byType(CardioLiveScreen), findsNothing);
    expect(await tester.runAsync(harness.repository.readSessions), isEmpty);
  });

  testWidgets('kurze Einheit lässt sich speichern und öffnet das Detail', (
    tester,
  ) async {
    await startRunning(tester, bpm: 130, after: const Duration(seconds: 40));
    await openLive(tester);

    await tester.tap(find.byKey(const ValueKey('cardio-finish')));
    await pumpUi(tester);
    await tester.tap(inDialog('Speichern'));
    await pumpUi(tester);

    expect(find.byType(CardioDetailScreen), findsOneWidget);
    final saved = await tester.runAsync(harness.repository.readSessions);
    expect(saved, hasLength(1));
  });

  testWidgets('ab 60 s bestätigt Beenden und öffnet das Detail', (
    tester,
  ) async {
    await startRunning(tester, bpm: 130, after: const Duration(minutes: 5));
    await openLive(tester);

    await tester.tap(find.byKey(const ValueKey('cardio-finish')));
    await pumpUi(tester);
    expect(find.text('Einheit beenden?'), findsOneWidget);
    expect(inDialog('Verwerfen'), findsNothing);
    await tester.tap(inDialog('Beenden'));
    await pumpUi(tester);

    expect(harness.controller.isRunning, isFalse);
    expect(find.byType(CardioDetailScreen), findsOneWidget);
    expect(find.text('Kennzahlen'), findsOneWidget);
  });

  testWidgets('laufende Karte zeigt Zeit und Puls', (tester) async {
    await startRunning(tester, bpm: 131, after: const Duration(seconds: 754));
    phoneSize(tester);
    var opened = 0;
    await tester.pumpWidget(
      trainingTestApp(
        home: CupertinoPageScaffold(
          child: CardioRunningCard(
            session: harness.controller,
            onOpen: () => opened++,
          ),
        ),
      ),
    );

    expect(find.text('Cardio läuft · 12:34 · 131 bpm'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cardio-running-card')));
    expect(opened, 1);
  });

  testWidgets('Live-Ansicht bei Textgröße 2 läuft nicht über', (tester) async {
    await startRunning(tester, bpm: 188, after: const Duration(hours: 1));
    await openLive(tester, textScale: 2);

    expect(tester.takeException(), isNull);
  });
}
