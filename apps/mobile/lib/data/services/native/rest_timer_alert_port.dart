/// Spielt einen Timerton in der App: zur Probe beim Auswählen und beim Ablauf,
/// solange keine Benachrichtigung erscheinen kann.
abstract interface class RestTimerAlertPort {
  Future<void> playSound(String soundId);
}
