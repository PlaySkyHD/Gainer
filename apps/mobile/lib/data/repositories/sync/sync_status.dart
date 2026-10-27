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
    this.writerKnown = false,
    this.upgradeRequired = false,
  });

  /// Zeitpunkt des letzten Syncs, bei dem der Server erreicht wurde.
  final DateTime? lastSyncedAtUtc;

  /// Lokale Änderungen, die der Server noch nicht bestätigt hat.
  final int pendingCount;

  /// `false`, sobald das letzte Sync-Ergebnis ein anderes Schreibgerät
  /// meldete. Vor dem ersten Sync gilt `true`, damit kein Banner blinkt.
  final bool isWriter;

  /// `true`, solange der letzte Sync-Lauf eine neuere App-Version verlangte
  /// (Server `upgrade_required` oder unbekannte Ressource im Pull).
  final bool upgradeRequired;

  /// `true`, sobald ein Sync-Lauf oder eine Übergabe in dieser Sitzung die
  /// Rolle geklärt hat. Sie wird nicht gespeichert; bis dahin ist [isWriter]
  /// nur ein Platzhalter und darf nicht als Aussage angezeigt werden.
  final bool writerKnown;

  SyncStatus copyWith({
    DateTime? lastSyncedAtUtc,
    int? pendingCount,
    bool? isWriter,
    bool? writerKnown,
    bool? upgradeRequired,
  }) => SyncStatus(
    writerKnown: writerKnown ?? this.writerKnown,
    lastSyncedAtUtc: lastSyncedAtUtc ?? this.lastSyncedAtUtc,
    pendingCount: pendingCount ?? this.pendingCount,
    isWriter: isWriter ?? this.isWriter,
    upgradeRequired: upgradeRequired ?? this.upgradeRequired,
  );

  @override
  bool operator ==(Object other) =>
      other is SyncStatus &&
      other.lastSyncedAtUtc == lastSyncedAtUtc &&
      other.pendingCount == pendingCount &&
      other.isWriter == isWriter &&
      other.writerKnown == writerKnown &&
      other.upgradeRequired == upgradeRequired;

  @override
  int get hashCode => Object.hash(
    lastSyncedAtUtc,
    pendingCount,
    isWriter,
    writerKnown,
    upgradeRequired,
  );
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
        final writerDecided = switch (report.state) {
          SyncRunState.inactiveClient ||
          SyncRunState.idle ||
          SyncRunState.synced ||
          SyncRunState.retryPending => true,
          _ => false,
        };
        final at = now.toUtc();
        if (reachedServer) {
          await store.writeSyncMetadata(
            _lastSyncedMetadataKey,
            at.toIso8601String(),
          );
        }
        // Nur ein Lauf, der Registrierung und Pull geschafft hat, löst
        // den Bedarf auf; Anmeldefehler oder ein laufender Sync nicht.
        final bool upgradeRequired;
        if (report.state == SyncRunState.upgradeRequired) {
          upgradeRequired = true;
        } else if (reachedServer) {
          upgradeRequired = false;
        } else {
          upgradeRequired = value.upgradeRequired;
        }
        _publish(
          value.copyWith(
            lastSyncedAtUtc: reachedServer ? at : null,
            pendingCount: await _pendingCount(),
            isWriter: writer,
            writerKnown: value.writerKnown || writerDecided,
            upgradeRequired: upgradeRequired,
          ),
        );
      });

  /// Nach einer erfolgreichen Übergabe ist dieses Gerät das Schreibgerät,
  /// noch bevor der nächste Sync-Lauf es meldet.
  void markWriter() {
    _publish(value.copyWith(isWriter: true, writerKnown: true));
  }

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
