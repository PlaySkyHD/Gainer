import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/api/sync_api_models.dart';
import 'package:gainer_mobile/data/models/local/local_mutation.dart';
import 'package:gainer_mobile/data/repositories/sync/sync_repository.dart';
import 'package:gainer_mobile/data/services/local/pending_handover_secret_store.dart';
import 'package:gainer_mobile/ui/core/theme.dart';
import 'package:gainer_mobile/ui/features/sync/sync_screen.dart';

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('sync screen matches golden in ${brightness.name} mode', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
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

      await expectLater(
        find.byType(SyncScreen),
        matchesGoldenFile('goldens/sync_screen_${brightness.name}.png'),
      );
      expect(tester.takeException(), isNull);
    }, tags: ['golden']);
  }
}

class _SyncActions implements MobileSyncActions {
  List<LocalConflictRecord> conflicts = [];

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
    required DateTime createdAtUtc,
  }) async => replacementMutationId;
}
