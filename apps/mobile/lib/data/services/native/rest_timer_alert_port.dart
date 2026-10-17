import 'package:flutter/services.dart';

/// Kurzer Ton beim Ablauf des Pausentimers, solange die App im Vordergrund ist.
abstract interface class RestTimerAlertPort {
  Future<void> playExpiry();
}

/// Systemton ohne eigenes Audio-Asset; keine zusätzliche Abhängigkeit.
final class SystemRestTimerAlertPort implements RestTimerAlertPort {
  const SystemRestTimerAlertPort();

  @override
  Future<void> playExpiry() => SystemSound.play(SystemSoundType.alert);
}
