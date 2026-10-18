import 'workout_input.dart';
import 'workout_model.dart';

const int maxWarmupSteps = 5;
const int minWarmupPercent = 1;
const int maxWarmupPercent = 100;
const int minWarmupRepetitions = 1;
const int maxWarmupRepetitions = 50;

/// Erlaubte Rundungen je Anzeigeeinheit; die erste ist der Standard.
const List<double> warmupRoundingKg = [2.5, 0.5, 1, 1.25, 5];
const List<double> warmupRoundingLbs = [5, 1, 2.5, 10];

List<double> warmupRoundingOptions(WeightUnit unit) =>
    unit == WeightUnit.kg ? warmupRoundingKg : warmupRoundingLbs;

double defaultWarmupRounding(WeightUnit unit) =>
    warmupRoundingOptions(unit).first;

/// Eine Aufwärmstufe: Anteil am Arbeitsgewicht, optional mit Wiederholungen.
final class WarmupStep {
  const WarmupStep({required this.percent, this.repetitions})
    : assert(percent >= minWarmupPercent && percent <= maxWarmupPercent),
      assert(
        repetitions == null ||
            (repetitions >= minWarmupRepetitions &&
                repetitions <= maxWarmupRepetitions),
      );

  final int percent;
  final int? repetitions;

  /// Liest eine gespeicherte Stufe; Werte außerhalb der Grenzen ergeben `null`.
  static WarmupStep? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final percent = json['percent'];
    final repetitions = json['repetitions'];
    if (percent is! int ||
        percent < minWarmupPercent ||
        percent > maxWarmupPercent) {
      return null;
    }
    if (repetitions != null &&
        (repetitions is! int ||
            repetitions < minWarmupRepetitions ||
            repetitions > maxWarmupRepetitions)) {
      return null;
    }
    return WarmupStep(percent: percent, repetitions: repetitions as int?);
  }

  Map<String, Object?> toJson() => {
    'percent': percent,
    'repetitions': repetitions,
  };

  @override
  bool operator ==(Object other) =>
      other is WarmupStep &&
      other.percent == percent &&
      other.repetitions == repetitions;

  @override
  int get hashCode => Object.hash(percent, repetitions);
}

const List<WarmupStep> defaultWarmupSteps = [
  WarmupStep(percent: 50),
  WarmupStep(percent: 80),
];

List<WarmupStep> _decodeSteps(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw.take(maxWarmupSteps)) ?WarmupStep.tryFromJson(item),
  ];
}

bool _stepsEqual(List<WarmupStep> a, List<WarmupStep> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Globale Aufwärmeinstellungen des Kontos.
final class WarmupSettings {
  const WarmupSettings({
    this.enabled = true,
    this.showRepetitions = false,
    this.steps = defaultWarmupSteps,
  });

  /// Fehlende oder ungültige Felder fallen auf den Standard zurück; eine
  /// gespeicherte leere Stufenliste bleibt leer.
  factory WarmupSettings.fromJson(Object? json) {
    if (json is! Map) return const WarmupSettings();
    return WarmupSettings(
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      showRepetitions: json['showRepetitions'] == true,
      steps: json['steps'] is List
          ? _decodeSteps(json['steps'])
          : defaultWarmupSteps,
    );
  }

  final bool enabled;
  final bool showRepetitions;
  final List<WarmupStep> steps;

  WarmupSettings copyWith({
    bool? enabled,
    bool? showRepetitions,
    List<WarmupStep>? steps,
  }) => WarmupSettings(
    enabled: enabled ?? this.enabled,
    showRepetitions: showRepetitions ?? this.showRepetitions,
    steps: steps ?? this.steps,
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'showRepetitions': showRepetitions,
    'steps': [for (final step in steps) step.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is WarmupSettings &&
      other.enabled == enabled &&
      other.showRepetitions == showRepetitions &&
      _stepsEqual(other.steps, steps);

  @override
  int get hashCode =>
      Object.hash(enabled, showRepetitions, Object.hashAll(steps));
}

/// Abweichungen einer Übung von den globalen Einstellungen. Fehlende Felder
/// erben den globalen Wert. [rounding] steht in der Anzeigeeinheit.
final class ExerciseWarmupOverride {
  const ExerciseWarmupOverride({
    required this.exerciseId,
    this.enabled,
    this.steps,
    this.rounding,
  });

  final String exerciseId;
  final bool? enabled;
  final List<WarmupStep>? steps;
  final double? rounding;

  /// Ohne eigene Werte erbt die Übung alles und braucht keinen Eintrag.
  bool get isEmpty => enabled == null && steps == null && rounding == null;

  ExerciseWarmupOverride copyWith({
    bool? Function()? enabled,
    List<WarmupStep>? Function()? steps,
    double? Function()? rounding,
  }) => ExerciseWarmupOverride(
    exerciseId: exerciseId,
    enabled: enabled != null ? enabled() : this.enabled,
    steps: steps != null ? steps() : this.steps,
    rounding: rounding != null ? rounding() : this.rounding,
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'steps': steps == null ? null : [for (final s in steps!) s.toJson()],
    'rounding': rounding,
  };

  static ExerciseWarmupOverride? tryFromJson(String exerciseId, Object? json) {
    if (json is! Map) return null;
    final override = ExerciseWarmupOverride(
      exerciseId: exerciseId,
      enabled: json['enabled'] is bool ? json['enabled'] as bool : null,
      steps: json['steps'] is List ? _decodeSteps(json['steps']) : null,
      rounding: json['rounding'] is num
          ? (json['rounding'] as num).toDouble()
          : null,
    );
    return override.isEmpty ? null : override;
  }

  @override
  bool operator ==(Object other) =>
      other is ExerciseWarmupOverride &&
      other.exerciseId == exerciseId &&
      other.enabled == enabled &&
      other.rounding == rounding &&
      (other.steps == null
          ? steps == null
          : steps != null && _stepsEqual(other.steps!, steps!));

  @override
  int get hashCode => Object.hash(
    exerciseId,
    enabled,
    rounding,
    steps == null ? null : Object.hashAll(steps!),
  );
}

/// Wirksame Werte einer Übung nach Vererbung.
final class ResolvedWarmup {
  const ResolvedWarmup({
    required this.enabled,
    required this.steps,
    required this.rounding,
    required this.showRepetitions,
  });

  final bool enabled;
  final List<WarmupStep> steps;
  final double rounding;
  final bool showRepetitions;
}

/// Wendet die Übungswerte auf die globalen an. Eine Rundung, die in [unit]
/// nicht erlaubt ist, fällt auf den Standard der Einheit zurück.
ResolvedWarmup resolveWarmup(
  WarmupSettings global,
  ExerciseWarmupOverride? override,
  WeightUnit unit,
) {
  final rounding = override?.rounding;
  return ResolvedWarmup(
    enabled: global.enabled && (override?.enabled ?? true),
    steps: override?.steps ?? global.steps,
    rounding: rounding != null && warmupRoundingOptions(unit).contains(rounding)
        ? rounding
        : defaultWarmupRounding(unit),
    showRepetitions: global.showRepetitions,
  );
}

/// Gerundetes Aufwärmgewicht einer Stufe in kg.
final class WarmupTarget {
  const WarmupTarget({required this.weightKg, this.repetitions});

  final double weightKg;
  final int? repetitions;

  @override
  bool operator ==(Object other) =>
      other is WarmupTarget &&
      other.weightKg == weightKg &&
      other.repetitions == repetitions;

  @override
  int get hashCode => Object.hash(weightKg, repetitions);
}

/// Gewichte der Aufwärmstufen, aufsteigend. Je Stufe: Basis mal Prozent, auf das
/// nächste Vielfache von [rounding] (in der Anzeigeeinheit) gerundet. Stufen mit
/// Ergebnis ≤ 0 oder ≥ Basis entfallen; gleiche Gewichte werden zusammengefasst
/// (die erste Stufe behält ihre Wiederholungen).
List<WarmupTarget> warmupTargets({
  required double baseKg,
  required List<WarmupStep> steps,
  required double rounding,
  required WeightUnit unit,
}) {
  if (baseKg <= 0 || rounding <= 0) return const [];
  final base = unit.fromKg(baseKg);
  final sorted = [...steps]..sort((a, b) => a.percent.compareTo(b.percent));
  final targets = <WarmupTarget>[];
  final seen = <double>{};
  for (final step in sorted) {
    final raw = base * step.percent / 100;
    final rounded = _clean((raw / rounding).roundToDouble() * rounding);
    if (rounded <= 0 || rounded >= base || !seen.add(rounded)) continue;
    targets.add(
      WarmupTarget(weightKg: unit.toKg(rounded), repetitions: step.repetitions),
    );
  }
  return targets;
}

/// Entfernt Gleitkomma-Reste wie 62.50000000000001.
double _clean(double value) => double.parse(value.toStringAsFixed(4));

/// Basisgewicht des Hinweises: erster Arbeitssatz (Typ normal) mit Gewicht in
/// den Vorwerten. `null`, wenn keiner existiert.
double? warmupBaseKg(List<LoggedSet?> previous) {
  for (final set in previous) {
    if (set != null &&
        set.setType == SetType.normal &&
        (set.weightKg ?? 0) > 0) {
      return set.weightKg;
    }
  }
  return null;
}

/// Hinweistext, z. B. „Aufwärmen 40 kg · 65 kg“ oder mit Wiederholungen
/// „Aufwärmen 40 kg × 8 · 65 kg × 3“.
String formatWarmupHint(
  List<WarmupTarget> targets,
  WeightUnit unit, {
  required bool showRepetitions,
}) {
  final parts = [
    for (final target in targets)
      [
        '${formatWeight(target.weightKg, unit)} ${unit.label}',
        if (showRepetitions && target.repetitions != null)
          '× ${target.repetitions}',
      ].join(' '),
  ];
  return 'Aufwärmen ${parts.join(' · ')}';
}
