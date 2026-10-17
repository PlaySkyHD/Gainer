import 'package:flutter/cupertino.dart';

import '../../../data/services/auth/mobile_auth_controller.dart';
import '../../core/components/components.dart';
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
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return CupertinoPageScaffold(
      backgroundColor: colors.background,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              padding: const EdgeInsets.all(GainerSpacing.l),
              shrinkWrap: true,
              children: [
                Icon(
                  CupertinoIcons.sportscourt,
                  size: 52,
                  color: colors.accent,
                ),
                const SizedBox(height: 18),
                Text(
                  'Gainer',
                  textAlign: TextAlign.center,
                  style: GainerTypography.largeTitle.copyWith(
                    color: colors.primaryText,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Melde dich mit deinem bestehenden Konto an.',
                  textAlign: TextAlign.center,
                  style: GainerTypography.body.copyWith(
                    color: colors.secondaryText,
                  ),
                ),
                const SizedBox(height: 28),
                GainerSegmentedControl<bool>(
                  options: const {
                    false: 'Anmelden',
                    true: 'Einladung annehmen',
                  },
                  value: _acceptingInvitation,
                  onChanged: (value) {
                    if (_busy) return;
                    setState(() => _acceptingInvitation = value);
                  },
                ),
                const SizedBox(height: 18),
                if (_acceptingInvitation)
                  _AuthField(
                    controller: _invitation,
                    keyboardType: TextInputType.url,
                    placeholder: 'Einladungscode oder Einladungslink',
                    textInputAction: TextInputAction.next,
                  )
                else
                  _AuthField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username],
                    placeholder: 'E-Mail-Adresse',
                    textInputAction: TextInputAction.next,
                  ),
                const SizedBox(height: 12),
                _AuthField(
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
                      style: GainerTypography.body.copyWith(
                        color: colors.destructive,
                      ),
                    ),
                  ),
                if (widget.controller.statusMessage case final message?)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: GainerTypography.body.copyWith(
                        color: colors.secondaryText,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                GainerPillButton(
                  label: _acceptingInvitation
                      ? 'Einladung bestätigen'
                      : 'Anmelden',
                  expand: true,
                  isLoading: _busy,
                  onPressed: _busy ? null : _login,
                ),
                const SizedBox(height: 14),
                Text(
                  'Deine Trainings- und Ernährungseinträge werden pro Konto lokal gespeichert und bleiben bei einem Verbindungsabbruch erhalten.',
                  textAlign: TextAlign.center,
                  style: GainerTypography.label.copyWith(
                    color: colors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

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

class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.controller,
    required this.placeholder,
    this.keyboardType,
    this.autofillHints,
    this.obscureText = false,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String placeholder;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final bool obscureText;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return CupertinoTextField(
      controller: controller,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      placeholder: placeholder,
      obscureText: obscureText,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      style: GainerTypography.body.copyWith(color: colors.primaryText),
      placeholderStyle: GainerTypography.body.copyWith(
        color: colors.placeholderText,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: GainerSpacing.m,
        vertical: GainerSpacing.s,
      ),
      decoration: BoxDecoration(
        color: colors.elevatedSurface,
        borderRadius: BorderRadius.circular(GainerRadii.field),
      ),
    );
  }
}
