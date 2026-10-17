/// Countdown als „mm:ss“, etwa „03:00“ oder „00:45“. Negative Werte zeigen „00:00“.
String formatRestTimerCountdown(int seconds) {
  final total = seconds < 0 ? 0 : seconds;
  final minutes = (total ~/ 60).toString().padLeft(2, '0');
  final rest = (total % 60).toString().padLeft(2, '0');
  return '$minutes:$rest';
}
