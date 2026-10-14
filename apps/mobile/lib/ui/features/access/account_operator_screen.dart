import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../../data/models/api/api_models.dart';
import '../../../data/services/auth/mobile_auth_controller.dart';

class AccountOperatorScreen extends StatefulWidget {
  const AccountOperatorScreen({required this.controller, super.key});

  final MobileAuthController controller;

  @override
  State<AccountOperatorScreen> createState() => _AccountOperatorScreenState();
}

class _AccountOperatorScreenState extends State<AccountOperatorScreen> {
  final _email = TextEditingController();
  List<ApiAccountSummary> _accounts = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  Uri? _issuedInvitation;
  DateTime? _invitationExpiresAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final accounts = await widget.controller.listOperatorAccounts();
      if (!mounted) return;
      setState(() => _accounts = accounts);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = 'Konten konnten nicht geladen werden. Prüfe deine Verbindung und Rolle.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createInvitation() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Gib die E-Mail-Adresse des neuen Kontos ein.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _issuedInvitation = null;
    });
    try {
      final invitation = await widget.controller.createOperatorInvitation(
        email,
      );
      final link = widget.controller.configuration.trustedOrigin.resolve(
        invitation.activationPath,
      );
      if (!mounted) return;
      setState(() {
        _issuedInvitation = link;
        _invitationExpiresAt = invitation.expiresAt;
      });
      await _load();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Die Einladung konnte nicht erstellt werden.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStatus(ApiAccountSummary account, bool active) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.setOperatorAccountStatus(
        account.accountId,
        active,
      );
      await _load();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Der Kontostatus konnte nicht geändert werden.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(
      middle: Text('Kontoverwaltung'),
    ),
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Einladung ausstellen', style: TextStyle(fontSize: 20)),
          const SizedBox(height: 12),
          CupertinoTextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            placeholder: 'E-Mail-Adresse',
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _createInvitation(),
          ),
          const SizedBox(height: 8),
          CupertinoButton.filled(
            onPressed: _busy ? null : _createInvitation,
            child: const Text('Einladung erstellen'),
          ),
          if (_issuedInvitation case final link?) ...[
            const SizedBox(height: 8),
            const Text(
              'Diesen Link einmalig sicher an die Person weitergeben.',
            ),
            Text(link.toString()),
            if (_invitationExpiresAt case final expires?)
              Text('Gültig bis ${expires.toLocal()}'),
            CupertinoButton(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: link.toString())),
              child: const Text('Einladungslink kopieren'),
            ),
          ],
          if (_error case final message?) ...[
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(
                color: CupertinoColors.systemRed.resolveFrom(context),
              ),
            ),
          ],
          const SizedBox(height: 26),
          const Text('Konten', style: TextStyle(fontSize: 20)),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CupertinoActivityIndicator()),
            )
          else
            for (final account in _accounts)
              CupertinoListTile(
                title: Text(account.email),
                subtitle: Text(account.isActive ? 'Aktiv' : 'Deaktiviert'),
                trailing: CupertinoSwitch(
                  value: account.isActive,
                  onChanged:
                      _busy ||
                          account.accountId.toLowerCase() ==
                              widget.controller.account?.session.userId
                                  .toLowerCase()
                      ? null
                      : (value) => _setStatus(account, value),
                ),
              ),
          CupertinoButton(
            onPressed: _loading || _busy ? null : _load,
            child: const Text('Liste aktualisieren'),
          ),
        ],
      ),
    ),
  );
}
