import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/local/local_mutation.dart';
import 'local_sync_store.dart';
import 'sync_repository.dart';

const _lastSyncedMetadataKey = 'last-synced-at';

/// Sichtbarer Sync-Zustand für Banner und Mehr-Menü.
@immutable
class SyncStatus {
  const SyncStatus({
    this.lastSyncedAtUtc,
    this.pendingCount = 0,
    this.isWriter = true,
  });

  /// Zeitpunkt des letzten Syncs, bei dem der Server erreicht wurde.
  final DateTime? lastSyncedAtUtc;

  /// Lokale Änderungen, die der Server noch nicht bestätigt hat.
  final int pendingCount;

  /// `false`, sobald das letzte Sync-Ergebnis ein anderes Schreibgerät
  /// meldete. Vor dem ersten Sync gilt `true`, damit kein Banner blinkt.
  final bool isWriter;

  SyncStatus copyWith({
    DateTime? lastSyncedAtUtc,
    int? pendingCount,
    bool? isWriter,
  }) => SyncStatus(
    lastSyncedAtUtc: lastSyncedAtUtc ?? this.lastSyncedAtUtc,
    pendingCount: pendingCount ?? this.pendingCount,
    isWriter: isWriter ?? this.isWriter,
  );

  @override
  bool operator ==(Object other) =>
      other is SyncStatus &&
      other.lastSyncedAtUtc == lastSyncedAtUtc &&
      other.pendingCount == pendingCount &&
      other.isWriter == isWriter;

  @override
  int get hashCode => Object.hash(lastSyncedAtUtc, pendingCount, isWriter);
}

/// Hält den [SyncStatus] eines Kontos aktuell: nach jedem Sync-Lauf und nach
/// jeder lokalen Änderung. Der Zeitpunkt des letzten Syncs überlebt Neustarts.
class SyncStatusTracker extends ValueNotifier<SyncStatus> {
  SyncStatusTracker({required this.store}) : super(const SyncStatus());

  final LocalSyncStore store;
  bool _disposed = false;
  Timer? _refreshTimer;

  /// Liest Zeitpunkt und Anzahl aus dem lokalen Speicher.
  Future<void> load() => _guarded(() async {
    final stored = await store.readSyncMetadata(_lastSyncedMetadataKey);
    final lastSynced = stored is String
        ? DateTime.tryParse(stored)?.toUtc()
        : null;
    _publish(
      value.copyWith(
        lastSyncedAtUtc: lastSynced,
        pendingCount: await _pendingCount(),
      ),
    );
  });

  /// Zählt kurz verzögert neu, damit viele Änderungen in Folge (Eingaben im
  /// Training) nur eine Abfrage auslösen.
  void scheduleRefresh() {
    if (_disposed) return;
    _refreshTimer?.cancel();
    _refreshTimer = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(refreshPending()),
    );
  }

  Future<void> refreshPending() => _guarded(() async {
    _publish(value.copyWith(pendingCount: await _pendingCount()));
  });

  /// Übernimmt das Ergebnis eines Sync-Laufs.
  Future<void> recordRun(SyncRunReport report, DateTime now) =>
      _guarded(() async {
        final reachedServer = switch (report.state) {
          SyncRunState.idle ||
          SyncRunState.synced ||
          SyncRunState.retryPending ||
          SyncRunState.inactiveClient => true,
          _ => false,
        };
        final writer = switch (report.state) {
          SyncRunState.inactiveClient => false,
          SyncRunState.idle ||
          SyncRunState.synced ||
          SyncRunState.retryPending => true,
          _ => value.isWriter,
        };
        final at = now.toUtc();
        if (reachedServer) {
          await store.writeSyncMetadata(
            _lastSyncedMetadataKey,
            at.toIso8601String(),
          );
        }
        _publish(
          value.copyWith(
            lastSyncedAtUtc: reachedServer ? at : null,
            pendingCount: await _pendingCount(),
            isWriter: writer,
          ),
        );
      });

  Future<int> _pendingCount() async => (await store.readOutbox())
      .where((mutation) => mutation.status != LocalMutationStatus.clean)
      .length;

  void _publish(SyncStatus next) {
    if (!_disposed) value = next;
  }

  /// Nach dem Schließen des Kontos darf ein spätes Ergebnis nichts mehr werfen.
  Future<void> _guarded(Future<void> Function() action) async {
    if (_disposed) return;
    try {
      await action();
    } catch (_) {
      // Der Status ist nur Anzeige; ein Lesefehler ändert die Daten nicht.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    super.dispose();
  }
}
