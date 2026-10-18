import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/api/sync_api_models.dart';
import 'package:gainer_mobile/data/models/local/local_mutation.dart';
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
      ];
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
    expect(find.text('Neue Serverversion vorhanden.'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Serverstand nutzen').first,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Serverstand nutzen'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Die ausstehende lokale Änderung für diesen Eintrag wird verworfen und durch den letzten Serverstand ersetzt.',
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
      ];
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

    await tester.scrollUntilVisible(
      find.text('Lokale Änderung erneut senden'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
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
}

class _SyncActions implements MobileSyncActions {
  List<LocalConflictRecord> conflicts = [];
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
    conflicts = [];
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
