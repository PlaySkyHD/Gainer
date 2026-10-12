import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/api/sync_api_models.dart';
import 'package:gainer_mobile/data/models/local/local_mutation.dart';
import 'package:gainer_mobile/data/repositories/sync/sync_repository.dart';
import 'package:gainer_mobile/data/services/local/pending_handover_secret_store.dart';
import 'package:gainer_mobile/ui/features/sync/sync_view_model.dart';

void main() {
  const accountId = 'a1234567-1234-4234-8234-123456789abc';
  const origin = 'https://gainer.markfort.xyz';

  test(
    'a popped sync screen does not continue after an in-flight handover',
    () async {
      final sync = _SyncActions();
      final viewModel = SyncViewModel(
        sync: sync,
        isOnline: true,
        expectedAccountId: accountId,
        expectedApiOrigin: origin,
      );
      await viewModel.load();
      expect(sync.pendingReads, 1);

      final operation = viewModel.beginHandover();
      expect(sync.beginCalls, 1);
      viewModel.dispose();
      sync.beginResponse.complete(
        BeginSyncHandoverResponse(
          handoverId: 'c1234567-1234-4234-8234-123456789abc',
          oneTimeCode: 'secret-code',
          frozenRevision: 41,
          expiresAtUtc: DateTime.now().toUtc().add(const Duration(hours: 1)),
        ),
      );

      expect(await operation, isNull);
      expect(sync.pendingReads, 1);
      expect(sync.conflictReads, 1);
    },
  );

  test('transfer bundles use the cross-platform size and integer limits', () {
    final sync = _SyncActions();
    final viewModel = SyncViewModel(
      sync: sync,
      isOnline: true,
      expectedAccountId: accountId,
      expectedApiOrigin: origin,
    );
    addTearDown(viewModel.dispose);
    final expiry = DateTime.now().toUtc().add(const Duration(hours: 1));
    final valid = {
      'kind': 'gainer-sync-handover',
      'version': 1,
      'accountId': accountId,
      'apiOrigin': origin,
      'sourceClientId': 'b1234567-1234-4234-8234-123456789abc',
      'handoverId': 'c1234567-1234-4234-8234-123456789abc',
      'oneTimeCode': 'one_time-code-123',
      'frozenRevision': 41,
      'expiresAtUtc': expiry.toIso8601String(),
    };
    expect(viewModel.parseTransferBundle(jsonEncode(valid)).frozenRevision, 41);

    expect(
      () => viewModel.parseTransferBundle(
        jsonEncode({...valid, 'oneTimeCode': 'x' * 129}),
      ),
      throwsFormatException,
    );
    expect(
      () => viewModel.parseTransferBundle(
        jsonEncode({...valid, 'frozenRevision': 9007199254740992}),
      ),
      throwsFormatException,
    );
  });
}

class _SyncActions implements MobileSyncActions {
  int pendingReads = 0;
  int conflictReads = 0;
  int beginCalls = 0;
  final beginResponse = Completer<BeginSyncHandoverResponse>();

  @override
  Future<PendingHandoverRecord?> readPendingHandover() async {
    pendingReads++;
    return null;
  }

  @override
  Future<BeginSyncHandoverResponse> beginHandover({required String requestId}) {
    beginCalls++;
    return beginResponse.future;
  }

  @override
  Future<CompleteSyncHandoverResponse> completeHandover({
    required String handoverId,
    required String oneTimeCode,
    required int frozenRevision,
    required String sourceClientId,
    required DateTime expiresAtUtc,
  }) => throw UnimplementedError();

  @override
  Future<bool> recoverExpiredTargetHandover() => throw UnimplementedError();

  @override
  Future<void> cancelHandover({required String handoverId}) =>
      throw UnimplementedError();

  @override
  Future<List<LocalConflictRecord>> readConflicts() async {
    conflictReads++;
    return const [];
  }

  @override
  Future<void> acceptConflictServerState(String conflictId) =>
      throw UnimplementedError();

  @override
  Future<String> retryConflictOnCurrentServerVersion({
    required String conflictId,
    required String replacementMutationId,
    required DateTime createdAtUtc,
  }) => throw UnimplementedError();
}
