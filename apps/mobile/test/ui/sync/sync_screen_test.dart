import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/api/sync_api_models.dart';
import 'package:gainer_mobile/data/models/local/local_mutation.dart';
import 'package:gainer_mobile/data/repositories/sync/local_conflict_recovery.dart';
import 'package:gainer_mobile/data/repositories/sync/sync_repository.dart';
import 'package:gainer_mobile/data/services/local/pending_handover_secret_store.dart';
import 'package:gainer_mobile/ui/core/theme.dart';
import 'package:gainer_mobile/ui/features/sync/sync_screen.dart';

void main() {
  testWidgets('source handover reveals its one-time code after confirmation', (
    tester,
  ) async {
    String? clipboardText;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardText = (call.arguments as Map)['text'] as String?;
        return null;
      }
      if (call.method == 'Clipboard.getData') return {'text': clipboardText};
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sync = _SyncActions();
    await tester.pumpWidget(
      CupertinoApp(
        theme: GainerTheme.light,
        home: SyncScreen(
          sync: sync,
          isOnline: true,
          accountId: 'a1234567-1234-4234-8234-123456789abc',
          apiOrigin: 'https://gainer.markfort.xyz',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dieses Gerät ablösen'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Lokale Schreibzugriffe werden angehalten. Nur das neue Gerät kann nach erfolgreichem Abschluss wieder schreiben.',
      ),
      findsOneWidget,
    );
    expect(find.text('one_time-code-123'), findsNothing);
    await tester.tap(find.text('Übergabe starten'));
    await tester.pumpAndSettle();

    expect(find.text('Übergabedaten'), findsOneWidget);
    expect(find.textContaining('one_time-code-123'), findsOneWidget);
    expect(sync.lastRequestId, matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(sync.pending?.phase, 'sourceBegan');
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Übergabedaten kopieren'));
    await tester.tap(find.text('Übergabedaten kopieren'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Es wird in die Zwischenablage kopiert'),
      findsOneWidget,
    );
    await tester.tap(find.text('Kopieren'));
    await tester.pumpAndSettle();
    expect(clipboardText, contains('gainer-sync-handover'));
  });

  testWidgets('popping during a pending handover stops follow-up view work', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sync = _SyncActions()
      ..beginGate = Completer<BeginSyncHandoverResponse>();
    await tester.pumpWidget(
      CupertinoApp(
        theme: GainerTheme.light,
        home: Builder(
          builder: (context) => CupertinoPageScaffold(
            child: Center(
              child: CupertinoButton(
                onPressed: () => Navigator.of(context).push(
                  CupertinoPageRoute<void>(
                    builder: (_) => SyncScreen(
                      sync: sync,
                      isOnline: true,
                      accountId: 'a1234567-1234-4234-8234-123456789abc',
                      apiOrigin: 'https://gainer.markfort.xyz',
                    ),
                  ),
                ),
                child: const Text('Open Sync'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open Sync'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dieses Gerät ablösen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Übergabe starten'));
    await tester.pumpAndSettle();
    expect(sync.beginCalls, 1);

    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    sync.beginGate!.complete(
      BeginSyncHandoverResponse(
        handoverId: 'c1234567-1234-4234-8234-123456789abc',
        oneTimeCode: 'one_time-code-123',
        frozenRevision: 41,
        expiresAtUtc: DateTime.now().toUtc().add(const Duration(hours: 1)),
      ),
    );
    await tester.pump();

    expect(sync.pendingReads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expired target handover offers explicit local recovery', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sync = _SyncActions()
      ..pending = PendingHandoverRecord(
        apiOrigin: 'https://gainer.markfort.xyz',
        accountId: 'a1234567-1234-4234-8234-123456789abc',
        requestId: 'd1234567-1234-4234-8234-123456789abc',
        sourceClientId: 'b1234567-1234-4234-8234-123456789abc',
        targetClientId: 'target-client',
        handoverId: 'c1234567-1234-4234-8234-123456789abc',
        phase: 'targetCompletePending',
        frozenRevision: 41,
        expiresAtUtc: DateTime.now().toUtc().subtract(
          const Duration(minutes: 1),
        ),
        oneTimeCode: 'one_time-code-123',
      );
    await tester.pumpWidget(
      CupertinoApp(
        theme: GainerTheme.light,
        home: SyncScreen(
          sync: sync,
          isOnline: true,
          accountId: 'a1234567-1234-4234-8234-123456789abc',
          apiOrigin: 'https://gainer.markfort.xyz',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nach Serverprüfung lokal freigeben'), findsOneWidget);

    await tester.tap(find.text('Nach Serverprüfung lokal freigeben'));
    await tester.pumpAndSettle();

    expect(sync.recoveryCalls, 1);
    expect(
      find.textContaining('Dieses Gerät bleibt schreibgeschützt'),
      findsOneWidget,
    );
  });

  testWidgets(
    'handover requires confirmation and submits the full source bundle',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final sync = _SyncActions();
      final expiry = DateTime.now().toUtc().add(const Duration(hours: 1));
      await tester.pumpWidget(
        CupertinoApp(
          theme: GainerTheme.light,
          home: SyncScreen(
            sync: sync,
            isOnline: true,
            accountId: 'a1234567-1234-4234-8234-123456789abc',
            apiOrigin: 'https://gainer.markfort.xyz',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Dieses Gerät ablösen'), findsOneWidget);
      await tester.enterText(
        find.byType(CupertinoTextField).at(0),
        '{"kind":"gainer-sync-handover","version":1,"accountId":"a1234567-1234-4234-8234-123456789abc","apiOrigin":"https://gainer.markfort.xyz","sourceClientId":"b1234567-1234-4234-8234-123456789abc","handoverId":"c1234567-1234-4234-8234-123456789abc","oneTimeCode":"one_time-code-123","frozenRevision":41,"expiresAtUtc":"${expiry.toIso8601String()}"}',
      );
      tester.testTextInput.hide();
      await tester.pump();
      await tester.tap(find.text('Übergabedaten einfügen'));
      await tester.pump();
      await tester.ensureVisible(find.text('Gerätewechsel bestätigen'));
      await tester.tap(find.text('Gerätewechsel bestätigen'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Das neue Gerät übernimmt den Schreibzugriff. Das bisherige Gerät wird dabei abgelöst.',
        ),
        findsOneWidget,
      );
      expect(sync.completed, isNull);

      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
      expect(sync.completed, isNotNull);
      expect(
        sync.completed!.handoverId,
        'c1234567-1234-4234-8234-123456789abc',
      );
      expect(sync.completed!.oneTimeCode, 'one_time-code-123');
      expect(
        sync.completed!.sourceClientId,
        'b1234567-1234-4234-8234-123456789abc',
      );
      expect(sync.completed!.frozenRevision, 41);
      expect(sync.completed!.expiresAtUtc, expiry);
    },
  );

  testWidgets('conflict resolution is explicit and shows destructive warning', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sync = _SyncActions()
      ..conflicts = [
        LocalConflictRecord(
          conflictId: 'conflict-1',
          aggregateType: 'daily-check-in',
          aggregateId: 'resource-1',
          createdAtUtc: DateTime.utc(2026, 10, 12),
          code: 'version_conflict',
          detail: {'message': 'Neue Serverversion vorhanden.'},
        ),
      ]
      ..infos = {
        'conflict-1': _info(title: '2026-10-12', hasServerState: true),
      };
    await tester.pumpWidget(_app(sync));
    await tester.pumpAndSettle();
    expect(find.text('Check-in · 2026-10-12'), findsOneWidget);
    expect(
      find.textContaining('Auf dem Server gibt es eine neuere Version'),
      findsOneWidget,
    );

    await tester.tap(find.text('Check-in · 2026-10-12'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Serverstand nutzen'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Die ausstehenden lokalen Änderungen dieses Eintrags werden verworfen und durch den letzten Serverstand ersetzt.',
      ),
      findsOneWidget,
    );
    expect(sync.acceptedConflictIds, isEmpty);
    await tester.tap(find.text('Serverstand nutzen').last);
    await tester.pumpAndSettle();
    expect(sync.acceptedConflictIds, ['conflict-1']);
  });

  testWidgets('source handover reveals the one-time code only on request', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sync = _SyncActions()
      ..pending = PendingHandoverRecord(
        apiOrigin: 'https://gainer.markfort.xyz',
        accountId: 'a1234567-1234-4234-8234-123456789abc',
        requestId: 'd1234567-1234-4234-8234-123456789abc',
        sourceClientId: 'b1234567-1234-4234-8234-123456789abc',
        targetClientId: 'target-client',
        handoverId: 'c1234567-1234-4234-8234-123456789abc',
        phase: 'sourceBegan',
        frozenRevision: 41,
        expiresAtUtc: DateTime.now().toUtc().add(const Duration(hours: 1)),
        oneTimeCode: 'one_time-code-123',
      );
    await tester.pumpWidget(
      CupertinoApp(
        theme: GainerTheme.light,
        home: SyncScreen(
          sync: sync,
          isOnline: true,
          accountId: 'a1234567-1234-4234-8234-123456789abc',
          apiOrigin: 'https://gainer.markfort.xyz',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('one_time-code-123'), findsNothing);

    await tester.tap(find.text('Einmalcode'));
    await tester.pumpAndSettle();
    expect(find.text('Einmalcode anzeigen'), findsOneWidget);
    expect(find.textContaining('one_time-code-123'), findsOneWidget);
  });

  testWidgets('local retry conflict action asks before resubmitting', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sync = _SyncActions()
      ..conflicts = [
        LocalConflictRecord(
          conflictId: 'conflict-2',
          aggregateType: 'workout',
          aggregateId: 'workout-7',
          createdAtUtc: DateTime.utc(2026, 10, 12),
          code: 'version_conflict',
          detail: {'message': 'Neue Serverversion vorhanden.'},
        ),
      ]
      ..infos = {'conflict-2': _info(title: 'Push', hasServerState: true)};
    await tester.pumpWidget(_app(sync));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Training · Push'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lokale Änderung erneut senden'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Die ausstehende lokale Änderung wird mit einer neuen sicheren Änderungs-ID gegen die aktuelle Serverversion gesendet. Der Vorgang kann erneut abgelehnt werden.',
      ),
      findsOneWidget,
    );
    expect(sync.retriedConflictIds, isEmpty);

    await tester.tap(find.text('Erneut senden'));
    await tester.pumpAndSettle();
    expect(sync.retriedConflictIds, ['conflict-2']);
  });

  testWidgets(
    'conflict row names the resource and the reason; no server copy',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final sync = _SyncActions()
        ..conflicts = [
          _conflict('c-1', 'workout', 'active_workout_exists'),
          _conflict('c-2', 'workout', 'validation_failed'),
          _conflict('c-3', 'custom-exercise', 'validation_failed'),
          _conflict('c-4', 'training-plan', 'resource_not_found'),
          _conflict('c-5', 'unknown-type', 'something_else'),
        ]
        ..infos = {
          'c-1': _info(title: 'Push · 17.10.2026'),
          'c-2': _info(title: 'Pull · 16.10.2026'),
          'c-3': _info(title: 'Rudern'),
          'c-4': _info(title: 'Plan A'),
        };
      await tester.pumpWidget(_app(sync));
      await tester.pumpAndSettle();

      expect(find.text('Training · Push · 17.10.2026'), findsOneWidget);
      expect(
        find.textContaining('Ein anderes Training war noch aktiv'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Übung oder Plan fehlt auf dem Server'),
        findsOneWidget,
      );
      expect(find.text('Übung · Rudern'), findsOneWidget);
      expect(
        find.textContaining('Der Server hat die Daten abgelehnt'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Auf dem Server nicht gefunden'),
        findsOneWidget,
      );
      expect(find.text('Eintrag · aaaaaaaa'), findsOneWidget);
      expect(
        find.textContaining('Der Server hat die Änderung abgelehnt'),
        findsOneWidget,
      );

      await tester.tap(find.text('Training · Push · 17.10.2026'));
      await tester.pumpAndSettle();
      expect(find.text('Lokalen Stand erzwingen'), findsOneWidget);
      expect(find.text('Serverstand nutzen'), findsNothing);
      expect(find.text('Lokale Änderung erneut senden'), findsNothing);
    },
  );

  testWidgets('forcing one conflict asks first, then forces and syncs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sync = _SyncActions()
      ..conflicts = [_conflict('c-1', 'workout', 'active_workout_exists')]
      ..infos = {'c-1': _info(title: 'Push')};
    await tester.pumpWidget(_app(sync));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Training · Push'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lokalen Stand erzwingen'));
    await tester.pumpAndSettle();
    expect(find.text('Lokalen Stand erzwingen?'), findsOneWidget);
    expect(find.textContaining('überschrieben'), findsOneWidget);
    expect(sync.forcedConflictIds, isEmpty);

    await tester.tap(find.text('Erzwingen'));
    await tester.pumpAndSettle();
    expect(sync.forcedConflictIds, ['c-1']);
    expect(sync.synchronizeCalls, 1);
    expect(
      find.text('Lokaler Stand erzwungen und synchronisiert.'),
      findsOneWidget,
    );
    expect(find.text('Keine ungelösten Konflikte'), findsOneWidget);
  });

  testWidgets('selection mode forces all selected conflicts in send order', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sync = _SyncActions()
      ..conflicts = [
        _conflict('c-workout', 'workout', 'validation_failed'),
        _conflict('c-exercise', 'custom-exercise', 'validation_failed'),
        _conflict('c-server', 'training-plan', 'stale_base_version'),
      ]
      ..infos = {
        'c-workout': _info(
          title: 'Push',
          queuedAt: DateTime.utc(2026, 10, 17, 9),
        ),
        'c-exercise': _info(
          title: 'Rudern',
          queuedAt: DateTime.utc(2026, 10, 17, 8),
        ),
        'c-server': _info(
          title: 'Plan A',
          hasServerState: true,
          canForce: false,
        ),
      };
    await tester.pumpWidget(_app(sync));
    await tester.pumpAndSettle();
    expect(find.text('Alle auswählen'), findsNothing);

    await tester.tap(find.text('Auswählen'));
    await tester.pumpAndSettle();
    expect(find.text('0 von 3 ausgewählt'), findsOneWidget);
    await tester.tap(find.text('Alle auswählen'));
    await tester.pumpAndSettle();
    expect(find.text('3 von 3 ausgewählt'), findsOneWidget);
    expect(find.text('Auswahl aufheben'), findsOneWidget);
    await tester.tap(find.text('Auswahl aufheben'));
    await tester.pumpAndSettle();
    expect(find.text('0 von 3 ausgewählt'), findsOneWidget);

    // Ohne Auswahl sind beide Sammelaktionen gesperrt.
    await tester.tap(find.byKey(const ValueKey('sync-force-selected')));
    await tester.pumpAndSettle();
    expect(find.text('Erzwingen'), findsNothing);

    await tester.tap(find.text('Training · Push'));
    await tester.tap(find.text('Übung · Rudern'));
    await tester.pumpAndSettle();
    expect(find.text('2 von 3 ausgewählt'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sync-force-selected')));
    await tester.pumpAndSettle();
    expect(
      find.text('Lokalen Stand für 2 Einträge erzwingen?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Erzwingen'));
    await tester.pumpAndSettle();

    expect(sync.forcedConflictIds, ['c-exercise', 'c-workout']);
    expect(sync.synchronizeCalls, 1);
    expect(find.text('Auswählen'), findsOneWidget);
  });

  testWidgets('selection accepts the server state only where a copy exists', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sync = _SyncActions()
      ..conflicts = [
        _conflict('c-a', 'workout', 'stale_base_version'),
        _conflict('c-b', 'workout', 'active_workout_exists'),
      ]
      ..infos = {
        'c-a': _info(title: 'A', hasServerState: true),
        'c-b': _info(title: 'B'),
      };
    await tester.pumpWidget(_app(sync));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Auswählen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alle auswählen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sync-accept-selected')));
    await tester.pumpAndSettle();
    expect(find.text('Serverstand übernehmen?'), findsOneWidget);
    await tester.tap(find.text('Serverstand nutzen'));
    await tester.pumpAndSettle();

    expect(sync.acceptedConflictIds, ['c-a']);
    expect(find.text('Auswählen'), findsOneWidget);
    expect(find.text('Training · B'), findsOneWidget);
    expect(find.text('Training · A'), findsNothing);
  });
}

ConflictResourceInfo _info({
  String? title,
  bool hasServerState = false,
  bool canForce = true,
  DateTime? queuedAt,
}) => ConflictResourceInfo(
  title: title,
  hasServerState: hasServerState,
  canForceLocal: canForce,
  firstQueuedAtUtc: queuedAt ?? DateTime.utc(2026, 10, 17, 8),
  firstSequence: 1,
);

LocalConflictRecord _conflict(String id, String type, String code) =>
    LocalConflictRecord(
      conflictId: id,
      aggregateType: type,
      aggregateId: 'aaaaaaaa-1234-4234-8234-123456789abc',
      createdAtUtc: DateTime.utc(2026, 10, 12),
      code: code,
      detail: {'message': 'abgelehnt'},
    );

Widget _app(MobileSyncActions sync) => CupertinoApp(
  theme: GainerTheme.light,
  home: SyncScreen(
    sync: sync,
    isOnline: true,
    accountId: 'a1234567-1234-4234-8234-123456789abc',
    apiOrigin: 'https://gainer.markfort.xyz',
  ),
);

class _SyncActions implements MobileSyncActions {
  List<LocalConflictRecord> conflicts = [];
  Map<String, ConflictResourceInfo> infos = {};
  final forcedConflictIds = <String>[];
  int synchronizeCalls = 0;
  List<String> acceptedConflictIds = [];
  CompleteHandoverInput? completed;
  PendingHandoverRecord? pending;
  String? lastRequestId;
  Completer<BeginSyncHandoverResponse>? beginGate;
  int beginCalls = 0;
  int pendingReads = 0;
  int recoveryCalls = 0;
  final retriedConflictIds = <String>[];

  @override
  Future<PendingHandoverRecord?> readPendingHandover() async {
    pendingReads++;
    return pending;
  }

  @override
  Future<BeginSyncHandoverResponse> beginHandover({
    required String requestId,
  }) async {
    beginCalls++;
    lastRequestId = requestId;
    if (beginGate != null) return beginGate!.future;
    final expiresAtUtc = DateTime.now().toUtc().add(const Duration(hours: 1));
    pending = PendingHandoverRecord(
      apiOrigin: 'https://gainer.markfort.xyz',
      accountId: 'a1234567-1234-4234-8234-123456789abc',
      requestId: requestId,
      sourceClientId: 'b1234567-1234-4234-8234-123456789abc',
      phase: 'sourceBegan',
      expiresAtUtc: expiresAtUtc,
      handoverId: 'c1234567-1234-4234-8234-123456789abc',
      frozenRevision: 41,
      oneTimeCode: 'one_time-code-123',
    );
    return BeginSyncHandoverResponse(
      handoverId: 'c1234567-1234-4234-8234-123456789abc',
      oneTimeCode: 'one_time-code-123',
      frozenRevision: 41,
      expiresAtUtc: expiresAtUtc,
    );
  }

  @override
  Future<CompleteSyncHandoverResponse> completeHandover({
    required String handoverId,
    required String oneTimeCode,
    required int frozenRevision,
    required String sourceClientId,
    required DateTime expiresAtUtc,
  }) async {
    completed = CompleteHandoverInput(
      handoverId: handoverId,
      oneTimeCode: oneTimeCode,
      sourceClientId: sourceClientId,
      frozenRevision: frozenRevision,
      expiresAtUtc: expiresAtUtc,
    );
    return CompleteSyncHandoverResponse(
      handoverId: handoverId,
      targetClientId: 'target-client',
      frozenRevision: frozenRevision,
      isActiveWriter: true,
      completedAtUtc: DateTime.utc(2026, 10, 12),
    );
  }

  @override
  Future<void> cancelHandover({required String handoverId}) async {}

  @override
  Future<bool> recoverExpiredTargetHandover() async {
    recoveryCalls++;
    pending = null;
    return false;
  }

  @override
  Future<List<LocalConflictRecord>> readConflicts() async => conflicts;

  @override
  Future<void> acceptConflictServerState(String conflictId) async {
    acceptedConflictIds.add(conflictId);
    conflicts = conflicts.where((c) => c.conflictId != conflictId).toList();
  }

  @override
  Future<Map<String, ConflictResourceInfo>> readConflictResourceInfos() async =>
      infos;

  @override
  Future<void> forceLocalState({
    required String conflictId,
    required String replacementMutationId,
    required DateTime createdAtUtc,
  }) async {
    forcedConflictIds.add(conflictId);
    conflicts = conflicts.where((c) => c.conflictId != conflictId).toList();
  }

  @override
  Future<SyncRunReport> synchronize({
    bool takeOverWriting = false,
    DateTime? now,
  }) async {
    synchronizeCalls++;
    return const SyncRunReport(
      state: SyncRunState.synced,
      pushed: 1,
      pulledBatches: 0,
    );
  }

  @override
  Future<String> retryConflictOnCurrentServerVersion({
    required String conflictId,
    required String replacementMutationId,
    required DateTime createdAtUtc,
  }) async {
    retriedConflictIds.add(conflictId);
    return replacementMutationId;
  }
}

class CompleteHandoverInput {
  const CompleteHandoverInput({
    required this.handoverId,
    required this.oneTimeCode,
    required this.sourceClientId,
    required this.frozenRevision,
    required this.expiresAtUtc,
  });

  final String handoverId;
  final String oneTimeCode;
  final String sourceClientId;
  final int frozenRevision;
  final DateTime expiresAtUtc;
}
