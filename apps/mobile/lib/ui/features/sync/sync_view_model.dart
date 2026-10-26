import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../data/models/api/sync_api_models.dart';
import '../../../data/models/local/local_mutation.dart';
import '../../../data/repositories/sync/local_conflict_recovery.dart';
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

  /// Titel, Serverstand und Erzwingbarkeit je Konflikt-ID.
  Map<String, ConflictResourceInfo> resourceInfos = const {};
  bool isSelecting = false;
  final Set<String> selectedConflictIds = {};
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
      final infos = await sync.readConflictResourceInfos();
      _requireActiveScope();
      pendingHandover = pending;
      conflicts = currentConflicts;
      resourceInfos = infos;
      _pruneSelection();
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
      await _refreshConflicts();
    },
    successMessage: 'Serverstand übernommen; lokale Änderungen für diesen Eintrag entfernt.',
  );

  Future<void> retryLocalVersion(String conflictId) => _run(() async {
    await sync.retryConflictOnCurrentServerVersion(
      conflictId: conflictId,
      replacementMutationId: _newUuidV4(),
    );
    _requireActiveScope();
    await _refreshConflicts();
  }, successMessage: 'Lokale Änderung mit neuer Idempotenz-ID vorgemerkt.');

  /// Ob der Konflikt den lokalen Stand erzwingen lässt.
  bool canForce(String conflictId) =>
      resourceInfos[conflictId]?.canForceLocal ?? false;

  /// Ob für den Konflikt ein Serverstand (Kopie oder Löschmarke) existiert.
  bool hasServerState(String conflictId) =>
      resourceInfos[conflictId]?.hasServerState ?? false;

  /// Ob „Lokale Änderung erneut senden“ gelingen kann.
  bool canRetry(String conflictId) =>
      resourceInfos[conflictId]?.canRetry ?? false;

  /// Ob der Server den Eintrag nie hatte: „Serverstand nutzen“ heißt dann
  /// „Verwerfen“.
  bool discardsLocal(String conflictId) =>
      resourceInfos[conflictId]?.discardsLocal ?? false;

  void startSelecting() {
    if (!_canUpdate || isBusy || conflicts.isEmpty) return;
    isSelecting = true;
    notifyListeners();
  }

  void stopSelecting() {
    if (!_canUpdate) return;
    isSelecting = false;
    selectedConflictIds.clear();
    notifyListeners();
  }

  void toggleSelection(String conflictId) {
    if (!_canUpdate || !isSelecting) return;
    if (!selectedConflictIds.remove(conflictId)) {
      selectedConflictIds.add(conflictId);
    }
    notifyListeners();
  }

  bool get allSelected =>
      conflicts.isNotEmpty &&
      conflicts.every((c) => selectedConflictIds.contains(c.conflictId));

  void toggleSelectAll() {
    if (!_canUpdate || !isSelecting) return;
    if (allSelected) {
      selectedConflictIds.clear();
    } else {
      selectedConflictIds.addAll(conflicts.map((c) => c.conflictId));
    }
    notifyListeners();
  }

  /// Erzwingbare unter den gewählten Konflikten.
  List<String> get forceableSelection => [
    for (final id in selectedConflictIds)
      if (canForce(id)) id,
  ];

  /// Gewählte Konflikte, für die ein Serverstand existiert.
  List<String> get acceptableSelection => [
    for (final id in selectedConflictIds)
      if (hasServerState(id)) id,
  ];

  /// Erzwingt den lokalen Stand der Konflikte in der ursprünglichen Reihenfolge
  /// ihrer Änderungen (Übungen und Pläne vor Trainings) und startet danach einen
  /// Sync. Nicht erzwingbare Konflikte werden übersprungen.
  Future<void> forceLocalStates(Iterable<String> conflictIds) async {
    final ids = conflictIds.where(canForce).toList()
      ..sort((a, b) {
        final left = resourceInfos[a]!;
        final right = resourceInfos[b]!;
        final byTime = (left.firstQueuedAtUtc ?? DateTime.utc(0)).compareTo(
          right.firstQueuedAtUtc ?? DateTime.utc(0),
        );
        return byTime != 0
            ? byTime
            : left.firstSequence.compareTo(right.firstSequence);
      });
    if (ids.isEmpty) return;
    var failed = 0;
    var synced = false;
    await _run(
      () async {
        for (final id in ids) {
          try {
            await sync.forceLocalState(
              conflictId: id,
              replacementMutationId: _newUuidV4(),
              createdAtUtc: DateTime.now().toUtc(),
            );
          } catch (_) {
            failed++;
          }
          _requireActiveScope();
        }
        if (failed < ids.length && isOnline) {
          try {
            final report = await sync.synchronize();
            synced = report.state == SyncRunState.synced;
          } catch (_) {}
        }
        _requireActiveScope();
        await _refreshConflicts();
        isSelecting = false;
        selectedConflictIds.clear();
        if (failed > 0) {
          throw StateError('$failed von ${ids.length} nicht erzwungen');
        }
      },
      successMessage: 'Lokaler Stand erzwungen.',
      resultMessage: () => synced
          ? 'Lokaler Stand erzwungen und synchronisiert.'
          : 'Lokaler Stand erzwungen. Die Synchronisierung folgt.',
      failureMessage: () =>
          '$failed von ${ids.length} Einträgen konnten nicht erzwungen werden.',
    );
  }

  /// Übernimmt den Serverstand für alle Konflikte mit Serverstand.
  Future<void> acceptServerVersions(Iterable<String> conflictIds) async {
    final ids = conflictIds.where(hasServerState).toList();
    if (ids.isEmpty) return;
    var failed = 0;
    await _run(
      () async {
        for (final id in ids) {
          try {
            await sync.acceptConflictServerState(id);
          } catch (_) {
            failed++;
          }
          _requireActiveScope();
        }
        await _refreshConflicts();
        isSelecting = false;
        selectedConflictIds.clear();
        if (failed > 0) {
          throw StateError('$failed von ${ids.length} nicht übernommen');
        }
      },
      successMessage: 'Serverstand übernommen; lokale Änderungen entfernt.',
      failureMessage: () =>
          '$failed von ${ids.length} Einträgen konnten nicht übernommen werden.',
    );
  }

  Future<void> _refreshConflicts() async {
    final current = await sync.readConflicts();
    _requireActiveScope();
    final infos = await sync.readConflictResourceInfos();
    _requireActiveScope();
    conflicts = current;
    resourceInfos = infos;
    _pruneSelection();
  }

  void _pruneSelection() {
    final ids = conflicts.map((c) => c.conflictId).toSet();
    selectedConflictIds.removeWhere((id) => !ids.contains(id));
    if (conflicts.isEmpty) isSelecting = false;
  }

  Future<T?> _run<T>(
    Future<T> Function() action, {
    required String successMessage,
    String Function()? resultMessage,
    String Function()? failureMessage,
  }) async {
    if (!_canUpdate || isBusy) return null;
    isBusy = true;
    errorMessage = null;
    statusMessage = null;
    notifyListeners();
    try {
      final result = await action();
      _requireActiveScope();
      statusMessage = resultMessage?.call() ?? successMessage;
      return result;
    } catch (_) {
      if (!_canUpdate) return null;
      try {
        final pending = await sync.readPendingHandover();
        _requireActiveScope();
        final currentConflicts = await sync.readConflicts();
        _requireActiveScope();
        final infos = await sync.readConflictResourceInfos();
        _requireActiveScope();
        pendingHandover = pending;
        conflicts = currentConflicts;
        resourceInfos = infos;
        _pruneSelection();
      } catch (_) {}
      if (!_canUpdate) return null;
      errorMessage = failureMessage?.call() ?? 'Aktion fehlgeschlagen. Prüfe Verbindung, Übergabedaten und Sync-Status.';
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
