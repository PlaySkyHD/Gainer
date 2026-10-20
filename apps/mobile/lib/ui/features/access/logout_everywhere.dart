import 'package:flutter/cupertino.dart';

import '../../core/components/components.dart';

/// Fragt nach und meldet alle Geräte des Kontos ab. Scheitert der Server,
/// bleibt dieses Gerät angemeldet und ein Dialog erklärt es.
Future<void> confirmLogoutEverywhere(
  BuildContext context,
  Future<void> Function() logoutEverywhere,
) async {
  final confirmed = await showGainerStackedDialog<bool>(
    context: context,
    title: 'Auf allen Geräten abmelden?',
    message: 'Alle Geräte mit deinem Konto werden abgemeldet, auch dieses. Deine Passkeys bleiben erhalten; entferne unbekannte unter Passkeys.',
    actions: const [
      GainerDialogAction(label: 'Abmelden', value: true, destructive: true),
      GainerDialogAction(label: 'Abbrechen', value: false),
    ],
  );
  if (confirmed != true) return;
  try {
    await logoutEverywhere();
  } catch (_) {
    if (!context.mounted) return;
    await showGainerStackedDialog<void>(
      context: context,
      title: 'Abmelden nicht möglich',
      message: 'Die anderen Geräte konnten nicht abgemeldet werden. Prüfe die Verbindung und versuche es erneut.',
      actions: const [GainerDialogAction(label: 'OK', value: null)],
    );
  }
}
