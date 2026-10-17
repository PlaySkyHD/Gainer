const double poundsPerKilogram = 2.20462;
const double maxWeightKg = 10000;
const int maxRepetitions = 10000;
const int maxRir = 10;

enum WeightUnit {
  kg,
  lbs;

  String get label => this == WeightUnit.kg ? 'kg' : 'lbs';

  /// Rechnet einen Anzeigewert in kg um; Gewichte werden kanonisch in kg gespeichert.
  double toKg(double value) =>
      this == WeightUnit.kg ? value : value / poundsPerKilogram;

  double fromKg(double kg) =>
      this == WeightUnit.kg ? kg : kg * poundsPerKilogram;
}

final RegExp _decimalPattern = RegExp(r'^\d+(\.\d+)?$');
final RegExp _integerPattern = RegExp(r'^\d+$');

/// Anzeige mit Komma als Dezimaltrennzeichen, ohne unnötige Nachkommastellen.
String formatWeight(double kg, WeightUnit unit) {
  var text = unit.fromKg(kg).toStringAsFixed(2);
  if (text.contains('.')) {
    text = text
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
  return text.replaceFirst('.', ',');
}

/// Liefert das Gewicht in kg oder `null` für ein leeres Feld. Ungültige,
/// negative oder zu große Eingaben werfen eine [FormatException].
double? parseWeightInput(String input, WeightUnit unit) {
  final text = _normalizedNumber(input);
  if (text == null) return null;
  if (!_decimalPattern.hasMatch(text)) {
    throw FormatException('Ungültiges Gewicht: $input');
  }
  final kg = unit.toKg(double.parse(text));
  if (kg > maxWeightKg) {
    throw FormatException('Gewicht zu groß: $input');
  }
  return kg;
}

/// Liefert die Wiederholungen oder `null` für ein leeres Feld.
int? parseRepetitionsInput(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;
  if (!_integerPattern.hasMatch(text)) {
    throw FormatException('Wiederholungen müssen ganzzahlig sein: $input');
  }
  final value = int.parse(text);
  if (value > maxRepetitions) {
    throw FormatException('Wiederholungen zu groß: $input');
  }
  return value;
}

/// Liefert den RIR-Wert oder `null` für ein leeres Feld.
int? parseRirInput(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;
  if (!_integerPattern.hasMatch(text)) {
    throw FormatException('RIR muss ganzzahlig sein: $input');
  }
  final value = int.parse(text);
  if (value > maxRir) {
    throw FormatException('RIR liegt über $maxRir: $input');
  }
  return value;
}

String? _normalizedNumber(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;
  final text = trimmed.replaceAll(',', '.');
  return text.startsWith('.') ? '0$text' : text;
}
