import '../../../domain/models/cardio/cardio_session.dart';
import '../../services/platform/platform_ports.dart';
import '../cardio/cardio_repository.dart';
import '../sync/local_sync_store.dart';

/// Stand des Apple-Health-Exports einer Cardio-Einheit.
class CardioExportState {
  const CardioExportState({
    required this.exported,
    this.syncVersion,
    this.exportedAtUtc,
    this.failed = false,
  });

  static const none = CardioExportState(exported: false);

  /// Die Einheit liegt in Apple Health („In Apple Health gesichert“).
  final bool exported;

  /// Version, mit der zuletzt exportiert wurde.
  final int? syncVersion;
  final DateTime? exportedAtUtc;

  /// Der letzte Versuch ist fehlgeschlagen; ein neuer Versuch ist möglich.
  final bool failed;
}

/// Exportiert beendete Cardio-Einheiten nach Apple Health und führt darüber
/// ein lokales Ledger (`health-ledger:cardio-export:<id>`). Dubletten verhindert
/// HealthKit über Sync-Identifier und -Version.
class CardioHealthExporter {
  CardioHealthExporter({
    required this.store,
    required this.repository,
    required this.platform,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final LocalSyncStore store;
  final CardioRepository repository;
  final CardioHealthPlatform platform;
  final DateTime Function() _clock;

  static String ledgerKey(String sessionId) =>
      'health-ledger:cardio-export:$sessionId';

  Future<CardioExportState> exportState(String sessionId) async {
    final raw = await store.readSyncMetadata(ledgerKey(sessionId));
    if (raw is! Map<String, dynamic>) return CardioExportState.none;
    if (raw['status'] == 'failed') {
      return const CardioExportState(exported: false, failed: true);
    }
    return CardioExportState(
      exported: raw['status'] == 'saved' || raw['status'] == 'alreadyPresent',
      syncVersion: raw['syncVersion'] as int?,
      exportedAtUtc: DateTime.tryParse(raw['recordedAtUtc'] as String? ?? '')
          ?.toUtc(),
    );
  }

  static int _syncVersion(int? serverVersion, int optimisticVersion) {
    if (serverVersion != null && serverVersion > 0) return serverVersion;
    return optimisticVersion < 1 ? 1 : optimisticVersion;
  }

  /// Schreibt die Einheit nach Apple Health. Die Version ist die Server-
  /// Version, solange die Einheit synchronisiert ist, sonst die lokale
  /// optimistische Version.
  Future<WorkoutExportReceipt> export(String sessionId) async {
    final row = await store.readAggregate(
      cardioSessionAggregateType,
      sessionId,
    );
    if (row == null) {
      throw StateError('Die Cardio-Einheit ist nicht verfügbar.');
    }
    final session = CardioSession.fromJson(
      (row.workingCopy as Map).cast<String, dynamic>(),
    );
    if (session.deletedAtUtc != null) {
      throw StateError('Gelöschte Einheiten lassen sich nicht exportieren.');
    }
    final syncVersion = _syncVersion(row.serverVersion, row.optimisticVersion);
    try {
      await platform.requestWriteAuthorization();
      final receipt = await platform.exportCardioSession(
        CardioHealthExport(
          accountId: store.accountId,
          sessionId: sessionId,
          syncVersion: syncVersion,
          activityType: session.activityType.wireName,
          startedAtUtc: session.startedAtUtc,
          endedAtUtc: session.endedAtUtc,
          sampleIntervalSeconds: session.sampleIntervalSeconds,
          heartRateBpm: session.heartRateBpm,
          distanceKm: session.distanceKm,
          energyKcal: session.energyKcal,
        ),
      );
      await store.writeSyncMetadata(ledgerKey(sessionId), {
        'accountId': store.accountId,
        'sessionId': sessionId,
        'syncIdentifier': receipt.syncIdentifier,
        'syncVersion': receipt.syncVersion,
        'status': receipt.status.name,
        'recordedAtUtc': _clock().toUtc().toIso8601String(),
      });
      return receipt;
    } catch (_) {
      // Ein früherer erfolgreicher Export bleibt im Ledger stehen.
      if (!(await exportState(sessionId)).exported) {
        await store.writeSyncMetadata(ledgerKey(sessionId), {
          'accountId': store.accountId,
          'sessionId': sessionId,
          'syncVersion': syncVersion,
          'status': 'failed',
          'retryable': true,
          'recordedAtUtc': _clock().toUtc().toIso8601String(),
        });
      }
      rethrow;
    }
  }
}
