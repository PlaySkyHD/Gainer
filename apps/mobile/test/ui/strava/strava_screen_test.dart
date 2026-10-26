import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/strava/strava_service.dart';
import 'package:gainer_mobile/ui/features/strava/strava_screen.dart';

import '../cardio/cardio_test_support.dart';
import '../training/training_test_support.dart';
import 'strava_test_support.dart';

void main() {
  Future<void> open(
    WidgetTester tester,
    FakeStravaService service, {
    bool online = true,
    double textScale = 1,
  }) async {
    phoneSize(tester);
    await tester.pumpWidget(
      trainingTestApp(
        textScale: textScale,
        home: StravaScreen(service: service, online: online),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('verbindet und zeigt danach die Arten, Kraft standardmäßig aus', (
    tester,
  ) async {
    final service = FakeStravaService(stravaStatus(connected: false));
    await open(tester, service);
    expect(find.text('Mit Strava verbinden'), findsOneWidget);
    expect(find.text('Cardio-Einheiten'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('strava-connect')));
    await tester.pumpAndSettle();

    expect(service.connects, 1);
    expect(find.text('Verbunden als Nic M'), findsOneWidget);
    final cardio = tester.widget<CupertinoSwitch>(
      find.byKey(const ValueKey('strava-export-cardio')),
    );
    final strength = tester.widget<CupertinoSwitch>(
      find.byKey(const ValueKey('strava-export-strength')),
    );
    expect(cardio.value, isTrue);
    expect(strength.value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('schaltet Krafttraining ein und speichert beide Arten', (
    tester,
  ) async {
    final service = FakeStravaService(stravaStatus());
    await open(tester, service);

    await tester.tap(find.byKey(const ValueKey('strava-export-strength')));
    await tester.pumpAndSettle();

    expect(service.settings, [(true, true)]);
    expect(
      tester
          .widget<CupertinoSwitch>(
            find.byKey(const ValueKey('strava-export-strength')),
          )
          .value,
      isTrue,
    );
  });

  testWidgets('sperrt beide Schalter, während ein Speichern läuft', (
    tester,
  ) async {
    final gate = Completer<void>();
    final service = FakeStravaService(stravaStatus())..settingsGate = gate;
    await open(tester, service);

    await tester.tap(find.byKey(const ValueKey('strava-export-cardio')));
    await tester.pump();

    CupertinoSwitch switchOf(String key) =>
        tester.widget<CupertinoSwitch>(find.byKey(ValueKey(key)));
    expect(switchOf('strava-export-cardio').onChanged, isNull);
    expect(switchOf('strava-export-strength').onChanged, isNull);

    gate.complete();
    await tester.pumpAndSettle();

    expect(switchOf('strava-export-strength').onChanged, isNotNull);
  });

  testWidgets('setzt den Schalter zurück, wenn Speichern scheitert', (
    tester,
  ) async {
    final service = FakeStravaService(stravaStatus())..failSettings = true;
    await open(tester, service);

    await tester.tap(find.byKey(const ValueKey('strava-export-cardio')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<CupertinoSwitch>(
            find.byKey(const ValueKey('strava-export-cardio')),
          )
          .value,
      isTrue,
    );
    expect(
      find.text('Die Einstellung konnte nicht gespeichert werden.'),
      findsOneWidget,
    );
  });

  testWidgets('erklärt fehlendes Upload-Recht', (tester) async {
    final service = FakeStravaService(stravaStatus(connected: false))
      ..connectResult = StravaConnectResult.denied;
    await open(tester, service);

    await tester.tap(find.byKey(const ValueKey('strava-connect')));
    await tester.pumpAndSettle();

    expect(
      find.text('Gainer braucht das Recht, Aktivitäten hochzuladen.'),
      findsOneWidget,
    );
    expect(find.text('Cardio-Einheiten'), findsNothing);
  });

  testWidgets('Abbruch im Sheet zeigt keinen Fehler', (tester) async {
    final service = FakeStravaService(stravaStatus(connected: false))
      ..connectResult = StravaConnectResult.cancelled;
    await open(tester, service);

    await tester.tap(find.byKey(const ValueKey('strava-connect')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('strava-error')), findsNothing);
  });

  testWidgets('abgelaufene Verbindung bietet erneutes Verbinden an', (
    tester,
  ) async {
    final service = FakeStravaService(stravaStatus(needsReconnect: true));
    await open(tester, service);

    expect(find.text('Erneut verbinden'), findsOneWidget);
    expect(find.textContaining('Strava-Verbindung abgelaufen'), findsOneWidget);
  });

  testWidgets('trennt nach Bestätigung', (tester) async {
    final service = FakeStravaService(stravaStatus());
    await open(tester, service);

    await tester.tap(find.byKey(const ValueKey('strava-disconnect')));
    await tester.pumpAndSettle();
    expect(find.text('Strava trennen?'), findsOneWidget);
    await tester.tap(find.text('Trennen'));
    await tester.pumpAndSettle();

    expect(service.disconnects, 1);
    expect(find.text('Mit Strava verbinden'), findsOneWidget);
  });

  testWidgets('ohne Server-Konfiguration ist Verbinden nicht möglich', (
    tester,
  ) async {
    final service = FakeStravaService(
      stravaStatus(configured: false, connected: false),
    );
    await open(tester, service);

    await tester.tap(find.text('Mit Strava verbinden'));
    await tester.pumpAndSettle();
    expect(service.connects, 0);
    expect(find.textContaining('noch nicht eingerichtet'), findsOneWidget);
  });

  testWidgets('offline keine Aktion und ein Grund', (tester) async {
    final service = FakeStravaService(stravaStatus(connected: false));
    await open(tester, service, online: false);

    await tester.tap(find.text('Mit Strava verbinden'));
    await tester.pumpAndSettle();
    expect(service.connects, 0);
    expect(
      find.text('Strava lässt sich nur mit Verbindung verwalten.'),
      findsOneWidget,
    );
  });

  testWidgets('läuft bei Textgröße 2 nicht über', (tester) async {
    await open(tester, FakeStravaService(stravaStatus()), textScale: 2);
    expect(tester.takeException(), isNull);
  });

  test('liest die Rückleitung des Servers', () {
    expect(
      ApiStravaService.parseCallback(
        Uri.parse('gainer://strava?result=connected'),
      ),
      StravaConnectResult.connected,
    );
    expect(
      ApiStravaService.parseCallback(
        Uri.parse('gainer://strava?result=denied'),
      ),
      StravaConnectResult.denied,
    );
    expect(
      ApiStravaService.parseCallback(
        Uri.parse('gainer://other?result=connected'),
      ),
      StravaConnectResult.failed,
    );
    expect(
      ApiStravaService.parseCallback(Uri.parse('gainer://strava')),
      StravaConnectResult.failed,
    );
  });
}
