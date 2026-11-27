import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../../data/models/api/api_models.dart';
import '../../../data/services/api/api_client.dart';
import '../../../data/services/auth/mobile_auth_controller.dart';
import '../../core/components/components.dart';
import '../../core/german_date_time.dart';
import '../../core/theme.dart';

/// Pfad des MCP-Endpunkts, den externe Assistenten wie ChatGPT aufrufen.
const connectorMcpPath = '/api/v1/mcp';

/// Per OAuth verbundene Assistenten (z. B. ChatGPT): ansehen und trennen.
class ConnectedAppsScreen extends StatefulWidget {
  const ConnectedAppsScreen({required this.controller, super.key});

  final MobileAuthController controller;

  @override
  State<ConnectedAppsScreen> createState() => _ConnectedAppsScreenState();
}

class _ConnectedAppsScreenState extends State<ConnectedAppsScreen> {
  List<ApiConnectorSession> _connectors = const [];
  bool _loading = true;
  bool _loadFailed = false;
  bool _busy = false;
  bool _copied = false;
  String? _error;

  bool get _online => widget.controller.account?.online ?? false;

  String? get _mcpUrl {
    final account = widget.controller.account;
    if (account == null) return null;
    return '${account.api.configuration.canonicalApiOrigin}$connectorMcpPath';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// [quiet] lädt im Hintergrund nach, ohne die Liste durch den Ladeindikator
  /// zu ersetzen.
  Future<void> _load({bool quiet = false}) async {
    if (!_online) {
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
      return;
    }
    setState(() {
      if (!quiet) _loading = true;
      _loadFailed = false;
    });
    try {
      final connectors = await widget.controller.listConnectors();
      if (!mounted) return;
      setState(() => _connectors = connectors);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadFailed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    if (_busy) return;
    await _load(quiet: true);
  }

  Future<void> _showActions(ApiConnectorSession connector) async {
    final disconnect = await showGainerActionSheet<bool>(
      context: context,
      title: connector.name,
      groups: [
        [
          const GainerSheetAction(
            label: 'Trennen',
            icon: CupertinoIcons.xmark_circle,
            value: true,
            destructive: true,
            hint: 'Die App verliert sofort den Zugriff auf dein Konto.',
          ),
        ],
      ],
    );
    if (disconnect == true && mounted && !_busy) await _disconnect(connector);
  }

  Future<void> _disconnect(ApiConnectorSession connector) async {
    setState(() {
      _busy = true;
      _error = null;
      _connectors = [
        for (final item in _connectors)
          if (item.id != connector.id) item,
      ];
    });
    try {
      await widget.controller.removeConnector(connector.id);
    } on ApiException catch (error) {
      // 404: schon getrennt, etwa auf einem anderen Gerät.
      if (error.statusCode != 404 && mounted) {
        setState(() => _error = 'Die Verbindung konnte nicht getrennt werden.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Die Verbindung konnte nicht getrennt werden.');
      }
    }
    if (!mounted) return;
    await _load(quiet: true);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _copyUrl(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return GainerScaffold(
      title: 'Verbundene Apps',
      onRefresh: _online ? _refresh : null,
      children: [
        _section(),
        if (_error case final message?)
          Padding(
            padding: const EdgeInsets.only(top: GainerSpacing.s),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: GainerTypography.body.copyWith(color: colors.destructive),
            ),
          ),
      ],
    );
  }

  Widget _section() {
    if (_loading) {
      return const GainerGroupedSection(
        children: [
          Padding(
            padding: EdgeInsets.all(GainerSpacing.l),
            child: Center(child: CupertinoActivityIndicator()),
          ),
        ],
      );
    }
    if (_loadFailed) {
      return GainerGroupedSection(
        footer: _online
            ? 'Verbundene Apps konnten nicht geladen werden. Prüfe deine Verbindung.'
            : 'Verbundene Apps lassen sich nur mit Verbindung verwalten.',
        children: [
          GainerListRow(
            title: 'Erneut versuchen',
            leadingIcon: CupertinoIcons.arrow_clockwise,
            onTap: _busy ? null : _load,
          ),
        ],
      );
    }
    if (_connectors.isEmpty) return _emptySection();
    return GainerGroupedSection(
      footer: 'Getrennte Apps verlieren sofort den Zugriff auf dein Konto.',
      children: [for (final connector in _connectors) _row(connector)],
    );
  }

  Widget _row(ApiConnectorSession connector) {
    final row = GainerListRow(
      title: connector.name,
      subtitle:
          'Verbunden am ${formatGermanDate(connector.createdAt)} · '
          'zuletzt genutzt ${formatGermanDate(connector.lastUsedAt)}',
      leadingIcon: CupertinoIcons.sparkles,
      onTap: _busy ? null : () => _showActions(connector),
    );
    // Während eine Trennung läuft, lässt sich nichts weiter trennen.
    if (_busy) return row;
    return GainerSwipeToDelete(
      dismissKey: ValueKey('connector-${connector.id}'),
      label: 'Trennen',
      confirm: () => confirmGainerDelete(
        context,
        title: '${connector.name} trennen?',
        message: 'Die App verliert sofort den Zugriff auf dein Konto.',
        deleteLabel: 'Trennen',
      ),
      onDeleted: () => _disconnect(connector),
      child: row,
    );
  }

  Widget _emptySection() {
    final url = _mcpUrl;
    return GainerGroupedSection(
      children: [
        const GainerListRow(
          title: 'Kein Assistent verbunden',
          subtitle: 'Füge in ChatGPT eine App mit dieser Adresse hinzu und bestätige sie mit deinem Passkey.',
          leadingIcon: CupertinoIcons.sparkles,
        ),
        if (url != null)
          Semantics(
            hint: 'Adresse kopieren',
            child: GainerListRow(
              key: const ValueKey('connector-mcp-url'),
              title: url,
              subtitle: _copied ? 'Kopiert' : 'Tippen zum Kopieren',
              leadingIcon: CupertinoIcons.doc_on_doc,
              onTap: () => _copyUrl(url),
            ),
          ),
      ],
    );
  }
}
