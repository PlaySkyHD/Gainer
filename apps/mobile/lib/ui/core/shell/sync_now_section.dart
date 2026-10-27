import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import '../../../data/repositories/sync/sync_repository.dart';
import '../../../data/repositories/sync/sync_status.dart';
import '../../../data/services/api/api_client.dart';
import '../components/components.dart';

/// Fragt nach, ob dieses iPhone das Schreiben übernehmen soll. Gemeinsam für
/// den Abschnitt unter Mehr und das Banner in den Tabs.
Future<bool> confirmTakeOverWriting(BuildContext context) async {
  final confirmed = await showGainerStackedDialog<bool>(
    context: context,
    title: 'Schreiben übernehmen?',
    message: 'Dieses iPhone wird dein Schreibgerät und überträgt seine Änderungen. Das bisher eingetragene Gerät kann danach nichts mehr hochladen; dort noch nicht synchronisierte Änderungen gehen verloren.',
    actions: const [
      GainerDialogAction(label: 'Übernehmen', value: true),
      GainerDialogAction(label: 'Abbrechen', value: false),
    ],
  );
  return confirmed == true;
}

/// Erklärt einen fehlgeschlagenen Sync-Versuch auf Deutsch.
String syncFailureMessage(Object error) {
  if (error is ApiException) {
    return switch (error.code) {
      'handover_required' => 'Für dieses Konto ist eine Übergabe vom bisherigen Gerät nötig: dort unter Sync & Gerätewechsel „Dieses Gerät ablösen“ wählen.',
      'handover_in_progress' => 'Gerade läuft eine Geräteübergabe. Schließe sie ab oder brich sie auf dem bisherigen Gerät ab.',
      _ =>
        'Synchronisierung nicht möglich. Lokale Änderungen bleiben erhalten.',
    };
  }
  return 'Synchronisierung nicht möglich. Lokale Änderungen bleiben erhalten.';
}

/// Erklärt das Ergebnis eines Sync-Laufs auf Deutsch. Gemeinsam für den
/// Abschnitt unter Mehr und das Banner in den Tabs.
String syncRunMessage(SyncRunState state, {required bool takeOverWriting}) =>
    switch (state) {
      SyncRunState.synced =>
        takeOverWriting
            ? 'Dieses iPhone ist jetzt dein Schreibgerät. Änderungen synchronisiert.'
            : 'Änderungen synchronisiert.',
      SyncRunState.retryPending =>
        'Änderungen warten auf einen erneuten Sync-Versuch.',
      SyncRunState.authBlocked =>
        'Bitte melde dich erneut an; lokale Änderungen bleiben gespeichert.',
      SyncRunState.upgradeRequired =>
        'Aktualisiere die App, um die Synchronisierung fortzusetzen.',
      SyncRunState.inactiveClient => 'Ein anderes Gerät ist als Schreibgerät eingetragen. Änderungen von diesem iPhone werden erst übertragen, wenn es das Schreiben übernimmt.',
      SyncRunState.busy => 'Synchronisierung läuft bereits.',
      SyncRunState.idle =>
        takeOverWriting
            ? 'Dieses iPhone ist jetzt dein Schreibgerät.'
            : 'Keine ausstehenden Änderungen.',
    };

/// Erklärt, warum eine Übernahme des Schreibens nicht geklappt hat; `null`,
/// wenn nichts zu erklären ist. `synced`, `idle` und `retryPending` machen
/// das Gerät zum Schreibgerät (die Änderungen folgen beim nächsten Versuch),
/// bei `upgradeRequired` zeigt das Banner stattdessen den Update-Hinweis.
String? takeOverProblemMessage(SyncRunState state) => switch (state) {
  SyncRunState.synced ||
  SyncRunState.idle ||
  SyncRunState.retryPending ||
  SyncRunState.upgradeRequired => null,
  SyncRunState.authBlocked => syncRunMessage(state, takeOverWriting: true),
  // „busy“ meldet auch pausierte Schreibzugriffe während einer Übergabe.
  SyncRunState.busy => 'Die Synchronisierung läuft gerade oder ist während einer Geräteübergabe pausiert. Versuche es später erneut.',
  SyncRunState.inactiveClient => 'Der Server hat dir das Schreiben nicht zugeteilt. Versuche es später erneut oder prüfe das andere Gerät.',
};

/// „gerade eben“, „vor 2 Min.“, „vor 3 Std.“, danach das Datum.
String relativeSyncTime(DateTime lastSyncedAtUtc, DateTime now) {
  final age = now.toUtc().difference(lastSyncedAtUtc.toUtc());
  if (age.inMinutes < 1) return 'gerade eben';
  if (age.inMinutes < 60) return 'vor ${age.inMinutes} Min.';
  if (age.inHours < 24) return 'vor ${age.inHours} Std.';
  final local = lastSyncedAtUtc.toLocal();
  return 'am ${local.day.toString().padLeft(2, '0')}.'
      '${local.month.toString().padLeft(2, '0')}.${local.year}';
}

/// Fußnote unter Mehr: „Zuletzt synchronisiert vor 2 Min. · 3 ausstehend“.
String syncStatusLine(SyncStatus status, DateTime now) {
  final last = status.lastSyncedAtUtc;
  final when = last == null
      ? 'Noch nicht synchronisiert'
      : 'Zuletzt synchronisiert ${relativeSyncTime(last, now)}';
  return '$when · ${status.pendingCount} ausstehend';
}

/// Abschnitt „Synchronisierung“ im Mehr-Menü. Meldet der Server ein anderes
/// Schreibgerät, kann dieses iPhone nach Bestätigung übernehmen.
class SyncNowSection extends StatefulWidget {
  const SyncNowSection({
    required this.online,
    required this.synchronize,
    this.status,
    this.clock = DateTime.now,
    super.key,
  });

  final bool online;
  final Future<SyncRunReport> Function({bool takeOverWriting}) synchronize;

  /// Zustand für die Fußnote; ohne Angabe entfällt sie.
  final ValueListenable<SyncStatus>? status;
  final DateTime Function() clock;

  @override
  State<SyncNowSection> createState() => _SyncNowSectionState();
}

class _SyncNowSectionState extends State<SyncNowSection> {
  bool _busy = false;
  String? _status;

  /// Zeigt die Übernahme an, nachdem der Server dieses Gerät als nicht
  /// schreibberechtigt gemeldet hat.
  bool _inactive = false;

  Future<void> _sync({bool takeOverWriting = false}) async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final result = await widget.synchronize(takeOverWriting: takeOverWriting);
      if (!mounted) {
        return;
      }
      setState(() {
        _inactive = result.state == SyncRunState.inactiveClient;
        _status = syncRunMessage(
          result.state,
          takeOverWriting: takeOverWriting,
        );
      });
    } catch (error) {
      if (mounted) setState(() => _status = syncFailureMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmTakeOver() async {
    if (await confirmTakeOverWriting(context) && mounted) {
      await _sync(takeOverWriting: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    if (status == null) return _section(null);
    return ValueListenableBuilder<SyncStatus>(
      valueListenable: status,
      builder: (context, value, _) =>
          _section(syncStatusLine(value, widget.clock())),
    );
  }

  Widget _section(String? statusLine) {
    final enabled = widget.online && !_busy;
    final footer = [?_status, ?statusLine].join('\n');
    return GainerGroupedSection(
      header: 'Synchronisierung',
      footer: footer.isEmpty ? null : footer,
      children: [
        GainerListRow(
          title: 'Jetzt synchronisieren',
          leadingIcon: CupertinoIcons.arrow_clockwise,
          trailing: _busy ? const CupertinoActivityIndicator() : null,
          onTap: enabled ? _sync : null,
        ),
        if (_inactive)
          GainerListRow(
            key: const ValueKey('sync-take-over'),
            title: 'Dieses iPhone als Schreibgerät verwenden',
            leadingIcon: CupertinoIcons.device_phone_portrait,
            onTap: enabled ? _confirmTakeOver : null,
          ),
      ],
    );
  }
}
