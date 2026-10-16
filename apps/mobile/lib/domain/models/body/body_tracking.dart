enum BodyGoalKind { bulk, maintain, cut }

enum BodyWeightUnit { kilograms, pounds }

const _invalidCalendarDayMessage = 'Ungültiger Kalendertag.';

class BodyTrackingValidationException implements Exception {
  const BodyTrackingValidationException(this.fields);

  final Map<String, String> fields;

  @override
  String toString() => 'BodyTrackingValidationException($fields)';
}

class BodyGoal {
  const BodyGoal({
    required this.kind,
    required this.startWeightKg,
    required this.targetWeightKg,
    required this.startDate,
    required this.targetDate,
    required this.createdAtUtc,
    required this.endedAtUtc,
  });

  final BodyGoalKind kind;
  final double startWeightKg;
  final double targetWeightKg;
  final String startDate;
  final String? targetDate;
  final String createdAtUtc;
  final String? endedAtUtc;

  bool get isActive => endedAtUtc == null;

  factory BodyGoal.fromJson(Map<String, dynamic> json) => BodyGoal(
    kind: BodyGoalKind.values.firstWhere(
      (value) => value.name == (json['kind'] as String).toLowerCase(),
      orElse: () => throw const FormatException('Unknown body goal kind.'),
    ),
    startWeightKg: _number(json, 'startWeightKg'),
    targetWeightKg: _number(json, 'targetWeightKg'),
    startDate: _requiredString(json, 'startDate'),
    targetDate: json['targetDate'] as String?,
    createdAtUtc: _requiredString(json, 'createdAtUtc'),
    endedAtUtc: json['endedAtUtc'] as String?,
  );

  Map<String, Object?> toJson() => {
    'kind': switch (kind) {
      BodyGoalKind.bulk => 'Bulk',
      BodyGoalKind.maintain => 'Maintain',
      BodyGoalKind.cut => 'Cut',
    },
    'startWeightKg': startWeightKg,
    'targetWeightKg': targetWeightKg,
    'startDate': startDate,
    'targetDate': targetDate,
    'createdAtUtc': createdAtUtc,
    'endedAtUtc': endedAtUtc,
  };
}

class DailyCheckIn {
  const DailyCheckIn({
    required this.localDate,
    required this.weightKg,
    required this.caloriesKcal,
    required this.proteinGrams,
    required this.carbohydrateGrams,
    required this.fatGrams,
    required this.steps,
    required this.sleepMinutes,
    required this.createdAtUtc,
    required this.updatedAtUtc,
  });

  final String localDate;
  final double weightKg;
  final double? caloriesKcal;
  final double? proteinGrams;
  final double? carbohydrateGrams;
  final double? fatGrams;
  final int? steps;
  final int? sleepMinutes;
  final String createdAtUtc;
  final String updatedAtUtc;

  factory DailyCheckIn.fromJson(Map<String, dynamic> json) => DailyCheckIn(
    localDate: _requiredString(json, 'localDate'),
    weightKg: _number(json, 'weightKg'),
    caloriesKcal: _nullableNumber(json, 'caloriesKcal'),
    proteinGrams: _nullableNumber(json, 'proteinGrams'),
    carbohydrateGrams: _nullableNumber(json, 'carbohydrateGrams'),
    fatGrams: _nullableNumber(json, 'fatGrams'),
    steps: json['steps'] as int?,
    sleepMinutes: json['sleepMinutes'] as int?,
    createdAtUtc: _requiredString(json, 'createdAtUtc'),
    updatedAtUtc: _requiredString(json, 'updatedAtUtc'),
  );

  Map<String, Object?> toJson() => {
    'localDate': localDate,
    'weightKg': weightKg,
    'caloriesKcal': caloriesKcal,
    'proteinGrams': proteinGrams,
    'carbohydrateGrams': carbohydrateGrams,
    'fatGrams': fatGrams,
    'steps': steps,
    'sleepMinutes': sleepMinutes,
    'createdAtUtc': createdAtUtc,
    'updatedAtUtc': updatedAtUtc,
  };
}

String? validateBodyGoal({
  required BodyGoalKind kind,
  required double startWeightKg,
  required double targetWeightKg,
  required String startDate,
  required String? targetDate,
}) {
  final errors = <String, String>{};
  if (!startWeightKg.isFinite || startWeightKg <= 0) {
    errors['startWeightKg'] = 'Das Startgewicht muss positiv sein.';
  }
  if (!targetWeightKg.isFinite || targetWeightKg <= 0) {
    errors['targetWeightKg'] = 'Das Zielgewicht muss positiv sein.';
  }
  if (!_validDate(startDate)) errors['startDate'] = _invalidCalendarDayMessage;
  if (targetDate != null && !_validDate(targetDate)) {
    errors['targetDate'] = _invalidCalendarDayMessage;
  } else if (targetDate != null && targetDate.compareTo(startDate) < 0) {
    errors['targetDate'] = 'Das Zieldatum darf nicht vor dem Start liegen.';
  }
  if (errors.isNotEmpty) {
    throw BodyTrackingValidationException(errors);
  }
  return null;
}

void validateDailyCheckIn({
  required String localDate,
  required double weightKg,
  required double? caloriesKcal,
  required double? proteinGrams,
  required double? carbohydrateGrams,
  required double? fatGrams,
  required int? steps,
  required int? sleepMinutes,
}) {
  final errors = <String, String>{};
  if (!_validDate(localDate)) errors['localDate'] = _invalidCalendarDayMessage;
  if (!weightKg.isFinite || weightKg <= 0) {
    errors['weightKg'] = 'Das Gewicht muss positiv sein.';
  }
  for (final (name, value) in [
    ('caloriesKcal', caloriesKcal),
    ('proteinGrams', proteinGrams),
    ('carbohydrateGrams', carbohydrateGrams),
    ('fatGrams', fatGrams),
  ]) {
    if (value != null && (!value.isFinite || value < 0)) {
      errors[name] = 'Der Wert darf nicht negativ sein.';
    }
  }
  if (steps != null && steps < 0) {
    errors['steps'] = 'Schritte dürfen nicht negativ sein.';
  }
  if (sleepMinutes != null && (sleepMinutes < 0 || sleepMinutes > 1440)) {
    errors['sleepMinutes'] = 'Schlaf muss zwischen 0 und 1440 Minuten liegen.';
  }
  if (errors.isNotEmpty) {
    throw BodyTrackingValidationException(errors);
  }
}

double weightForDisplay(double kilograms, BodyWeightUnit unit) =>
    unit == BodyWeightUnit.kilograms ? kilograms : kilograms * 2.2046226218;

double weightToKilograms(double value, BodyWeightUnit unit) =>
    unit == BodyWeightUnit.kilograms ? value : value / 2.2046226218;

bool _validDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
  final parsed = DateTime.tryParse(value);
  return parsed != null &&
      '${parsed.year.toString().padLeft(4, '0')}-'
              '${parsed.month.toString().padLeft(2, '0')}-'
              '${parsed.day.toString().padLeft(2, '0')}' ==
          value;
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Invalid $key.');
  }
  return value;
}

double _number(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is num && value.toDouble().isFinite) return value.toDouble();
  throw FormatException('Invalid $key.');
}

double? _nullableNumber(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is num && value.toDouble().isFinite) return value.toDouble();
  throw FormatException('Invalid $key.');
}
