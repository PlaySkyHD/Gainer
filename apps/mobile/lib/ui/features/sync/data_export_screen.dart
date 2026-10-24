import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import '../../../data/repositories/sync/data_export_service.dart';
import '../../../data/repositories/sync/sync_status.dart';
import '../../../data/services/api/api_client.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';

/// Alle eigenen Daten als JSON-Datei exportieren und teilen.
class DataExportScreen extends StatefulWidget {
  const DataExportScreen({
    required this.service,
    required this.online,
    this.status,
    super.key,
  });

  final DataExportService service;
  final bool online;

  /// Für den Hinweis auf noch nicht gesendete Änderungen.
  final ValueListenable<SyncStatus>? status;

  @override
  State<DataExportScreen> createState() => _DataExportScreenState();
}

class _DataExportScreenState extends State<DataExportScreen> {
  bool _busy = false;
  String? _error;

  static const _contents =
      'Die JSON-Datei enthält deine Trainings, Pläne, Cardio-Einheiten, '
      'Ernährungstage, Gerichte, Ziele und Check-ins. Passkeys, Geräte und '
      'Verbindungen sind nicht enthalten.';

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.exportAndShare();
    } on ApiException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.statusCode == 429
              ? 'Du hast gerade mehrere Exporte erstellt. Versuche es in '
                    'einer Viertelstunde erneut.'
              : _failed,
        );
      }
    } on Object {
      if (mounted) setState(() => _error = _failed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _failed =
      'Der Export hat nicht geklappt. Prüfe deine Verbindung und versuche es '
      'erneut.';

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final status = widget.status;
    return GainerScaffold(
      title: 'Daten exportieren',
      children: [
        if (status == null)
          _section(colors, 0)
        else
          ValueListenableBuilder<SyncStatus>(
            valueListenable: status,
            builder: (context, value, _) =>
                _section(colors, value.pendingCount),
          ),
        if (_error case final message?)
          Padding(
            padding: const EdgeInsets.only(top: GainerSpacing.s),
            child: Text(
              message,
              key: const ValueKey('data-export-error'),
              textAlign: TextAlign.center,
              style: GainerTypography.body.copyWith(color: colors.destructive),
            ),
          ),
      ],
    );
  }

  Widget _section(GainerColors colors, int pendingCount) {
    final notes = [
      if (!widget.online) 'Der Export geht nur mit Verbindung.',
      if (pendingCount > 0)
        '${pendingCount == 1 ? '1 Änderung ist noch nicht gesendet und fehlt' : '$pendingCount Änderungen sind noch nicht gesendet und fehlen'} '
            'im Export. Synchronisiere zuerst unter „Sync & Gerätewechsel“.',
      _contents,
    ];
    return GainerGroupedSection(
      footer: notes.join('\n\n'),
      children: [
        GainerListRow(
          key: const ValueKey('data-export-start'),
          title: 'Export erstellen',
          leadingIcon: CupertinoIcons.square_arrow_up,
          trailing: _busy
              ? CupertinoActivityIndicator(color: colors.secondaryText)
              : null,
          onTap: widget.online && !_busy ? _export : null,
        ),
      ],
    );
  }
}
