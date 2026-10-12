import '../../models/api/sync_api_models.dart';
import '../../services/api/api_client.dart';
import '../../services/local/pending_handover_secret_store.dart';
import 'local_sync_store.dart';

const nativeHandoverSyncProtocolVersion = 2;

/// Crash-safe native ownership transfer. Every identity needed to retry a
/// request is written to the purpose-bound secure record before network I/O.
class NativeHandoverRepository {
  NativeHandoverRepository({
    required this.store,
    required this.api,
    required this.installationIdentity,
    required this.displayName,
    required this.secrets,
    required this.assertSessionMatchesStore,
    required this.synchronizeSource,
    required this.pullAll,
  });

  final LocalSyncStore store;
  final ApiClient api;
  final InstallationIdentityStore installationIdentity;
  final String displayName;
  final PendingHandoverSecretStore? secrets;
  final Future<void> Function() assertSessionMatchesStore;
  final Future<void> Function() synchronizeSource;
  final Future<int> Function() pullAll;

  Future<PendingHandoverRecord?> readPendingHandover() async {
    final secureStore = secrets;
    if (secureStore == null) return null;
    final origin = api.configuration.canonicalApiOrigin;
    final bytes = await secureStore.read(
      apiOrigin: origin,
      accountId: store.accountId,
    );
    if (bytes == null) return null;
    final record = PendingHandoverRecord.decode(bytes);
    if (record.apiOrigin != origin || record.accountId != store.accountId) {
      throw StateError(
        'The secure handover record belongs to another account or API.',
      );
    }
    return record;
  }

  Future<BeginSyncHandoverResponse> begin({required String requestId}) async {
    final secureStore = _requireSecureStore();
    _validateUuid(requestId, 'requestId');
    await assertSessionMatchesStore();
    await synchronizeSource();
    final clientId = await installationIdentity.getOrCreateInstallationId();
    final cursor = await store.readSyncMetadata('pull-cursor');
    final origin = api.configuration.canonicalApiOrigin;
    final accountId = store.accountId;
    final existing = await readPendingHandover();
    if (existing != null &&
        (existing.phase != 'sourceBeginPending' ||
            existing.sourceClientId != clientId)) {
      throw StateError('Another handover is already pending for this account.');
    }
    final stableRequestId = existing?.requestId ?? requestId;
    final expectedRevision =
        existing?.frozenRevision ?? (cursor is int ? cursor : 0);
    await store.freezeWritesIfOutboxEmpty();
    await _write(
      secureStore,
      PendingHandoverRecord(
        apiOrigin: origin,
        accountId: accountId,
        requestId: stableRequestId,
        sourceClientId: clientId,
        phase: 'sourceBeginPending',
        frozenRevision: expectedRevision,
        expiresAtUtc: null,
        handoverId: existing?.handoverId,
        oneTimeCode: existing?.oneTimeCode,
      ),
    );
    try {
      final response = await api.beginSyncHandover(
        BeginSyncHandoverRequest(
          requestId: stableRequestId,
          sourceClientId: clientId,
          expectedRevision: expectedRevision,
        ),
        expectedAccountId: accountId,
      );
      await _write(
        secureStore,
        PendingHandoverRecord(
          apiOrigin: origin,
          accountId: accountId,
          requestId: stableRequestId,
          sourceClientId: clientId,
          handoverId: response.handoverId,
          frozenRevision: response.frozenRevision,
          phase: 'sourceBegan',
          expiresAtUtc: response.expiresAtUtc,
          oneTimeCode: response.oneTimeCode,
        ),
      );
      return response;
    } on ApiException catch (error) {
      if ([400, 401, 403, 404, 422].contains(error.statusCode)) {
        await store.unfreezeWrites();
        await secureStore.clear(apiOrigin: origin, accountId: accountId);
      }
      rethrow;
    }
  }

  Future<CompleteSyncHandoverResponse> complete({
    required String handoverId,
    required String oneTimeCode,
    required int frozenRevision,
    required String sourceClientId,
    required DateTime expiresAtUtc,
  }) async {
    _validateUuid(handoverId, 'handoverId');
    _validateUuid(sourceClientId, 'sourceClientId');
    if (frozenRevision < 0 || oneTimeCode.isEmpty) {
      throw ArgumentError(
        'A handover code and nonnegative frozen revision are required.',
      );
    }
    await assertSessionMatchesStore();
    final secureStore = _requireSecureStore();
    final clientId = await installationIdentity.getOrCreateInstallationId();
    final origin = api.configuration.canonicalApiOrigin;
    final accountId = store.accountId;
    final prior = await readPendingHandover();
    if (prior?.phase == 'targetCompletePending' &&
        (prior!.handoverId != handoverId ||
            prior.frozenRevision != frozenRevision ||
            prior.targetClientId != clientId ||
            prior.sourceClientId != sourceClientId)) {
      throw StateError('A different handover completion is already pending.');
    }
    final record = PendingHandoverRecord(
      apiOrigin: origin,
      accountId: accountId,
      requestId: prior?.requestId ?? handoverId,
      sourceClientId: sourceClientId,
      handoverId: handoverId,
      targetClientId: clientId,
      frozenRevision: frozenRevision,
      phase: 'targetCompletePending',
      expiresAtUtc: expiresAtUtc.toUtc(),
      oneTimeCode: prior?.oneTimeCode ?? oneTimeCode,
    );
    if (record.expiresAtUtc!.isBefore(DateTime.now().toUtc())) {
      throw StateError('The one-time handover code has expired.');
    }
    await store.freezeWritesIfOutboxEmpty();
    await _write(secureStore, record);
    await api.registerSyncClient(
      SyncClientRegistrationRequest(
        clientId: clientId,
        displayName: displayName,
        protocolVersion: nativeHandoverSyncProtocolVersion,
        takeOverWriting: false,
      ),
      expectedAccountId: accountId,
    );
    await pullAll();
    final cursor = await store.readSyncMetadata('pull-cursor');
    final caughtUp = cursor is int ? cursor : 0;
    if (caughtUp < frozenRevision) {
      throw StateError(
        'Target client has not reached the frozen server revision.',
      );
    }
    final response = await api.completeSyncHandover(
      handoverId: handoverId,
      request: CompleteSyncHandoverRequest(
        oneTimeCode: record.oneTimeCode!,
        targetClientId: clientId,
        caughtUpRevision: frozenRevision,
      ),
      expectedAccountId: accountId,
    );
    if (!response.isActiveWriter ||
        response.frozenRevision != frozenRevision ||
        response.targetClientId != clientId) {
      throw StateError(
        'The server did not confirm this frozen revision and target as active writer.',
      );
    }
    await store.unfreezeWrites();
    await secureStore.clear(apiOrigin: origin, accountId: accountId);
    return response;
  }

  Future<void> cancel({required String handoverId}) async {
    _validateUuid(handoverId, 'handoverId');
    await assertSessionMatchesStore();
    final secureStore = _requireSecureStore();
    final clientId = await installationIdentity.getOrCreateInstallationId();
    final pending = await readPendingHandover();
    if (pending == null ||
        pending.handoverId != handoverId ||
        pending.sourceClientId != clientId ||
        pending.phase != 'sourceBegan') {
      throw StateError(
        'No matching source handover record is available to cancel.',
      );
    }
    await api.cancelSyncHandover(
      handoverId: handoverId,
      request: CancelSyncHandoverRequest(sourceClientId: clientId),
      expectedAccountId: store.accountId,
    );
    await store.unfreezeWrites();
    await secureStore.clear(
      apiOrigin: api.configuration.canonicalApiOrigin,
      accountId: store.accountId,
    );
  }

  PendingHandoverSecretStore _requireSecureStore() =>
      secrets ??
      (throw StateError('A secure pending-handover store is not configured.'));

  Future<void> _write(
    PendingHandoverSecretStore store,
    PendingHandoverRecord record,
  ) => store.write(
    apiOrigin: record.apiOrigin,
    accountId: record.accountId,
    record: record.encode(),
  );

  void _validateUuid(String value, String name) {
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(value)) {
      throw ArgumentError.value(value, name, 'Expected a UUID.');
    }
  }
}
