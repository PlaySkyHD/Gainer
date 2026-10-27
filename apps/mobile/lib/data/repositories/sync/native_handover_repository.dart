import '../../models/api/sync_api_models.dart';
import '../../services/api/api_client.dart';
import '../../services/local/pending_handover_secret_store.dart';
import 'local_sync_store.dart';
import 'sync_protocol.dart';

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

  bool _isDifferentCompletion(
    PendingHandoverRecord prior, {
    required String handoverId,
    required int frozenRevision,
    required String targetClientId,
    required String sourceClientId,
    required String oneTimeCode,
  }) =>
      prior.handoverId != handoverId ||
      prior.frozenRevision != frozenRevision ||
      prior.targetClientId != targetClientId ||
      prior.sourceClientId != sourceClientId ||
      prior.oneTimeCode != oneTimeCode ||
      prior.expiresAtUtc == null;

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
    final secureStore = _requireSecureStore();
    final origin = api.configuration.canonicalApiOrigin;
    final accountId = store.accountId;
    final prior = await readPendingHandover();
    final isReplay = prior?.phase == 'targetCompletePending';
    if (!isReplay && !expiresAtUtc.toUtc().isAfter(DateTime.now().toUtc())) {
      throw StateError('The one-time handover code has expired.');
    }
    final clientId = await installationIdentity.getOrCreateInstallationId();
    if (isReplay &&
        _isDifferentCompletion(
          prior!,
          handoverId: handoverId,
          frozenRevision: frozenRevision,
          targetClientId: clientId,
          sourceClientId: sourceClientId,
          oneTimeCode: oneTimeCode,
        )) {
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
      expiresAtUtc: isReplay
          ? prior!.expiresAtUtc!.toUtc()
          : _cappedExpiry(expiresAtUtc),
      oneTimeCode: isReplay ? prior!.oneTimeCode : oneTimeCode,
    );
    await assertSessionMatchesStore();
    final wasFrozen =
        await store.readSyncMetadata('local-writes-frozen') == true;
    await store.freezeWritesIfOutboxEmpty();
    await _write(secureStore, record);
    await _prepareVerifiedTarget(
      clientId: clientId,
      accountId: accountId,
      frozenRevision: frozenRevision,
    );
    final CompleteSyncHandoverResponse response;
    try {
      response = await api.completeSyncHandover(
        handoverId: handoverId,
        request: CompleteSyncHandoverRequest(
          oneTimeCode: record.oneTimeCode!,
          targetClientId: clientId,
          caughtUpRevision: frozenRevision,
        ),
        expectedAccountId: accountId,
      );
    } on ApiException catch (error) {
      // A wrong code or id is typed by hand and can never succeed on retry
      // with the same values. Release the freeze and the record so a corrected
      // entry is accepted instead of being rejected as a different completion.
      if (_isDefinitiveCompleteRejection(error)) {
        // Only release a freeze this flow set. A device that was already
        // frozen (e.g. after a recovery that keeps it frozen) stays frozen.
        if (!wasFrozen || isReplay) await store.unfreezeWrites();
        await secureStore.clear(apiOrigin: origin, accountId: accountId);
      }
      rethrow;
    }
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

  /// Explicitly releases a stale target freeze only after the server confirms
  /// that the stored handover is terminal or confirms this installation as the
  /// completed target. Local clock expiry alone never clears recovery state.
  Future<bool> recoverExpiredTargetHandover() async {
    await assertSessionMatchesStore();
    final secureStore = _requireSecureStore();
    final clientId = await installationIdentity.getOrCreateInstallationId();
    final origin = api.configuration.canonicalApiOrigin;
    final accountId = store.accountId;
    final pending = await readPendingHandover();
    if (pending == null ||
        pending.phase != 'targetCompletePending' ||
        pending.targetClientId != clientId ||
        pending.handoverId == null ||
        pending.oneTimeCode == null ||
        pending.frozenRevision == null ||
        pending.expiresAtUtc == null ||
        !isHandoverExpiryElapsed(pending.expiresAtUtc!)) {
      throw StateError('No expired target handover can be recovered.');
    }
    await store.freezeWritesIfOutboxEmpty();
    await _prepareVerifiedTarget(
      clientId: clientId,
      accountId: accountId,
      frozenRevision: pending.frozenRevision!,
    );

    CompleteSyncHandoverResponse response;
    try {
      response = await api.completeSyncHandover(
        handoverId: pending.handoverId!,
        request: CompleteSyncHandoverRequest(
          oneTimeCode: pending.oneTimeCode!,
          targetClientId: clientId,
          caughtUpRevision: pending.frozenRevision!,
        ),
        expectedAccountId: accountId,
      );
    } on ApiException catch (error) {
      if (error.code != 'handover_expired' &&
          error.code != 'handover_not_pending' &&
          error.code != 'handover_not_found') {
        rethrow;
      }
      await _registerWithoutTakeover(clientId: clientId, accountId: accountId);
      await secureStore.clear(apiOrigin: origin, accountId: accountId);
      // The server says this handover is terminal, but has not granted this
      // client writer ownership. Keep local edits frozen until a later verified
      // transfer or explicit server-confirmed completion.
      return false;
    }

    if (response.handoverId != pending.handoverId ||
        response.frozenRevision != pending.frozenRevision ||
        response.targetClientId != clientId) {
      throw StateError(
        'The server response does not match the stored handover identity.',
      );
    }
    if (response.isActiveWriter) {
      await store.unfreezeWrites();
      await secureStore.clear(apiOrigin: origin, accountId: accountId);
      return true;
    }

    final registration = await _registerWithoutTakeover(
      clientId: clientId,
      accountId: accountId,
    );
    if (registration.isActiveWriter) {
      throw StateError(
        'Server handover and registration writer states do not match.',
      );
    }
    await secureStore.clear(apiOrigin: origin, accountId: accountId);
    return false;
  }

  /// The expiry of a hand-entered bundle is untrusted: a far-future value
  /// would block recovery until then, so the stored expiry never exceeds the
  /// server lifetime from now. A legitimately later value cannot exist.
  DateTime _cappedExpiry(DateTime expiresAtUtc) {
    final latest = DateTime.now().toUtc().add(handoverMaxLifetime);
    final expiry = expiresAtUtc.toUtc();
    return expiry.isAfter(latest) ? latest : expiry;
  }

  /// Rejections caused by what was typed in, decided by the server error code
  /// (never by a bare status, a proxy may answer 400). Terminal states such as
  /// `handover_expired`, `handover_not_pending` and `handover_already_consumed`
  /// are left to [recoverExpiredTargetHandover], which keeps the device frozen
  /// until a verified transfer. `stale_revision`, `inactive_source` and
  /// `target_not_registered` can succeed on retry, so they keep the record.
  bool _isDefinitiveCompleteRejection(ApiException error) => const {
    'invalid_handover_code',
    'handover_not_found',
    'invalid_handover_request',
    'invalid_handover_target',
  }.contains(error.code);

  Future<SyncClientRegistrationResponse> _registerWithoutTakeover({
    required String clientId,
    required String accountId,
  }) async {
    final registration = await api.registerSyncClient(
      SyncClientRegistrationRequest(
        clientId: clientId,
        displayName: displayName,
        protocolVersion: nativeSyncProtocolVersion,
        takeOverWriting: false,
      ),
      expectedAccountId: accountId,
    );
    if (registration.clientId != clientId ||
        registration.protocolVersion < nativeSyncProtocolVersion) {
      throw StateError('The server did not confirm this device registration.');
    }
    return registration;
  }

  Future<void> _prepareVerifiedTarget({
    required String clientId,
    required String accountId,
    required int frozenRevision,
  }) async {
    await _registerWithoutTakeover(clientId: clientId, accountId: accountId);
    await pullAll();
    final cursor = await store.readSyncMetadata('pull-cursor');
    if ((cursor is int ? cursor : 0) < frozenRevision) {
      throw StateError(
        'Target client has not reached the frozen server revision.',
      );
    }
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
