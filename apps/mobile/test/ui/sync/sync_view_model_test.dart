import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/api/sync_api_models.dart';
import 'package:gainer_mobile/data/models/local/local_mutation.dart';
import 'package:gainer_mobile/data/repositories/sync/local_conflict_recovery.dart';
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

  group('conflict selection and forcing', () {
    late _SyncActions sync;
    late SyncViewModel viewModel;

    Future<SyncViewModel> open({bool online = true}) async {
      viewModel = SyncViewModel(
        sync: sync,
        isOnline: online,
        expectedAccountId: accountId,
        expectedApiOrigin: origin,
      );
      addTearDown(viewModel.dispose);
      await viewModel.load();
      return viewModel;
    }

    setUp(() {
      sync = _SyncActions()
        ..conflicts = [
          _conflict('workout'),
          _conflict('exercise'),
          _conflict('server'),
        ]
        ..infos = {
          'workout': _info(DateTime.utc(2026, 10, 17, 9)),
          'exercise': _info(DateTime.utc(2026, 10, 17, 8)),
          'server': _info(
            DateTime.utc(2026, 10, 17, 7),
            canForce: false,
            hasServerState: true,
          ),
        };
    });

    test(
      'selection mode toggles, selects all and prunes vanished conflicts',
      () async {
        final model = await open();
        expect(model.resourceInfos, hasLength(3));
        model.toggleSelection('workout');
        expect(model.selectedConflictIds, isEmpty);

        model.startSelecting();
        expect(model.isSelecting, isTrue);
        model.toggleSelection('workout');
        expect(model.selectedConflictIds, {'workout'});
        expect(model.allSelected, isFalse);
        model.toggleSelectAll();
        expect(model.allSelected, isTrue);
        expect(
          model.forceableSelection,
          unorderedEquals(['workout', 'exercise']),
        );
        expect(model.acceptableSelection, ['server']);
        model.toggleSelectAll();
        expect(model.selectedConflictIds, isEmpty);

        model.toggleSelection('exercise');
        sync.conflicts = [_conflict('workout')];
        await model.load();
        expect(model.selectedConflictIds, isEmpty);
        model.stopSelecting();
        expect(model.isSelecting, isFalse);

        sync.conflicts = [];
        await model.load();
        model.startSelecting();
        expect(model.isSelecting, isFalse);
      },
    );

    test('forces in queue order, then synchronizes once', () async {
      final model = await open();
      model.startSelecting();
      model.toggleSelectAll();

      await model.forceLocalStates(model.selectedConflictIds);

      expect(sync.calls, ['force:exercise', 'force:workout', 'sync']);
      expect(sync.forceMutationIds.toSet(), hasLength(2));
      expect(
        model.statusMessage,
        'Lokaler Stand erzwungen und synchronisiert.',
      );
      expect(model.isSelecting, isFalse);
      expect(model.conflicts.map((c) => c.conflictId), ['server']);
    });

    test('reports a pending sync when sync does not finish', () async {
      sync.syncState = SyncRunState.retryPending;
      final model = await open();

      await model.forceLocalStates(['workout']);
      expect(
        model.statusMessage,
        'Lokaler Stand erzwungen. Die Synchronisierung folgt.',
      );

      sync.syncError = StateError('offline');
      await model.forceLocalStates(['exercise']);
      expect(
        model.statusMessage,
        'Lokaler Stand erzwungen. Die Synchronisierung folgt.',
      );
      expect(model.errorMessage, isNull);
    });

    test('does not synchronize while offline', () async {
      final model = await open(online: false);

      await model.forceLocalStates(['workout']);

      expect(sync.calls, ['force:workout']);
    });

    test(
      'a failing item is reported and the others still go through',
      () async {
        sync.failingForce = {'exercise'};
        final model = await open();

        await model.forceLocalStates(['workout', 'exercise']);

        expect(sync.calls, ['force:exercise', 'force:workout', 'sync']);
        expect(
          model.errorMessage,
          '1 von 2 Einträgen konnten nicht erzwungen werden.',
        );
        expect(model.statusMessage, isNull);
      },
    );

    test('all failing skips the sync', () async {
      sync.failingForce = {'workout'};
      final model = await open();

      await model.forceLocalStates(['workout']);

      expect(sync.calls, ['force:workout']);
      expect(model.errorMessage, isNotNull);
    });

    test('skips conflicts that cannot be forced', () async {
      final model = await open();

      await model.forceLocalStates(['server']);

      expect(sync.calls, isEmpty);
      expect(model.statusMessage, isNull);
    });

    test('accepts server state only for conflicts with a copy', () async {
      final model = await open();

      await model.acceptServerVersions(['workout', 'server']);

      expect(sync.calls, ['accept:server']);
      expect(
        model.statusMessage,
        'Serverstand übernommen; lokale Änderungen entfernt.',
      );
      await model.acceptServerVersions(['workout']);
      expect(sync.calls, ['accept:server']);

      sync.failingAccept = {'exercise'};
      sync.infos = {
        'exercise': _info(DateTime.utc(2026), hasServerState: true),
      };
      sync.conflicts = [_conflict('exercise')];
      await model.load();
      await model.acceptServerVersions(['exercise']);
      expect(
        model.errorMessage,
        '1 von 1 Einträgen konnten nicht übernommen werden.',
      );
    });
  });

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

ConflictResourceInfo _info(
  DateTime queuedAt, {
  bool canForce = true,
  bool hasServerState = false,
}) => ConflictResourceInfo(
  title: null,
  hasServerState: hasServerState,
  canForceLocal: canForce,
  firstQueuedAtUtc: queuedAt,
  firstSequence: 1,
);

LocalConflictRecord _conflict(String id) => LocalConflictRecord(
  conflictId: id,
  aggregateType: 'workout',
  aggregateId: 'aggregate-$id',
  createdAtUtc: DateTime.utc(2026, 10, 18),
  code: 'validation_failed',
  detail: const {},
);

class _SyncActions implements MobileSyncActions {
  List<LocalConflictRecord> conflicts = [];
  Map<String, ConflictResourceInfo> infos = {};
  final calls = <String>[];
  final forceMutationIds = <String>[];
  Set<String> failingForce = {};
  Set<String> failingAccept = {};
  SyncRunState syncState = SyncRunState.synced;
  Object? syncError;
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
    return conflicts;
  }

  @override
  Future<void> acceptConflictServerState(String conflictId) async {
    if (failingAccept.contains(conflictId)) throw StateError('failed');
    calls.add('accept:$conflictId');
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
    calls.add('force:$conflictId');
    if (failingForce.contains(conflictId)) throw StateError('failed');
    forceMutationIds.add(replacementMutationId);
    conflicts = conflicts.where((c) => c.conflictId != conflictId).toList();
  }

  @override
  Future<SyncRunReport> synchronize({
    bool takeOverWriting = false,
    DateTime? now,
  }) async {
    calls.add('sync');
    if (syncError case final error?) throw error;
    return SyncRunReport(state: syncState, pushed: 1, pulledBatches: 0);
  }

  @override
  Future<String> retryConflictOnCurrentServerVersion({
    required String conflictId,
    required String replacementMutationId,
  }) => throw UnimplementedError();
}
