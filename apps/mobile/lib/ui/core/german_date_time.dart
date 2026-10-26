/// Lokale Zeit als „26.10.2026, 14:03“ (deutsch, ohne Sekunden und Zeitzone).
String formatGermanDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)}.${local.year}, '
      '${two(local.hour)}:${two(local.minute)}';
}
