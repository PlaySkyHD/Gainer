import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../../data/models/api/api_models.dart';
import '../../../data/services/auth/mobile_auth_controller.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';

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

  List<Widget> _invitationChildren(Uri link, GainerColors colors) => [
    Padding(
      padding: const EdgeInsets.fromLTRB(
        GainerSpacing.m,
        GainerSpacing.xs,
        GainerSpacing.m,
        0,
      ),
      child: Text(
        'Diesen Link einmalig sicher an die Person weitergeben.',
        style: GainerTypography.body.copyWith(color: colors.secondaryText),
      ),
    ),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: GainerSpacing.m),
      child: Text(
        link.toString(),
        style: GainerTypography.body.copyWith(color: colors.primaryText),
      ),
    ),
    if (_invitationExpiresAt case final expires?)
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: GainerSpacing.m),
        child: Text(
          'Gültig bis ${expires.toLocal()}',
          style: GainerTypography.label.copyWith(color: colors.secondaryText),
        ),
      ),
    GainerListRow(
      title: 'Einladungslink kopieren',
      onTap: () => Clipboard.setData(ClipboardData(text: link.toString())),
    ),
  ];

  List<Widget> _accountChildren(GainerColors colors) {
    if (_loading) {
      return const [
        Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CupertinoActivityIndicator()),
        ),
      ];
    }
    return [for (final account in _accounts) _accountRow(account, colors)];
  }

  Widget _accountRow(ApiAccountSummary account, GainerColors colors) => Row(
    children: [
      Expanded(
        child: GainerListRow(
          title: account.email,
          value: account.isActive ? 'Aktiv' : 'Deaktiviert',
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(right: GainerSpacing.m),
        child: CupertinoSwitch(
          value: account.isActive,
          onChanged: _isOwnAccount(account) || _busy
              ? null
              : (value) => _setStatus(account, value),
        ),
      ),
    ],
  );

  bool _isOwnAccount(ApiAccountSummary account) =>
      account.accountId.toLowerCase() ==
      widget.controller.account?.session.userId.toLowerCase();

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return CupertinoPageScaffold(
      backgroundColor: colors.background,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Kontoverwaltung'),
        backgroundColor: colors.background,
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(GainerSpacing.m),
          children: [
            GainerGroupedSection(
              header: 'Einladung ausstellen',
              children: [
                Padding(
                  padding: const EdgeInsets.all(GainerSpacing.m),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CupertinoTextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        placeholder: 'E-Mail-Adresse',
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _createInvitation(),
                        style: GainerTypography.body.copyWith(
                          color: colors.primaryText,
                        ),
                        placeholderStyle: GainerTypography.body.copyWith(
                          color: colors.placeholderText,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: GainerSpacing.m,
                          vertical: GainerSpacing.s,
                        ),
                        decoration: BoxDecoration(
                          color: colors.elevatedSurface,
                          borderRadius: BorderRadius.circular(
                            GainerRadii.field,
                          ),
                        ),
                      ),
                      const SizedBox(height: GainerSpacing.s),
                      GainerPillButton(
                        label: 'Einladung erstellen',
                        expand: true,
                        onPressed: _busy ? null : _createInvitation,
                      ),
                    ],
                  ),
                ),
                if (_issuedInvitation case final link?)
                  ..._invitationChildren(link, colors),
                if (_error case final message?)
                  Padding(
                    padding: const EdgeInsets.all(GainerSpacing.m),
                    child: Text(
                      message,
                      style: GainerTypography.body.copyWith(
                        color: colors.destructive,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: GainerSpacing.l),
            GainerGroupedSection(
              header: 'Konten',
              children: _accountChildren(colors),
            ),
            const SizedBox(height: GainerSpacing.m),
            GainerPillButton(
              label: 'Liste aktualisieren',
              variant: GainerPillVariant.tonal,
              expand: true,
              onPressed: _loading || _busy ? null : _load,
            ),
          ],
        ),
      ),
    );
  }
}
