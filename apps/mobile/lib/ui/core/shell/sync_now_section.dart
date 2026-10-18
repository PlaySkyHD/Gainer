import 'package:flutter/cupertino.dart';

import '../../../data/repositories/sync/sync_repository.dart';
import '../../../data/services/api/api_client.dart';
import '../components/components.dart';

/// Abschnitt „Synchronisierung“ im Mehr-Menü. Meldet der Server ein anderes
/// Schreibgerät, kann dieses iPhone nach Bestätigung übernehmen.
class SyncNowSection extends StatefulWidget {
  const SyncNowSection({
    required this.online,
    required this.synchronize,
    super.key,
  });

  final bool online;
  final Future<SyncRunReport> Function({bool takeOverWriting}) synchronize;

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
        _status = switch (result.state) {
          SyncRunState.synced =>
            takeOverWriting
                ? 'Dieses iPhone ist jetzt dein Schreibgerät. Änderungen synchronisiert.'
                : 'Änderungen synchronisiert.',
          SyncRunState.retryPending =>
            'Änderungen warten auf einen erneuten Sync-Versuch.',
          SyncRunState.authBlocked => 'Bitte melde dich erneut an; lokale Änderungen bleiben gespeichert.',
          SyncRunState.upgradeRequired =>
            'Aktualisiere die App, um die Synchronisierung fortzusetzen.',
          SyncRunState.inactiveClient => 'Ein anderes Gerät ist als Schreibgerät eingetragen. Änderungen von diesem iPhone werden erst übertragen, wenn es das Schreiben übernimmt.',
          SyncRunState.busy => 'Synchronisierung läuft bereits.',
          SyncRunState.idle =>
            takeOverWriting
                ? 'Dieses iPhone ist jetzt dein Schreibgerät.'
                : 'Keine ausstehenden Änderungen.',
        };
      });
    } on ApiException catch (error) {
      if (mounted) {
        setState(
          () => _status = switch (error.code) {
            'handover_required' => 'Für dieses Konto ist eine Übergabe vom bisherigen Gerät nötig: dort unter Sync & Gerätewechsel „Dieses Gerät ablösen“ wählen.',
            'handover_in_progress' => 'Gerade läuft eine Geräteübergabe. Schließe sie ab oder brich sie auf dem bisherigen Gerät ab.',
            _ => 'Synchronisierung nicht möglich. Lokale Änderungen bleiben erhalten.',
          },
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _status = 'Synchronisierung nicht möglich. Lokale Änderungen bleiben erhalten.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmTakeOver() async {
    final confirmed = await showGainerStackedDialog<bool>(
      context: context,
      title: 'Schreiben übernehmen?',
      message: 'Dieses iPhone wird dein Schreibgerät und überträgt seine Änderungen. Das bisher eingetragene Gerät kann danach nichts mehr hochladen; dort noch nicht synchronisierte Änderungen gehen verloren.',
      actions: const [
        GainerDialogAction(label: 'Übernehmen', value: true),
        GainerDialogAction(label: 'Abbrechen', value: false),
      ],
    );
    if (confirmed == true && mounted) await _sync(takeOverWriting: true);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.online && !_busy;
    return GainerGroupedSection(
      header: 'Synchronisierung',
      footer: _status,
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
