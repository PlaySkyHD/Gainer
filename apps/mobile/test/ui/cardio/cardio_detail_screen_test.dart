import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_session.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_detail_screen.dart';

import '../training/training_test_support.dart';
import 'cardio_test_support.dart';

void main() {
  late CardioHarness harness;

  setUp(() async {
    harness = await CardioHarness.create();
  });

  tearDown(() async => harness.dispose());

  /// Fünf Werte mit Lücke: Ø 128,5 bpm, Max 141 bpm, 10 s im Zielbereich.
  Future<CardioSession> seedSmall(WidgetTester tester) async {
    final session = await tester.runAsync(
      () => harness.seedSession(
        start: DateTime(2026, 10, 18, 10, 15).toUtc(),
        length: const Duration(seconds: 20),
        heartRate: const [118, 125, 0, 141, 130],
      ),
    );
    return session!;
  }

  Future<void> openDetail(
    WidgetTester tester,
    String sessionId, {
    Brightness brightness = Brightness.light,
    double textScale = 1,
  }) async {
    phoneSize(tester, height: 1400);
    await tester.pumpWidget(
      trainingTestApp(
        brightness: brightness,
        textScale: textScale,
        home: CardioDetailScreen(
          feature: harness.feature,
          sessionId: sessionId,
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('zeigt Kennzahlen deutsch formatiert und beschriftet', (
    tester,
  ) async {
    final session = await seedSmall(tester);
    await openDetail(tester, session.sessionId);

    expect(find.text('Rad-Ergometer'), findsWidgets);
    expect(find.text('So, 18. Okt. · 10:15 Uhr'), findsOneWidget);
    expect(find.text('Dauer'), findsOneWidget);
    expect(find.text('00:20 min'), findsOneWidget);
    expect(find.text('Ø-Puls'), findsOneWidget);
    expect(find.text('128,5 bpm'), findsOneWidget);
    expect(find.text('Max-Puls'), findsOneWidget);
    expect(find.text('141 bpm'), findsOneWidget);
    expect(find.text('Im Zielbereich'), findsOneWidget);
    expect(find.text('00:10 min (50 %)'), findsOneWidget);
    expect(find.text('Zielbereich 120–140 bpm'), findsOneWidget);
    // Keine RR-Werte, also keine HRV und keine Fußnote.
    expect(find.text('HRV (RMSSD)'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('HRV erscheint mit Fußnote, wenn RR-Werte reichen', (
    tester,
  ) async {
    final session = await tester.runAsync(
      () => harness.seedSession(
        start: DateTime(2026, 10, 18, 10).toUtc(),
        rr: [for (var i = 0; i < 60; i++) i.isEven ? 800 : 820],
      ),
    );
    await openDetail(tester, session!.sessionId);

    expect(find.text('HRV (RMSSD)'), findsOneWidget);
    expect(find.text('20 ms'), findsOneWidget);
    expect(
      find.textContaining('Während Belastung niedriger als in Ruhe'),
      findsOneWidget,
    );
  });

  testWidgets('Ergometerwerte lassen sich nachtragen', (tester) async {
    final session = await seedSmall(tester);
    await openDetail(tester, session.sessionId);
    expect(find.text('–'), findsNWidgets(3));

    await tester.tap(find.byKey(const ValueKey('cardio-edit-ergometer')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('cardio-field-distance')),
      '14,2',
    );
    await tester.enterText(
      find.byKey(const ValueKey('cardio-field-power')),
      '165',
    );
    await tester.tap(find.byKey(const ValueKey('cardio-ergometer-save')));
    await settle(tester);

    expect(find.text('14,2 km'), findsOneWidget);
    expect(find.text('165 W'), findsOneWidget);
    final stored = await tester.runAsync(
      () => harness.repository.readSession(session.sessionId),
    );
    expect(stored!.distanceKm, 14.2);
    expect(stored.averagePowerWatts, 165);
    expect(stored.energyKcal, isNull);
  });

  testWidgets('ungültige Ergometerwerte zeigen einen Fehler', (tester) async {
    final session = await seedSmall(tester);
    await openDetail(tester, session.sessionId);

    await tester.tap(find.byKey(const ValueKey('cardio-edit-ergometer')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('cardio-field-power')),
      '5000',
    );
    await tester.tap(find.byKey(const ValueKey('cardio-ergometer-save')));
    await settle(tester);

    expect(find.text('Erlaubt sind 0 bis 3.000 W.'), findsOneWidget);
    expect(find.text('Ergometer-Werte'), findsOneWidget);
  });

  testWidgets('Notiz lässt sich bearbeiten', (tester) async {
    final session = await seedSmall(tester);
    await openDetail(tester, session.sessionId);
    expect(find.text('Notiz hinzufügen'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cardio-edit-notes')));
    await settle(tester);
    await tester.enterText(find.byType(CupertinoTextField), 'Locker gefahren');
    await tester.tap(find.text('Fertig'));
    await settle(tester);

    expect(find.text('Locker gefahren'), findsOneWidget);
    final stored = await tester.runAsync(
      () => harness.repository.readSession(session.sessionId),
    );
    expect(stored!.notes, 'Locker gefahren');
  });

  testWidgets('Apple Health sichern zeigt danach den Stand', (tester) async {
    final session = await seedSmall(tester);
    await openDetail(tester, session.sessionId);

    expect(find.text('In Apple Health gesichert'), findsNothing);
    await tester.tap(find.text('In Apple Health sichern'));
    await settle(tester);

    expect(harness.health.exports, 1);
    expect(find.text('In Apple Health gesichert'), findsOneWidget);
    expect(find.text('In Apple Health sichern'), findsNothing);
  });

  testWidgets('fehlende Health-Berechtigung zeigt einen Hinweis', (
    tester,
  ) async {
    harness.health.failure = StateError('not authorized');
    final session = await seedSmall(tester);
    await openDetail(tester, session.sessionId);

    await tester.tap(find.text('In Apple Health sichern'));
    await settle(tester);

    expect(find.textContaining('Datenzugriff'), findsOneWidget);
    expect(find.text('In Apple Health sichern'), findsOneWidget);
  });

  testWidgets('Löschen fragt nach und entfernt die Einheit', (tester) async {
    final session = await seedSmall(tester);
    phoneSize(tester);
    await tester.pumpWidget(
      trainingTestApp(
        home: Builder(
          builder: (context) => CupertinoPageScaffold(
            child: CupertinoButton(
              onPressed: () =>
                  openCardioDetail(context, harness.feature, session.sessionId),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);

    await tester.tap(find.byIcon(CupertinoIcons.trash));
    await settle(tester);
    expect(find.text('Einheit löschen?'), findsOneWidget);
    await tester.tap(inDialog('Abbrechen'));
    await settle(tester);
    expect(find.byType(CardioDetailScreen), findsOneWidget);

    await tester.tap(find.byIcon(CupertinoIcons.trash));
    await settle(tester);
    await tester.tap(inDialog('Löschen'));
    await settle(tester);

    expect(find.byType(CardioDetailScreen), findsNothing);
    expect(await tester.runAsync(harness.repository.readSessions), isEmpty);
  });

  testWidgets('Einheit ohne Pulssignal zeigt statt Kurve einen Hinweis', (
    tester,
  ) async {
    final session = await tester.runAsync(
      () => harness.seedSession(
        start: DateTime(2026, 10, 18, 10).toUtc(),
        length: const Duration(minutes: 10),
        heartRate: List.filled(121, 0),
      ),
    );
    await openDetail(tester, session!.sessionId);

    expect(find.text('Kein Puls erfasst'), findsOneWidget);
    expect(find.text('Ø-Puls'), findsOneWidget);
    expect(find.text('–'), findsWidgets);
  });

  testWidgets('bei Textgröße 2 läuft nichts über', (tester) async {
    final session = await seedSmall(tester);
    await openDetail(tester, session.sessionId, textScale: 2);

    expect(tester.takeException(), isNull);
  });
}
