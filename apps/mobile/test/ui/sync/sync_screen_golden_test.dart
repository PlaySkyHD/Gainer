import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/api/sync_api_models.dart';
import 'package:gainer_mobile/data/models/local/local_mutation.dart';
import 'package:gainer_mobile/data/repositories/sync/local_conflict_recovery.dart';
import 'package:gainer_mobile/data/repositories/sync/sync_repository.dart';
import 'package:gainer_mobile/data/services/local/pending_handover_secret_store.dart';
import 'package:gainer_mobile/ui/core/theme.dart';
import 'package:gainer_mobile/ui/features/sync/sync_screen.dart';

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    for (final selecting in [false, true]) {
      final suffix = selecting ? '_selecting' : '';
      testWidgets(
        'sync screen$suffix matches golden in ${brightness.name} mode',
        (tester) async {
          tester.view.physicalSize = const Size(390, 1400);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final sync = _SyncActions()
            ..conflicts = [
              _conflict('c-1', 'workout', 'active_workout_exists'),
              _conflict('c-2', 'workout', 'validation_failed'),
              _conflict('c-3', 'daily-check-in', 'version_conflict'),
            ]
            ..infos = {
              'c-1': _info('Push · 17.10.2026'),
              'c-2': _info('Pull · 16.10.2026'),
              'c-3': _info('2026-10-12', hasServerState: true),
            };

          await tester.pumpWidget(
            CupertinoApp(
              debugShowCheckedModeBanner: false,
              theme: GainerTheme.forBrightness(brightness),
              home: SyncScreen(
                sync: sync,
                isOnline: true,
                accountId: 'a1234567-1234-4234-8234-123456789abc',
                apiOrigin: 'https://gainer.markfort.xyz',
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (selecting) {
            await tester.tap(find.text('Auswählen'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Training · Push · 17.10.2026'));
            await tester.pumpAndSettle();
          }

          await expectLater(
            find.byType(SyncScreen),
            matchesGoldenFile(
              'goldens/sync_screen${suffix}_${brightness.name}.png',
            ),
          );
          expect(tester.takeException(), isNull);
        },
        tags: ['golden'],
      );
    }
  }
}

LocalConflictRecord _conflict(String id, String type, String code) =>
    LocalConflictRecord(
      conflictId: id,
      aggregateType: type,
      aggregateId: 'resource-$id',
      createdAtUtc: DateTime.utc(2026, 10, 12),
      code: code,
      detail: {'message': 'abgelehnt'},
    );

ConflictResourceInfo _info(String title, {bool hasServerState = false}) =>
    ConflictResourceInfo(
      title: title,
      hasServerState: hasServerState,
      canForceLocal: true,
      firstQueuedAtUtc: DateTime.utc(2026, 10, 12),
      firstSequence: 1,
    );

class _SyncActions implements MobileSyncActions {
  List<LocalConflictRecord> conflicts = [];
  Map<String, ConflictResourceInfo> infos = {};

  @override
  Future<PendingHandoverRecord?> readPendingHandover() async => null;

  @override
  Future<BeginSyncHandoverResponse> beginHandover({
    required String requestId,
  }) => throw UnimplementedError();

  @override
  Future<CompleteSyncHandoverResponse> completeHandover({
    required String handoverId,
    required String oneTimeCode,
    required int frozenRevision,
    required String sourceClientId,
    required DateTime expiresAtUtc,
  }) => throw UnimplementedError();

  @override
  Future<void> cancelHandover({required String handoverId}) async {}

  @override
  Future<bool> recoverExpiredTargetHandover() async => false;

  @override
  Future<List<LocalConflictRecord>> readConflicts() async => conflicts;

  @override
  Future<void> acceptConflictServerState(String conflictId) async {}

  @override
  Future<String> retryConflictOnCurrentServerVersion({
    required String conflictId,
    required String replacementMutationId,
  }) async => replacementMutationId;

  @override
  Future<Map<String, ConflictResourceInfo>> readConflictResourceInfos() async =>
      infos;

  @override
  Future<void> forceLocalState({
    required String conflictId,
    required String replacementMutationId,
    required DateTime createdAtUtc,
  }) async {}

  @override
  Future<SyncRunReport> synchronize({
    bool takeOverWriting = false,
    DateTime? now,
  }) async => const SyncRunReport(
    state: SyncRunState.synced,
    pushed: 0,
    pulledBatches: 0,
  );
}
