import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/api/strava_api_models.dart';
import 'package:gainer_mobile/data/models/local/local_aggregate.dart';
import 'package:gainer_mobile/data/models/local/local_mutation.dart';
import 'package:gainer_mobile/data/repositories/cardio/cardio_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_session.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_detail_screen.dart';

import '../strava/strava_test_support.dart';
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
    expect(find.text('0:20 min'), findsOneWidget);
    expect(find.text('Ø-Puls'), findsOneWidget);
    expect(find.text('128,5 bpm'), findsOneWidget);
    expect(find.text('Max-Puls'), findsOneWidget);
    expect(find.text('141 bpm'), findsOneWidget);
    expect(find.text('Im Zielbereich'), findsOneWidget);
    expect(find.text('0:10 min (50 %)'), findsOneWidget);
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

  /// Wie nach dem Sync: der Server kennt die Einheit in Version 1.
  Future<void> markSynced(WidgetTester tester, CardioSession session) async {
    await tester.runAsync(
      () => harness.store.commitMutation(
        MutationDraft(
          mutationId: '00000000-0000-4000-8000-000000000900',
          aggregateType: cardioSessionAggregateType,
          aggregateId: session.sessionId,
          operation: LocalMutationOperation.update,
          baseVersion: 1,
          body: session.toJson(),
          envelope: LocalAggregateEnvelope<Object?>(
            aggregateId: session.sessionId,
            serverSnapshot: session.toJson(),
            workingCopy: session.toJson(),
            serverVersion: 1,
            optimisticVersion: 2,
            syncState: LocalSyncState.pending,
          ),
          createdAtUtc: harness.now,
        ),
      ),
    );
  }

  testWidgets('sendet eine synchronisierte Einheit an Strava', (tester) async {
    final session = await seedSmall(tester);
    await markSynced(tester, session);
    final strava = FakeStravaService(stravaStatus())
      ..requestedStatus = StravaExportStatus.processing;
    harness.strava = strava;
    await openDetail(tester, session.sessionId);

    final row = find.byKey(const ValueKey('cardio-strava-export'));
    await scrollIntoView(tester, row);
    expect(find.text('An Strava senden'), findsOneWidget);
    await tester.tap(row);
    await tester.pump();
    await tester.pump();

    expect(strava.requested, [session.sessionId]);
    expect(find.text('Wird an Strava gesendet'), findsOneWidget);

    strava.exports[session.sessionId] = const ApiStravaExport(
      status: StravaExportStatus.completed,
      activityId: 9001,
      errorCode: null,
    );
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    expect(find.text('An Strava gesendet'), findsOneWidget);
  });

  testWidgets('ohne Sync oder ohne Strava-Verbindung keine Strava-Zeile', (
    tester,
  ) async {
    final session = await seedSmall(tester);
    harness.strava = FakeStravaService(stravaStatus());
    await openDetail(tester, session.sessionId);
    expect(find.text('Strava'), findsNothing);

    await markSynced(tester, session);
    harness.strava = FakeStravaService(stravaStatus(connected: false));
    await openDetail(tester, session.sessionId);
    await pumpUi(tester);
    expect(find.text('Strava'), findsNothing);
  });

  testWidgets('fehlgeschlagener Export bietet erneutes Senden an', (
    tester,
  ) async {
    final session = await seedSmall(tester);
    await markSynced(tester, session);
    harness.strava = FakeStravaService(stravaStatus())
      ..exports[session.sessionId] = const ApiStravaExport(
        status: StravaExportStatus.failed,
        activityId: null,
        errorCode: 'strava_upload_error',
      );
    await openDetail(tester, session.sessionId, textScale: 2);

    final row = find.byKey(const ValueKey('cardio-strava-export'));
    await scrollIntoView(tester, row);
    expect(find.text('Erneut an Strava senden'), findsOneWidget);
    expect(find.textContaining('nicht angenommen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
