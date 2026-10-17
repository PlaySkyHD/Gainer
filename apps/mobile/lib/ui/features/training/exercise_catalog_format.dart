import '../../../domain/models/training/workout_model.dart';
import '../../../domain/models/training/workout_validation.dart';

/// Suchnormalisierung: Groß-/Kleinschreibung und Umlaut-Schreibweise sind gleich.
String foldCatalogSearch(String value) => value
    .toLowerCase()
    .replaceAll('ä', 'ae')
    .replaceAll('ö', 'oe')
    .replaceAll('ü', 'ue')
    .replaceAll('ß', 'ss');

String catalogKindLabel(ExerciseKind kind) => switch (kind) {
  ExerciseKind.strength => 'Kraft',
  ExerciseKind.bodyweightLoaded => 'Körpergewicht mit Zusatzlast',
  ExerciseKind.bodyweightOnly => 'Reines Körpergewicht',
  ExerciseKind.assisted => 'Assistiert',
};

/// Anzeige eines Körpergewichtsfaktors (0–1) als Prozent, z. B. 0,64 → „64“.
String formatBodyweightPercent(double factor) {
  final percent = double.parse((factor * 100).toStringAsFixed(2));
  return _formatDecimal(percent);
}

/// Anzeige eines Zusatzgewichtsfaktors, z. B. 1,5 → „1,5“.
String formatWeightFactor(double factor) => _formatDecimal(factor);

String _formatDecimal(double value) {
  if (value == value.roundToDouble()) return value.round().toString();
  return value.toString().replaceAll('.', ',');
}

/// Nutzertext zu einem Fehler aus dem Repository. Unbekannte Fehler erhalten [fallback].
String catalogErrorMessage(Object error, String fallback) => switch (error) {
  StateError(:final message) => message,
  WorkoutValidationException(:final fields) when fields.isNotEmpty =>
    fields.values.first,
  _ => fallback,
};
