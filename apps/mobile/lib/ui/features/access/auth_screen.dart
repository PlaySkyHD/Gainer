import 'package:flutter/cupertino.dart';

import '../../../data/services/auth/mobile_auth_controller.dart';
import '../../core/theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({required this.controller, super.key});
  final MobileAuthController controller;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _invitation = TextEditingController();
  bool _busy = false;
  bool _acceptingInvitation = false;
  String? _localError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _invitation.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() => _localError = null);
    setState(() => _busy = true);
    if (_acceptingInvitation) {
      final token = _extractInvitationToken(_invitation.text);
      if (token.isEmpty) {
        _localError =
            'Gib einen gültigen Einladungscode oder Einladungslink ein.';
      } else {
        await widget.controller.acceptInvitation(token, _password.text);
      }
    } else {
      await widget.controller.login(_email.text, _password.text);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    child: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: ListView(
            padding: const EdgeInsets.all(24),
            shrinkWrap: true,
            children: [
              const Icon(CupertinoIcons.sportscourt, size: 52),
              const SizedBox(height: 18),
              Text(
                'Gainer',
                textAlign: TextAlign.center,
                style: CupertinoTheme.of(context)
                    .textTheme
                    .navLargeTitleTextStyle
                    .copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              const Text(
                'Melde dich mit deinem bestehenden Konto an.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              CupertinoSlidingSegmentedControl<bool>(
                groupValue: _acceptingInvitation,
                children: const {
                  false: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: Text('Anmelden'),
                  ),
                  true: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: Text('Einladung annehmen'),
                  ),
                },
                onValueChanged: (value) {
                  if (_busy) return;
                  setState(() => _acceptingInvitation = value ?? false);
                },
              ),
              const SizedBox(height: 18),
              if (_acceptingInvitation)
                CupertinoTextField(
                  controller: _invitation,
                  keyboardType: TextInputType.url,
                  placeholder: 'Einladungscode oder Einladungslink',
                  textInputAction: TextInputAction.next,
                )
              else
                CupertinoTextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.username],
                  placeholder: 'E-Mail-Adresse',
                  textInputAction: TextInputAction.next,
                ),
              const SizedBox(height: 12),
              CupertinoTextField(
                controller: _password,
                obscureText: true,
                autofillHints: [
                  _acceptingInvitation
                      ? AutofillHints.newPassword
                      : AutofillHints.password,
                ],
                placeholder: _acceptingInvitation
                    ? 'Neues Passwort'
                    : 'Passwort',
                onSubmitted: (_) => _login(),
              ),
              if ((widget.controller.errorMessage ?? _localError)
                  case final message?)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: CupertinoColors.systemRed.resolveFrom(context),
                    ),
                  ),
                ),
              if (widget.controller.statusMessage case final message?)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: GainerTheme.secondaryText(context)),
                  ),
                ),
              const SizedBox(height: 20),
              CupertinoButton.filled(
                onPressed: _busy ? null : _login,
                child: _busy
                    ? const CupertinoActivityIndicator()
                    : Text(
                        _acceptingInvitation
                            ? 'Einladung bestätigen'
                            : 'Anmelden',
                      ),
              ),
              const SizedBox(height: 14),
              Text(
                'Deine Trainings- und Ernährungseinträge werden pro Konto lokal gespeichert und bleiben bei einem Verbindungsabbruch erhalten.',
                textAlign: TextAlign.center,
                style: TextStyle(color: GainerTheme.secondaryText(context)),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  String _extractInvitationToken(String value) {
    final input = value.trim();
    final uri = Uri.tryParse(input);
    if (uri == null ||
        uri.path != '/accept-invitation' ||
        (!uri.hasScheme && !input.startsWith('/accept-invitation'))) {
      return input;
    }
    return uri.queryParameters['token']?.trim() ?? '';
  }
}
