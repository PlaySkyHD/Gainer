import 'package:flutter/cupertino.dart';

import '../../../data/models/api/api_models.dart';
import '../../../data/services/auth/mobile_auth_controller.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';

/// Passkeys des Kontos: anlegen (Face ID) und per Wischen entfernen.
class PasskeysScreen extends StatefulWidget {
  const PasskeysScreen({required this.controller, super.key});

  final MobileAuthController controller;

  @override
  State<PasskeysScreen> createState() => _PasskeysScreenState();
}

class _PasskeysScreenState extends State<PasskeysScreen> {
  List<ApiPasskey> _passkeys = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  bool get _online => widget.controller.account?.online ?? false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_online) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final passkeys = await widget.controller.listPasskeys();
      if (!mounted) return;
      setState(() => _passkeys = passkeys);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error =
            'Passkeys konnten nicht geladen werden. Prüfe deine Verbindung.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final created = await widget.controller.addPasskey();
      if (!mounted) return;
      if (created != null) setState(() => _passkeys = [..._passkeys, created]);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error =
            'Der Passkey konnte nicht angelegt werden. Versuche es erneut.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(ApiPasskey passkey) async {
    final previous = _passkeys;
    setState(() {
      _passkeys = [
        for (final item in _passkeys)
          if (item.id != passkey.id) item,
      ];
      _error = null;
    });
    try {
      await widget.controller.removePasskey(passkey.id);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _passkeys = previous;
        _error = 'Der Passkey konnte nicht entfernt werden.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return GainerScaffold(
      title: 'Passkeys',
      trailing: [
        GainerToolbarButton(
          icon: CupertinoIcons.add,
          semanticLabel: 'Passkey hinzufügen',
          onPressed: _online && !_busy && !_loading ? _add : null,
        ),
      ],
      children: [
        GainerGroupedSection(
          footer: _online
              ? 'Mit einem Passkey meldest du dich per Face ID an, ohne Passwort. Er liegt im iCloud-Schlüsselbund. Dein Passwort bleibt gültig.'
              : 'Passkeys lassen sich nur mit Verbindung verwalten.',
          children: _rows(colors),
        ),
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

  List<Widget> _rows(GainerColors colors) {
    if (_loading) {
      return const [
        Padding(
          padding: EdgeInsets.all(GainerSpacing.l),
          child: Center(child: CupertinoActivityIndicator()),
        ),
      ];
    }
    if (_passkeys.isEmpty) {
      return [
        GainerListRow(
          title: 'Passkey hinzufügen',
          leadingIcon: CupertinoIcons.lock_shield,
          onTap: _online && !_busy ? _add : null,
        ),
      ];
    }
    return [
      for (final passkey in _passkeys)
        GainerSwipeToDelete(
          dismissKey: ValueKey('passkey-${passkey.id}'),
          label: 'Entfernen',
          confirm: () => confirmGainerDelete(
            context,
            title: 'Passkey entfernen?',
            message: 'Danach meldest du dich auf diesem Weg nicht mehr an. Entferne ihn zusätzlich in den iPhone-Einstellungen unter Passwörter.',
            deleteLabel: 'Entfernen',
          ),
          onDeleted: () => _remove(passkey),
          child: GainerListRow(
            title: passkey.name,
            subtitle: 'Erstellt am ${_date(passkey.createdAt)}',
            leadingIcon: CupertinoIcons.lock_shield,
          ),
        ),
    ];
  }

  static String _date(DateTime value) {
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return '$day.$month.${local.year}';
  }
}
