import 'dart:math' as math;

enum NutritionMeal { breakfast, lunch, dinner, snacks }

enum NutritionTargetInputMode { grams, percent }

enum NutritionTargetCategory { custom, cut, maintenance, bulk }

class NutritionValidationException implements Exception {
  const NutritionValidationException(this.fields);
  final Map<String, String> fields;

  @override
  String toString() => 'NutritionValidationException($fields)';
}

class NutritionTotals {
  const NutritionTotals({
    required this.kilocalories,
    this.proteinGrams,
    this.carbohydrateGrams,
    this.fatGrams,
  });

  final double kilocalories;
  final double? proteinGrams;
  final double? carbohydrateGrams;
  final double? fatGrams;

  factory NutritionTotals.fromJson(Map<String, dynamic> json) =>
      NutritionTotals(
        kilocalories: _number(json, 'kilocalories'),
        proteinGrams: _nullableNumber(json, 'proteinGrams'),
        carbohydrateGrams: _nullableNumber(json, 'carbohydrateGrams'),
        fatGrams: _nullableNumber(json, 'fatGrams'),
      );

  Map<String, Object?> toJson() => {
    'kilocalories': kilocalories,
    'proteinGrams': proteinGrams,
    'carbohydrateGrams': carbohydrateGrams,
    'fatGrams': fatGrams,
  };

  NutritionTotals scaled(double factor) => NutritionTotals(
    kilocalories: roundNutrition(kilocalories * factor),
    proteinGrams: _scale(proteinGrams, factor),
    carbohydrateGrams: _scale(carbohydrateGrams, factor),
    fatGrams: _scale(fatGrams, factor),
  );

  static NutritionTotals get zero => const NutritionTotals(kilocalories: 0);
}

class NutritionSource {
  const NutritionSource({
    this.provider,
    this.barcode,
    this.retrievedAtUtc,
    required this.basisGrams,
  });

  final String? provider;
  final String? barcode;
  final DateTime? retrievedAtUtc;
  final double basisGrams;

  factory NutritionSource.fromJson(Map<String, dynamic> json) =>
      NutritionSource(
        provider: json['provider'] as String?,
        barcode: json['barcode'] as String?,
        retrievedAtUtc: json['retrievedAtUtc'] == null
            ? null
            : DateTime.parse(json['retrievedAtUtc'] as String).toUtc(),
        basisGrams: _number(json, 'basisGrams'),
      );

  Map<String, Object?> toJson() => {
    'provider': provider,
    'barcode': barcode,
    'retrievedAtUtc': retrievedAtUtc?.toUtc().toIso8601String(),
    'basisGrams': basisGrams,
  };
}

class NutritionEntry {
  NutritionEntry({
    required this.entryId,
    required this.meal,
    required this.position,
    required String productName,
    required String? brand,
    required this.amountGrams,
    required this.per100Grams,
    required this.source,
  }) : productName = productName.trim(),
       brand = brand?.trim().isEmpty == true ? null : brand?.trim() {
    validateNutritionEntry(this);
  }

  final String entryId;
  final NutritionMeal meal;
  final int position;
  final String productName;
  final String? brand;
  final double amountGrams;
  final NutritionTotals per100Grams;
  final NutritionSource? source;

  NutritionTotals get totals => per100Grams.scaled(amountGrams / 100);

  factory NutritionEntry.fromJson(Map<String, dynamic> json) => NutritionEntry(
    entryId: _requiredString(json, 'entryId'),
    meal: nutritionMealFromWire(_requiredString(json, 'meal')),
    position: json['position'] as int,
    productName: _requiredString(json, 'productName'),
    brand: json['brand'] as String?,
    amountGrams: _number(json, 'amountGrams'),
    per100Grams: NutritionTotals.fromJson(
      _object(json['per100Grams'], 'per100Grams'),
    ),
    source: json['source'] == null
        ? null
        : NutritionSource.fromJson(_object(json['source'], 'source')),
  );

  Map<String, Object?> toJson() => {
    'entryId': entryId,
    'meal': nutritionMealToWire(meal),
    'position': position,
    'productName': productName,
    'brand': brand,
    'amountGrams': amountGrams,
    'totals': totals.toJson(),
    'per100Grams': per100Grams.toJson(),
    'source': source?.toJson(),
  };

  NutritionEntry copyWith({
    NutritionMeal? meal,
    int? position,
    String? productName,
    String? brand,
    bool clearBrand = false,
    double? amountGrams,
    NutritionTotals? per100Grams,
    NutritionSource? source,
    bool clearSource = false,
  }) => NutritionEntry(
    entryId: entryId,
    meal: meal ?? this.meal,
    position: position ?? this.position,
    productName: productName ?? this.productName,
    brand: clearBrand ? null : brand ?? this.brand,
    amountGrams: amountGrams ?? this.amountGrams,
    per100Grams: per100Grams ?? this.per100Grams,
    source: clearSource ? null : source ?? this.source,
  );
}

class NutritionDay {
  NutritionDay({required this.localDate, required List<NutritionEntry> entries})
    : entries = List.unmodifiable(_orderedEntries(entries)) {
    if (!isValidLocalDate(localDate)) {
      throw NutritionValidationException({
        'localDate': 'Ungültiger Kalendertag.',
      });
    }
    if (entries.length > 200) {
      throw NutritionValidationException({
        'entries': 'Maximal 200 Einträge pro Tag.',
      });
    }
    final ids = entries.map((item) => item.entryId).toSet();
    if (ids.length != entries.length) {
      throw NutritionValidationException({
        'entries': 'Eintrags-IDs müssen eindeutig sein.',
      });
    }
    for (final meal in NutritionMeal.values) {
      final positions = entries
          .where((item) => item.meal == meal)
          .map((item) => item.position)
          .toList();
      if (positions.toSet().length != positions.length ||
          positions.any((value) => value < 0)) {
        throw NutritionValidationException({
          'entries': 'Positionen innerhalb einer Mahlzeit müssen eindeutig und gültig sein.',
        });
      }
    }
  }

  final String localDate;
  final List<NutritionEntry> entries;

  NutritionTotals get totals {
    double? sum(double? Function(NutritionTotals) select) {
      final values = entries
          .map((item) => select(item.totals))
          .whereType<double>()
          .toList();
      return values.isEmpty
          ? null
          : roundNutrition(values.fold<double>(0, (a, b) => a + b));
    }

    return NutritionTotals(
      kilocalories: roundNutrition(
        entries.fold<double>(0, (a, item) => a + item.totals.kilocalories),
      ),
      proteinGrams: sum((v) => v.proteinGrams),
      carbohydrateGrams: sum((v) => v.carbohydrateGrams),
      fatGrams: sum((v) => v.fatGrams),
    );
  }

  factory NutritionDay.fromJson(Map<String, dynamic> json) => NutritionDay(
    localDate: _requiredString(json, 'localDate'),
    entries: _objectList(
      json['entries'],
      'entries',
    ).map(NutritionEntry.fromJson).toList(),
  );

  Map<String, Object?> toJson() => {
    'localDate': localDate,
    'entries': [for (final entry in entries) entry.toJson()],
  };

  NutritionDay replace(NutritionEntry entry) {
    final index = entries.indexWhere((item) => item.entryId == entry.entryId);
    final next = [...entries];
    if (index == -1) {
      next.add(entry.copyWith(position: _nextPosition(entry.meal)));
    } else {
      next[index] = entry;
    }
    return NutritionDay(localDate: localDate, entries: next);
  }

  NutritionDay remove(String entryId) => NutritionDay(
    localDate: localDate,
    entries: _reindex(
      entries.where((item) => item.entryId != entryId).toList(),
    ),
  );

  NutritionDay move(String entryId, NutritionMeal meal, int targetPosition) {
    final matches = entries.where((item) => item.entryId == entryId);
    final moving = matches.isEmpty ? null : matches.first;
    if (moving == null) {
      throw StateError('Der Ernährungseintrag ist nicht verfügbar.');
    }
    final items = entries.where((item) => item.entryId != entryId).toList();
    final destination = items.where((item) => item.meal == meal).toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    if (targetPosition < 0 || targetPosition > destination.length) {
      throw RangeError.range(
        targetPosition,
        0,
        destination.length,
        'targetPosition',
      );
    }
    destination.insert(
      targetPosition,
      moving.copyWith(meal: meal, position: targetPosition),
    );
    final other = items.where((item) => item.meal != meal);
    return NutritionDay(
      localDate: localDate,
      entries: [...other, ..._reindex(destination)],
    );
  }

  int _nextPosition(NutritionMeal meal) => entries
      .where((item) => item.meal == meal)
      .fold<int>(0, (max, item) => math.max(max, item.position + 1));
}

class ReusableMealComponent {
  ReusableMealComponent({
    required this.componentId,
    required this.position,
    required String name,
    required String? brand,
    required this.amountGrams,
    required this.per100Grams,
    required this.source,
  }) : name = name.trim(),
       brand = brand?.trim().isEmpty == true ? null : brand?.trim() {
    if (componentId.isEmpty ||
        position < 0 ||
        this.name.isEmpty ||
        this.name.length > 160 ||
        !amountGrams.isFinite ||
        amountGrams <= 0) {
      throw NutritionValidationException({
        'components': 'Gerichtseintrag ist ungültig.',
      });
    }
    _validateTotals(per100Grams, requirePositiveCalories: true);
  }

  final String componentId;
  final int position;
  final String name;
  final String? brand;
  final double amountGrams;
  final NutritionTotals per100Grams;
  final NutritionSource? source;
  NutritionTotals get totals => per100Grams.scaled(amountGrams / 100);

  factory ReusableMealComponent.fromJson(Map<String, dynamic> json) =>
      ReusableMealComponent(
        componentId: _requiredString(json, 'componentId'),
        position: json['position'] as int,
        name: _requiredString(json, 'name'),
        brand: json['brand'] as String?,
        amountGrams: _number(json, 'amountGrams'),
        per100Grams: NutritionTotals.fromJson(
          _object(json['per100Grams'], 'per100Grams'),
        ),
        source: json['source'] == null
            ? null
            : NutritionSource.fromJson(_object(json['source'], 'source')),
      );

  Map<String, Object?> toJson() => {
    'componentId': componentId,
    'position': position,
    'name': name,
    'brand': brand,
    'amountGrams': amountGrams,
    'totals': totals.toJson(),
    'per100Grams': per100Grams.toJson(),
    'source': source?.toJson(),
  };
}

class ReusableMeal {
  ReusableMeal({
    required String name,
    required String? description,
    required this.standardPortion,
    required List<ReusableMealComponent> components,
    this.status = 'Active',
    this.createdAtUtc,
    this.updatedAtUtc,
  }) : name = name.trim(),
       description = description?.trim().isEmpty == true
           ? null
           : description?.trim(),
       components = List.unmodifiable(
         [...components]..sort((a, b) => a.position.compareTo(b.position)),
       ) {
    if (this.name.isEmpty || this.name.length > 120) {
      throw NutritionValidationException({
        'name': 'Name erforderlich (maximal 120 Zeichen).',
      });
    }
    if (!standardPortion.isFinite ||
        standardPortion < .01 ||
        standardPortion > 100) {
      throw NutritionValidationException({
        'standardPortion': 'Portion muss zwischen 0,01 und 100 liegen.',
      });
    }
    if (this.components.isEmpty || this.components.length > 50) {
      throw NutritionValidationException({
        'components': 'Ein Gericht benötigt 1 bis 50 Bestandteile.',
      });
    }
    if (this.components.map((e) => e.componentId).toSet().length !=
            this.components.length ||
        this.components.map((e) => e.position).toSet().length !=
            this.components.length) {
      throw NutritionValidationException({
        'components': 'Bestandteil-IDs und Positionen müssen eindeutig sein.',
      });
    }
    if (status != 'Active' && status != 'Archived') {
      throw NutritionValidationException({
        'status': 'Ungültiger Gerichtstatus.',
      });
    }
  }

  final String name;
  final String? description;
  final double standardPortion;
  final List<ReusableMealComponent> components;
  final String status;
  final String? createdAtUtc;
  final String? updatedAtUtc;

  factory ReusableMeal.fromJson(Map<String, dynamic> json) => ReusableMeal(
    name: _requiredString(json, 'name'),
    description: json['description'] as String?,
    standardPortion: _number(json, 'standardPortion'),
    components: _objectList(
      json['components'],
      'components',
    ).map(ReusableMealComponent.fromJson).toList(),
    status: json['status'] as String? ?? 'Active',
    createdAtUtc: json['createdAtUtc'] as String?,
    updatedAtUtc: json['updatedAtUtc'] as String?,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'description': description,
    'standardPortion': standardPortion,
    'status': status,
    'components': [for (final item in components) item.toJson()],
    'createdAtUtc': createdAtUtc,
    'updatedAtUtc': updatedAtUtc,
  };

  ReusableMeal archived() => ReusableMeal(
    name: name,
    description: description,
    standardPortion: standardPortion,
    components: components,
    status: 'Archived',
    createdAtUtc: createdAtUtc,
    updatedAtUtc: updatedAtUtc,
  );
}

class NutritionTargetVersion {
  const NutritionTargetVersion({
    required this.targetVersionId,
    required this.name,
    required this.category,
    required this.effectiveFrom,
    required this.effectiveUntil,
    required this.inputMode,
    required this.kilocalories,
    required this.proteinGrams,
    required this.carbohydrateGrams,
    required this.fatGrams,
    required this.proteinPercent,
    required this.carbohydratePercent,
    required this.fatPercent,
    this.origin = 'Manual',
    this.algorithmVersion,
    this.reason,
  });

  final String targetVersionId, name, effectiveFrom;
  final String? effectiveUntil;
  final NutritionTargetCategory category;
  final NutritionTargetInputMode inputMode;
  final double kilocalories, proteinGrams, carbohydrateGrams, fatGrams;
  final double? proteinPercent, carbohydratePercent, fatPercent;
  final String origin;
  final String? algorithmVersion, reason;

  double get macroEnergyKilocalories =>
      proteinGrams * 4 + carbohydrateGrams * 4 + fatGrams * 9;

  Map<String, Object?> toJson() => {
    'targetVersionId': targetVersionId,
    'name': name,
    'category': _title(category.name),
    'effectiveFrom': effectiveFrom,
    'effectiveUntil': effectiveUntil,
    'inputMode': _title(inputMode.name),
    'kilocalories': kilocalories,
    'proteinGrams': proteinGrams,
    'carbohydrateGrams': carbohydrateGrams,
    'fatGrams': fatGrams,
    'proteinPercent': proteinPercent,
    'carbohydratePercent': carbohydratePercent,
    'fatPercent': fatPercent,
    'origin': origin,
    'algorithmVersion': algorithmVersion,
    'reason': reason,
  };
}

class NutritionTargetSchedule {
  NutritionTargetSchedule({required List<NutritionTargetVersion> versions})
    : versions = List.unmodifiable(
        [...versions]
          ..sort((a, b) => a.effectiveFrom.compareTo(b.effectiveFrom)),
      ) {
    validateTargetSchedule(this.versions);
  }
  final List<NutritionTargetVersion> versions;
  Map<String, Object?> toJson() => {
    'versions': [for (final item in versions) item.toJson()],
  };
}

NutritionTotals calculatePer100Totals({
  required double amountGrams,
  required NutritionTotals totals,
}) {
  if (!amountGrams.isFinite || amountGrams <= 0) {
    throw NutritionValidationException({
      'amountGrams': 'Menge muss positiv sein.',
    });
  }
  return NutritionTotals(
    kilocalories: roundNutrition(totals.kilocalories * 100 / amountGrams),
    proteinGrams: _scale(totals.proteinGrams, 100 / amountGrams),
    carbohydrateGrams: _scale(totals.carbohydrateGrams, 100 / amountGrams),
    fatGrams: _scale(totals.fatGrams, 100 / amountGrams),
  );
}

double? _scale(double? value, double factor) =>
    value == null ? null : roundNutrition(value * factor);
double roundNutrition(double value) =>
    ((value * 100) + 1e-9).roundToDouble() / 100;

NutritionTotals macroGramsFromPercent({
  required double kilocalories,
  required double proteinPercent,
  required double carbohydratePercent,
  required double fatPercent,
}) {
  final values = [
    kilocalories,
    proteinPercent,
    carbohydratePercent,
    fatPercent,
  ];
  if (!values.every((value) => value.isFinite) ||
      kilocalories <= 0 ||
      [
        proteinPercent,
        carbohydratePercent,
        fatPercent,
      ].any((value) => value < 0) ||
      (proteinPercent + carbohydratePercent + fatPercent - 100).abs() > .01) {
    throw NutritionValidationException({
      'percentages': 'Kalorien und Makroanteile müssen gültig sein und zusammen 100 % ergeben.',
    });
  }
  return NutritionTotals(
    kilocalories: roundNutrition(kilocalories),
    proteinGrams: roundNutrition(kilocalories * proteinPercent / 100 / 4),
    carbohydrateGrams: roundNutrition(
      kilocalories * carbohydratePercent / 100 / 4,
    ),
    fatGrams: roundNutrition(kilocalories * fatPercent / 100 / 9),
  );
}

void validateNutritionEntry(NutritionEntry entry) {
  if (entry.entryId.isEmpty ||
      entry.position < 0 ||
      entry.productName.isEmpty ||
      entry.productName.length > 160) {
    throw NutritionValidationException({'entry': 'Eintrag ist ungültig.'});
  }
  if (!entry.amountGrams.isFinite ||
      entry.amountGrams <= 0 ||
      entry.amountGrams > 100000) {
    throw NutritionValidationException({
      'amountGrams': 'Menge muss positiv und plausibel sein.',
    });
  }
  if (entry.brand != null && entry.brand!.length > 120) {
    throw NutritionValidationException({'brand': 'Marke ist zu lang.'});
  }
  _validateTotals(entry.per100Grams, requirePositiveCalories: true);
  if (entry.source case final source?) {
    if (!source.basisGrams.isFinite || source.basisGrams <= 0) {
      throw NutritionValidationException({
        'source': 'Quellenbasis muss positiv sein.',
      });
    }
  }
}

void _validateTotals(
  NutritionTotals totals, {
  required bool requirePositiveCalories,
}) {
  if (!totals.kilocalories.isFinite ||
      (requirePositiveCalories
          ? totals.kilocalories <= 0
          : totals.kilocalories < 0)) {
    throw NutritionValidationException({
      'kilocalories': 'Kalorien müssen positiv sein.',
    });
  }
  for (final (key, value) in [
    ('proteinGrams', totals.proteinGrams),
    ('carbohydrateGrams', totals.carbohydrateGrams),
    ('fatGrams', totals.fatGrams),
  ]) {
    if (value != null && (!value.isFinite || value < 0)) {
      throw NutritionValidationException({
        key: 'Nährwerte dürfen nicht negativ sein.',
      });
    }
  }
}

void validateTargetSchedule(List<NutritionTargetVersion> versions) {
  final errors = <String, String>{};
  if (versions.map((e) => e.targetVersionId).toSet().length !=
      versions.length) {
    errors['versions'] = 'Zielversionen müssen eindeutige IDs besitzen.';
  }
  for (var index = 0; index < versions.length; index++) {
    final target = versions[index];
    if (target.name.trim().isEmpty ||
        !isValidLocalDate(target.effectiveFrom) ||
        (target.effectiveUntil != null &&
            !isValidLocalDate(target.effectiveUntil!))) {
      errors['versions.$index'] = 'Name oder Datum ungültig.';
    }
    if (target.effectiveUntil != null &&
        target.effectiveUntil!.compareTo(target.effectiveFrom) < 0) {
      errors['versions.$index.effectiveUntil'] = 'Enddatum liegt vor Beginn.';
    }
    if (![
          target.kilocalories,
          target.proteinGrams,
          target.carbohydrateGrams,
          target.fatGrams,
        ].every((v) => v.isFinite && v >= 0) ||
        target.kilocalories <= 0) {
      errors['versions.$index.nutrients'] =
          'Zielwerte müssen gültig und Kalorien positiv sein.';
    }
    if (target.inputMode == NutritionTargetInputMode.percent) {
      final p = target.proteinPercent,
          c = target.carbohydratePercent,
          f = target.fatPercent;
      if (p == null ||
          c == null ||
          f == null ||
          ![p, c, f].every((v) => v.isFinite && v >= 0) ||
          (p + c + f - 100).abs() > 0.01) {
        errors['versions.$index.percentages'] =
            'Makroanteile müssen zusammen 100 % ergeben.';
      }
    }
    if (index > 0) {
      final previous = versions[index - 1];
      if (previous.effectiveUntil == null ||
          previous.effectiveUntil!.compareTo(target.effectiveFrom) >= 0) {
        errors['versions.$index.effectiveFrom'] = 'Zielphasen dürfen sich nicht überschneiden; die vorherige Phase braucht ein Enddatum.';
      }
    }
  }
  if (errors.isNotEmpty) throw NutritionValidationException(errors);
}

NutritionMeal nutritionMealFromWire(String value) =>
    NutritionMeal.values.firstWhere(
      (item) => _title(item.name) == value,
      orElse: () => throw FormatException('Unbekannte Mahlzeit: $value'),
    );
String nutritionMealToWire(NutritionMeal value) => _title(value.name);
String _title(String value) => value[0].toUpperCase() + value.substring(1);
bool isValidLocalDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
  final parsed = DateTime.tryParse(value);
  return parsed != null &&
      '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}' ==
          value;
}

List<NutritionEntry> _orderedEntries(List<NutritionEntry> entries) =>
    [...entries]..sort((a, b) {
      final meal = a.meal.index.compareTo(b.meal.index);
      return meal == 0 ? a.position.compareTo(b.position) : meal;
    });
List<NutritionEntry> _reindex(List<NutritionEntry> entries) {
  final counters = <NutritionMeal, int>{};
  return entries.map((item) {
    final position = counters[item.meal] ?? 0;
    counters[item.meal] = position + 1;
    return item.copyWith(position: position);
  }).toList();
}

Map<String, dynamic> _object(Object? value, String name) =>
    value is Map<String, dynamic>
    ? value
    : throw FormatException('Invalid $name.');
List<Map<String, dynamic>> _objectList(Object? value, String name) =>
    value is List && value.every((e) => e is Map<String, dynamic>)
    ? value.cast<Map<String, dynamic>>()
    : throw FormatException('Invalid $name.');
String _requiredString(Map<String, dynamic> json, String key) =>
    json[key] is String && (json[key] as String).isNotEmpty
    ? json[key] as String
    : throw FormatException('Invalid $key.');
double _number(Map<String, dynamic> json, String key) =>
    json[key] is num && (json[key] as num).toDouble().isFinite
    ? (json[key] as num).toDouble()
    : throw FormatException('Invalid $key.');
double? _nullableNumber(Map<String, dynamic> json, String key) =>
    json[key] == null ? null : _number(json, key);
