import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../data/models/api/sync_api_models.dart';
import '../../../data/models/local/local_mutation.dart';
import '../../../data/repositories/sync/sync_repository.dart';
import '../../../data/services/local/pending_handover_secret_store.dart';

class SyncViewModel extends ChangeNotifier {
  SyncViewModel({
    required this.sync,
    required this.isOnline,
    required this.expectedAccountId,
    required this.expectedApiOrigin,
    bool Function()? isScopeActive,
  }) : isScopeActive = isScopeActive ?? _alwaysActive;

  final MobileSyncActions sync;
  final bool isOnline;
  final String expectedAccountId;
  final String expectedApiOrigin;
  final bool Function() isScopeActive;

  PendingHandoverRecord? pendingHandover;
  List<LocalConflictRecord> conflicts = const [];
  bool isLoading = false;
  bool isBusy = false;
  String? statusMessage;
  String? errorMessage;
  bool _disposed = false;

  static bool _alwaysActive() => true;

  bool get _canUpdate => !_disposed && isScopeActive();

  void _requireActiveScope() {
    if (!_canUpdate) throw StateError('This sync screen is no longer active.');
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void reportInputError(String message) {
    if (!_canUpdate) return;
    errorMessage = message;
    notifyListeners();
  }

  void reportStatus(String message) {
    if (!_canUpdate) return;
    statusMessage = message;
    errorMessage = null;
    notifyListeners();
  }

  String? createTransferBundle() {
    final pending = pendingHandover;
    if (pending == null ||
        pending.phase != 'sourceBegan' ||
        pending.handoverId == null ||
        pending.oneTimeCode == null ||
        pending.frozenRevision == null ||
        pending.expiresAtUtc == null ||
        pending.accountId.toLowerCase() != expectedAccountId.toLowerCase() ||
        pending.apiOrigin != expectedApiOrigin ||
        pending.oneTimeCode!.length > 128 ||
        pending.frozenRevision! < 0 ||
        pending.frozenRevision! > _maxJavaScriptSafeInteger ||
        !pending.expiresAtUtc!.isAfter(DateTime.now().toUtc())) {
      reportInputError('Übergabedaten sind auf diesem Gerät nicht verfügbar.');
      return null;
    }
    return jsonEncode({
      'kind': 'gainer-sync-handover',
      'version': 1,
      'accountId': pending.accountId,
      'apiOrigin': pending.apiOrigin,
      'sourceClientId': pending.sourceClientId,
      'handoverId': pending.handoverId,
      'oneTimeCode': pending.oneTimeCode,
      'frozenRevision': pending.frozenRevision,
      'expiresAtUtc': pending.expiresAtUtc!.toUtc().toIso8601String(),
    });
  }

  HandoverTransferBundle parseTransferBundle(String encoded) {
    if (encoded.length > 8192) {
      throw const FormatException(_invalidTransferBundleMessage);
    }
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic> ||
        decoded.length != 9 ||
        decoded['kind'] != 'gainer-sync-handover' ||
        decoded['version'] != 1) {
      throw const FormatException(_invalidTransferBundleMessage);
    }
    final accountId = _bundleString(decoded, 'accountId', maxLength: 64);
    final apiOrigin = _bundleString(decoded, 'apiOrigin', maxLength: 512);
    final sourceClientId = _bundleString(
      decoded,
      'sourceClientId',
      maxLength: 64,
    );
    final handoverId = _bundleString(decoded, 'handoverId', maxLength: 64);
    final oneTimeCode = _bundleString(decoded, 'oneTimeCode', maxLength: 128);
    final rawRevision = decoded['frozenRevision'];
    final rawExpiry = _bundleString(decoded, 'expiresAtUtc', maxLength: 40);
    final expiry = DateTime.tryParse(rawExpiry);
    final explicitUtc = RegExp(
      r'(?:Z|\+00:00)$',
      caseSensitive: false,
    ).hasMatch(rawExpiry);
    if (accountId.toLowerCase() != expectedAccountId.toLowerCase() ||
        apiOrigin != expectedApiOrigin ||
        !_isUuid(accountId) ||
        !_isUuid(sourceClientId) ||
        !_isUuid(handoverId) ||
        oneTimeCode.trim() != oneTimeCode ||
        oneTimeCode.runes.any((character) => character < 0x20) ||
        rawRevision is! int ||
        rawRevision < 0 ||
        rawRevision > _maxJavaScriptSafeInteger ||
        expiry == null ||
        !explicitUtc ||
        !expiry.isAfter(DateTime.now().toUtc()) ||
        expiry.difference(DateTime.now().toUtc()) > const Duration(hours: 24)) {
      throw const FormatException(_invalidTransferBundleMessage);
    }
    return HandoverTransferBundle(
      accountId: accountId,
      apiOrigin: apiOrigin,
      sourceClientId: sourceClientId,
      handoverId: handoverId,
      oneTimeCode: oneTimeCode,
      frozenRevision: rawRevision,
      expiresAtUtc: expiry.toUtc(),
    );
  }

  Future<void> load() async {
    if (!_canUpdate || isLoading || isBusy) return;
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final pending = await sync.readPendingHandover();
      _requireActiveScope();
      final currentConflicts = await sync.readConflicts();
      _requireActiveScope();
      pendingHandover = pending;
      conflicts = currentConflicts;
    } catch (_) {
      if (_canUpdate) {
        errorMessage = 'Sync-Status kann gerade nicht geladen werden.';
      }
    } finally {
      if (_canUpdate) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<BeginSyncHandoverResponse?> beginHandover() => _run(() async {
    if (!isOnline) throw StateError('offline');
    final pending = pendingHandover;
    final response = await sync.beginHandover(
      requestId: pending?.phase == 'sourceBeginPending'
          ? pending!.requestId
          : _newUuidV4(),
    );
    _requireActiveScope();
    pendingHandover = await sync.readPendingHandover();
    return response;
  }, successMessage: 'Übergabe vorbereitet. Der Quellaccount ist eingefroren.');

  Future<void> cancelHandover() => _run(() async {
    final pending = pendingHandover;
    if (!isOnline ||
        pending?.phase != 'sourceBegan' ||
        pending?.handoverId == null) {
      throw StateError('unavailable');
    }
    await sync.cancelHandover(handoverId: pending!.handoverId!);
    _requireActiveScope();
    pendingHandover = await sync.readPendingHandover();
  }, successMessage: 'Übergabe abgebrochen.');

  Future<CompleteSyncHandoverResponse?> completeHandover({
    required String handoverId,
    required String oneTimeCode,
    required String sourceClientId,
    required String frozenRevision,
    required DateTime expiresAtUtc,
  }) => _run(
    () async {
      if (!isOnline) throw StateError('offline');
      final revision = int.tryParse(frozenRevision.trim());
      if (revision == null ||
          revision < 0 ||
          revision > _maxJavaScriptSafeInteger) {
        throw const FormatException('revision');
      }
      final result = await sync.completeHandover(
        handoverId: handoverId.trim(),
        oneTimeCode: oneTimeCode.trim(),
        sourceClientId: sourceClientId.trim(),
        frozenRevision: revision,
        expiresAtUtc: expiresAtUtc.toUtc(),
      );
      _requireActiveScope();
      pendingHandover = await sync.readPendingHandover();
      return result;
    },
    successMessage:
        'Dieses Gerät ist jetzt als aktives Schreibgerät bestätigt.',
  );

  Future<CompleteSyncHandoverResponse?> resumeTargetHandover() async {
    final pending = pendingHandover;
    if (pending == null ||
        pending.phase != 'targetCompletePending' ||
        pending.handoverId == null ||
        pending.oneTimeCode == null ||
        pending.frozenRevision == null ||
        pending.expiresAtUtc == null ||
        pending.targetClientId == null) {
      return null;
    }
    return completeHandover(
      handoverId: pending.handoverId!,
      oneTimeCode: pending.oneTimeCode!,
      sourceClientId: pending.sourceClientId,
      frozenRevision: pending.frozenRevision.toString(),
      expiresAtUtc: pending.expiresAtUtc!,
    );
  }

  Future<void> recoverExpiredTargetHandover() async {
    final activeWriter = await _run(
      () async {
        if (!isOnline) throw StateError('offline');
        final becameWriter = await sync.recoverExpiredTargetHandover();
        _requireActiveScope();
        pendingHandover = await sync.readPendingHandover();
        return becameWriter;
      },
      successMessage:
          'Die abgelaufene Übergabe wurde nach Serverprüfung bereinigt.',
    );
    if (activeWriter == false && _canUpdate) {
      statusMessage = 'Die Übergabe ist abgelaufen. Dieses Gerät bleibt schreibgeschützt; lokale Daten und ausstehende Änderungen bleiben geschützt.';
      notifyListeners();
    }
  }

  Future<void> acceptServerVersion(String conflictId) => _run(
    () async {
      await sync.acceptConflictServerState(conflictId);
      _requireActiveScope();
      conflicts = await sync.readConflicts();
    },
    successMessage: 'Serverstand übernommen; lokale Änderungen für diesen Eintrag entfernt.',
  );

  Future<void> retryLocalVersion(String conflictId) => _run(() async {
    await sync.retryConflictOnCurrentServerVersion(
      conflictId: conflictId,
      replacementMutationId: _newUuidV4(),
      createdAtUtc: DateTime.now().toUtc(),
    );
    _requireActiveScope();
    conflicts = await sync.readConflicts();
  }, successMessage: 'Lokale Änderung mit neuer Idempotenz-ID vorgemerkt.');

  Future<T?> _run<T>(
    Future<T> Function() action, {
    required String successMessage,
  }) async {
    if (!_canUpdate || isBusy) return null;
    isBusy = true;
    errorMessage = null;
    statusMessage = null;
    notifyListeners();
    try {
      final result = await action();
      _requireActiveScope();
      statusMessage = successMessage;
      return result;
    } catch (_) {
      if (!_canUpdate) return null;
      try {
        final pending = await sync.readPendingHandover();
        _requireActiveScope();
        final currentConflicts = await sync.readConflicts();
        _requireActiveScope();
        pendingHandover = pending;
        conflicts = currentConflicts;
      } catch (_) {}
      if (!_canUpdate) return null;
      errorMessage = 'Aktion fehlgeschlagen. Prüfe Verbindung, Übergabedaten und Sync-Status.';
      return null;
    } finally {
      if (_canUpdate) {
        isBusy = false;
        notifyListeners();
      }
    }
  }
}

const int _maxJavaScriptSafeInteger = 9007199254740991;
const _invalidTransferBundleMessage = 'Invalid transfer bundle.';

class HandoverTransferBundle {
  const HandoverTransferBundle({
    required this.accountId,
    required this.apiOrigin,
    required this.sourceClientId,
    required this.handoverId,
    required this.oneTimeCode,
    required this.frozenRevision,
    required this.expiresAtUtc,
  });

  final String accountId;
  final String apiOrigin;
  final String sourceClientId;
  final String handoverId;
  final String oneTimeCode;
  final int frozenRevision;
  final DateTime expiresAtUtc;
}

String _bundleString(
  Map<String, dynamic> value,
  String key, {
  required int maxLength,
}) {
  final result = value[key];
  if (result is! String || result.isEmpty || result.length > maxLength) {
    throw const FormatException(_invalidTransferBundleMessage);
  }
  return result;
}

bool _isUuid(String value) => RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
).hasMatch(value);

String _newUuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0'));
  final value = hex.join();
  return '${value.substring(0, 8)}-${value.substring(8, 12)}-'
      '${value.substring(12, 16)}-${value.substring(16, 20)}-'
      '${value.substring(20)}';
}
