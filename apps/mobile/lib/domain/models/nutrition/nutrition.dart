import 'dart:math' as math;

enum NutritionMeal { breakfast, lunch, dinner, snacks }

enum NutritionTargetInputMode { grams, percent }

enum NutritionTargetCategory { custom, cut, maintenance, bulk }

/// Ob ein Tag für sein Ernährungsziel als Trainings- oder Ruhetag zählt.
enum NutritionDayKind { training, rest }

NutritionDayKind? nutritionDayKindFromWire(Object? value) => switch (value) {
  null => null,
  'Training' => NutritionDayKind.training,
  'Rest' => NutritionDayKind.rest,
  _ => throw FormatException('Unbekannte Tagesart: $value'),
};

String nutritionDayKindToWire(NutritionDayKind value) => switch (value) {
  NutritionDayKind.training => 'Training',
  NutritionDayKind.rest => 'Rest',
};

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
    this.saltGrams,
    this.fiberGrams,
  });

  final double kilocalories;
  final double? proteinGrams;
  final double? carbohydrateGrams;
  final double? fatGrams;

  /// Salz in Gramm; fehlt bei Einträgen ohne Salzangabe.
  final double? saltGrams;

  /// Ballaststoffe in Gramm; fehlt bei Einträgen ohne Angabe.
  final double? fiberGrams;

  factory NutritionTotals.fromJson(Map<String, dynamic> json) =>
      NutritionTotals(
        kilocalories: _number(json, 'kilocalories'),
        proteinGrams: _nullableNumber(json, 'proteinGrams'),
        carbohydrateGrams: _nullableNumber(json, 'carbohydrateGrams'),
        fatGrams: _nullableNumber(json, 'fatGrams'),
        saltGrams: _nullableNumber(json, 'saltGrams'),
        fiberGrams: _nullableNumber(json, 'fiberGrams'),
      );

  Map<String, Object?> toJson() => {
    'kilocalories': kilocalories,
    'proteinGrams': proteinGrams,
    'carbohydrateGrams': carbohydrateGrams,
    'fatGrams': fatGrams,
    if (saltGrams != null) 'saltGrams': saltGrams,
    if (fiberGrams != null) 'fiberGrams': fiberGrams,
  };

  NutritionTotals scaled(double factor) => NutritionTotals(
    kilocalories: roundNutrition(kilocalories * factor),
    proteinGrams: _scale(proteinGrams, factor),
    carbohydrateGrams: _scale(carbohydrateGrams, factor),
    fatGrams: _scale(fatGrams, factor),
    saltGrams: _scale(saltGrams, factor),
    fiberGrams: _scale(fiberGrams, factor),
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
    this.pieceGrams,
    this.pieceCount,
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

  /// Gewicht eines Stücks (Ei, Scheibe, Brötchen); bleibt gemerkt, auch wenn
  /// die Menge in Gramm eingegeben wurde.
  final double? pieceGrams;

  /// Stückzahl, wenn die Menge in Stück eingegeben wurde; dann gilt
  /// [amountGrams] = [pieceCount] × [pieceGrams].
  final double? pieceCount;

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
    pieceGrams: _portionValue(json, 'pieceGrams'),
    pieceCount: _portionValue(json, 'pieceCount'),
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
    if (pieceGrams != null) 'pieceGrams': pieceGrams,
    if (pieceCount != null) 'pieceCount': pieceCount,
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
    double? pieceGrams,
    double? pieceCount,
    bool clearPieces = false,
  }) => NutritionEntry(
    entryId: entryId,
    meal: meal ?? this.meal,
    position: position ?? this.position,
    productName: productName ?? this.productName,
    brand: clearBrand ? null : brand ?? this.brand,
    amountGrams: amountGrams ?? this.amountGrams,
    per100Grams: per100Grams ?? this.per100Grams,
    source: clearSource ? null : source ?? this.source,
    pieceGrams: clearPieces ? pieceGrams : pieceGrams ?? this.pieceGrams,
    pieceCount: clearPieces ? pieceCount : pieceCount ?? this.pieceCount,
  );
}

class NutritionDay {
  NutritionDay({
    required this.localDate,
    required List<NutritionEntry> entries,
    this.dayKind,
  }) : entries = List.unmodifiable(_orderedEntries(entries)) {
    if (!isValidLocalDate(localDate)) {
      throw const NutritionValidationException({
        'localDate': 'Ungültiger Kalendertag.',
      });
    }
    if (entries.length > 200) {
      throw const NutritionValidationException({
        'entries': 'Maximal 200 Einträge pro Tag.',
      });
    }
    final ids = entries.map((item) => item.entryId).toSet();
    if (ids.length != entries.length) {
      throw const NutritionValidationException({
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
        throw const NutritionValidationException({
          'entries': 'Positionen innerhalb einer Mahlzeit müssen eindeutig und gültig sein.',
        });
      }
    }
  }

  final String localDate;
  final List<NutritionEntry> entries;

  /// Vom Nutzer festgelegte Tagesart; null heißt automatisch.
  final NutritionDayKind? dayKind;

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
      saltGrams: sum((v) => v.saltGrams),
      fiberGrams: sum((v) => v.fiberGrams),
    );
  }

  factory NutritionDay.fromJson(Map<String, dynamic> json) => NutritionDay(
    localDate: _requiredString(json, 'localDate'),
    entries: _objectList(
      json['entries'],
      'entries',
    ).map(NutritionEntry.fromJson).toList(),
    dayKind: nutritionDayKindFromWire(json['dayKind']),
  );

  Map<String, Object?> toJson() => {
    'localDate': localDate,
    'entries': [for (final entry in entries) entry.toJson()],
    if (dayKind case final kind?) 'dayKind': nutritionDayKindToWire(kind),
  };

  NutritionDay withEntries(List<NutritionEntry> entries) =>
      NutritionDay(localDate: localDate, entries: entries, dayKind: dayKind);

  NutritionDay withDayKind(NutritionDayKind? dayKind) =>
      NutritionDay(localDate: localDate, entries: entries, dayKind: dayKind);

  NutritionDay replace(NutritionEntry entry) {
    final index = entries.indexWhere((item) => item.entryId == entry.entryId);
    final next = [...entries];
    if (index == -1) {
      next.add(entry.copyWith(position: _nextPosition(entry.meal)));
    } else {
      next[index] = entry;
    }
    return withEntries(next);
  }

  NutritionDay remove(String entryId) => withEntries(
    _reindex(entries.where((item) => item.entryId != entryId).toList()),
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
    return withEntries([...other, ..._reindex(destination)]);
  }

  int _nextPosition(NutritionMeal meal) => entries
      .where((item) => item.meal == meal)
      .fold<int>(0, (max, item) => math.max(max, item.position + 1));
}

/// Benannte Kopie der Einträge eines Ernährungstags, die sich auf andere Tage
/// anwenden lässt. Angewendete Einträge sind Kopien mit neuen IDs.
class NutritionDayTemplate {
  NutritionDayTemplate({
    required this.templateId,
    required String name,
    required this.dayKind,
    required List<NutritionEntry> entries,
    this.updatedAtUtc,
  }) : name = name.trim(),
       entries = List.unmodifiable(_orderedEntries(entries)) {
    if (templateId.isEmpty) {
      throw const NutritionValidationException({
        'templateId': 'Vorlage ohne ID.',
      });
    }
    if (this.name.isEmpty || this.name.length > maxNameLength) {
      throw const NutritionValidationException({
        'name': 'Der Name muss 1 bis 80 Zeichen haben.',
      });
    }
    if (entries.isEmpty || entries.length > maxEntriesPerDay) {
      throw const NutritionValidationException({
        'entries': 'Eine Vorlage braucht 1 bis 200 Einträge.',
      });
    }
    if (entries.map((item) => item.entryId).toSet().length != entries.length) {
      throw const NutritionValidationException({
        'entries': 'Eintrags-IDs müssen eindeutig sein.',
      });
    }
  }

  factory NutritionDayTemplate.fromJson(Map<String, dynamic> json) =>
      NutritionDayTemplate(
        templateId: _requiredString(json, 'templateId'),
        name: _requiredString(json, 'name'),
        dayKind: nutritionDayKindFromWire(json['dayKind']),
        entries: _objectList(
          json['entries'],
          'entries',
        ).map(NutritionEntry.fromJson).toList(),
        updatedAtUtc: DateTime.tryParse((json['updatedAtUtc'] as String?) ?? '')
            ?.toUtc(),
      );

  static const maxNameLength = 80;
  static const maxTemplates = 50;

  final String templateId;
  final String name;
  final NutritionDayKind? dayKind;
  final List<NutritionEntry> entries;
  final DateTime? updatedAtUtc;

  NutritionTotals get totals =>
      NutritionDay(localDate: '2000-01-01', entries: entries).totals;

  Map<String, Object?> toJson() => {
    'templateId': templateId,
    'name': name,
    'dayKind': dayKind == null ? null : nutritionDayKindToWire(dayKind!),
    'entries': [for (final entry in entries) entry.toJson()],
    if (updatedAtUtc case final stamp?)
      'updatedAtUtc': stamp.toUtc().toIso8601String(),
  };
}

/// Höchstzahl der Einträge eines Tages, auch nach dem Anwenden einer Vorlage.
const maxEntriesPerDay = 200;

class ReusableMealComponent {
  ReusableMealComponent({
    required this.componentId,
    required this.position,
    required String name,
    required String? brand,
    required this.amountGrams,
    required this.per100Grams,
    required this.source,
    this.pieceGrams,
    this.pieceCount,
  }) : name = name.trim(),
       brand = brand?.trim().isEmpty == true ? null : brand?.trim() {
    if (componentId.isEmpty ||
        position < 0 ||
        this.name.isEmpty ||
        this.name.length > 160 ||
        !amountGrams.isFinite ||
        amountGrams <= 0) {
      throw const NutritionValidationException({
        'components': 'Gerichtseintrag ist ungültig.',
      });
    }
    _validateTotals(per100Grams);
    validatePortion(amountGrams, pieceGrams, pieceCount);
  }

  final String componentId;
  final int position;
  final String name;
  final String? brand;
  final double amountGrams;
  final NutritionTotals per100Grams;
  final NutritionSource? source;
  final double? pieceGrams;
  final double? pieceCount;
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
        pieceGrams: _portionValue(json, 'pieceGrams'),
        pieceCount: _portionValue(json, 'pieceCount'),
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
    if (pieceGrams != null) 'pieceGrams': pieceGrams,
    if (pieceCount != null) 'pieceCount': pieceCount,
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
      throw const NutritionValidationException({
        'name': 'Name erforderlich (maximal 120 Zeichen).',
      });
    }
    if (!standardPortion.isFinite ||
        standardPortion < .01 ||
        standardPortion > 100) {
      throw const NutritionValidationException({
        'standardPortion': 'Portion muss zwischen 0,01 und 100 liegen.',
      });
    }
    if (this.components.isEmpty || this.components.length > 50) {
      throw const NutritionValidationException({
        'components': 'Ein Gericht benötigt 1 bis 50 Bestandteile.',
      });
    }
    if (this.components.map((e) => e.componentId).toSet().length !=
            this.components.length ||
        this.components.map((e) => e.position).toSet().length !=
            this.components.length) {
      throw const NutritionValidationException({
        'components': 'Bestandteil-IDs und Positionen müssen eindeutig sein.',
      });
    }
    if (status != 'Active' && status != 'Archived') {
      throw const NutritionValidationException({
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
    this.saltGrams,
    this.restDay,
    this.fiberGrams,
  });

  /// Standard-Salzgrenze, wenn eine Zielphase keine eigene hat (DGE-Richtwert).
  static const defaultSaltGrams = 6.0;

  /// Standard-Ballaststoffziel als Mindestwert, wenn eine Zielphase keines hat (DGE-Richtwert).
  static const defaultFiberGrams = 30.0;

  final String targetVersionId, name, effectiveFrom;
  final String? effectiveUntil;
  final NutritionTargetCategory category;
  final NutritionTargetInputMode inputMode;
  final double kilocalories, proteinGrams, carbohydrateGrams, fatGrams;
  final double? proteinPercent, carbohydratePercent, fatPercent;
  final String origin;
  final String? algorithmVersion, reason;

  /// Eigene Salzgrenze in Gramm; null bedeutet [defaultSaltGrams].
  final double? saltGrams;

  double get effectiveSaltGrams => saltGrams ?? defaultSaltGrams;

  /// Eigenes Ballaststoffziel (Mindestwert) in Gramm; null bedeutet [defaultFiberGrams].
  final double? fiberGrams;

  double get effectiveFiberGrams => fiberGrams ?? defaultFiberGrams;

  /// Eigenes Ziel für Ruhetage; ohne gilt das Ziel der Version an allen Tagen.
  final NutritionDayTarget? restDay;

  /// Das Ziel der Version selbst, das an Trainingstagen gilt.
  NutritionDayTarget get trainingDay => NutritionDayTarget(
    inputMode: inputMode,
    kilocalories: kilocalories,
    proteinGrams: proteinGrams,
    carbohydrateGrams: carbohydrateGrams,
    fatGrams: fatGrams,
    proteinPercent: proteinPercent,
    carbohydratePercent: carbohydratePercent,
    fatPercent: fatPercent,
  );

  NutritionTargetVersion copyWith({
    String? targetVersionId,
    String? name,
    NutritionTargetCategory? category,
    String? effectiveFrom,
    String? effectiveUntil,
    bool clearEffectiveUntil = false,
    NutritionDayTarget? trainingDay,
    double? saltGrams,
    bool clearSaltGrams = false,
    double? fiberGrams,
    bool clearFiberGrams = false,
    NutritionDayTarget? restDay,
    bool clearRestDay = false,
  }) {
    final training = trainingDay ?? this.trainingDay;
    return NutritionTargetVersion(
      targetVersionId: targetVersionId ?? this.targetVersionId,
      name: name ?? this.name,
      category: category ?? this.category,
      effectiveFrom: effectiveFrom ?? this.effectiveFrom,
      effectiveUntil: clearEffectiveUntil
          ? null
          : effectiveUntil ?? this.effectiveUntil,
      inputMode: training.inputMode,
      kilocalories: training.kilocalories,
      proteinGrams: training.proteinGrams,
      carbohydrateGrams: training.carbohydrateGrams,
      fatGrams: training.fatGrams,
      proteinPercent: training.proteinPercent,
      carbohydratePercent: training.carbohydratePercent,
      fatPercent: training.fatPercent,
      origin: origin,
      algorithmVersion: algorithmVersion,
      reason: reason,
      saltGrams: clearSaltGrams ? null : saltGrams ?? this.saltGrams,
      restDay: clearRestDay ? null : restDay ?? this.restDay,
      fiberGrams: clearFiberGrams ? null : fiberGrams ?? this.fiberGrams,
    );
  }

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
    if (saltGrams != null) 'saltGrams': saltGrams,
    if (restDay case final rest?) 'restDay': rest.toJson(),
    if (fiberGrams != null) 'fiberGrams': fiberGrams,
  };
}

/// kcal und Makros eines Tagesziels (Trainings- oder Ruhetag).
class NutritionDayTarget {
  const NutritionDayTarget({
    required this.inputMode,
    required this.kilocalories,
    required this.proteinGrams,
    required this.carbohydrateGrams,
    required this.fatGrams,
    this.proteinPercent,
    this.carbohydratePercent,
    this.fatPercent,
  });

  factory NutritionDayTarget.fromJson(Map<String, dynamic> json) =>
      NutritionDayTarget(
        inputMode: NutritionTargetInputMode.values.firstWhere(
          (e) =>
              e.name.toLowerCase() ==
              ((json['inputMode'] as String?) ?? 'Grams').toLowerCase(),
        ),
        kilocalories: _number(json, 'kilocalories'),
        proteinGrams: _number(json, 'proteinGrams'),
        carbohydrateGrams: _number(json, 'carbohydrateGrams'),
        fatGrams: _number(json, 'fatGrams'),
        proteinPercent: (json['proteinPercent'] as num?)?.toDouble(),
        carbohydratePercent: (json['carbohydratePercent'] as num?)?.toDouble(),
        fatPercent: (json['fatPercent'] as num?)?.toDouble(),
      );

  final NutritionTargetInputMode inputMode;
  final double kilocalories, proteinGrams, carbohydrateGrams, fatGrams;
  final double? proteinPercent, carbohydratePercent, fatPercent;

  double get macroEnergyKilocalories =>
      proteinGrams * 4 + carbohydrateGrams * 4 + fatGrams * 9;

  Map<String, Object?> toJson() => {
    'inputMode': _title(inputMode.name),
    'kilocalories': kilocalories,
    'proteinGrams': proteinGrams,
    'carbohydrateGrams': carbohydrateGrams,
    'fatGrams': fatGrams,
    'proteinPercent': proteinPercent,
    'carbohydratePercent': carbohydratePercent,
    'fatPercent': fatPercent,
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

  /// Zielphase, die an [localDate] gilt: die zuletzt beginnende passende.
  NutritionTargetVersion? targetOn(String localDate) => versions
      .where(
        (phase) =>
            phase.effectiveFrom.compareTo(localDate) <= 0 &&
            (phase.effectiveUntil == null ||
                phase.effectiveUntil!.compareTo(localDate) >= 0),
      )
      .lastOrNull;

  Map<String, Object?> toJson() => {
    'versions': [for (final item in versions) item.toJson()],
  };
}

NutritionTotals calculatePer100Totals({
  required double amountGrams,
  required NutritionTotals totals,
}) {
  if (!amountGrams.isFinite || amountGrams <= 0) {
    throw const NutritionValidationException({
      'amountGrams': 'Menge muss positiv sein.',
    });
  }
  return NutritionTotals(
    kilocalories: roundNutrition(totals.kilocalories * 100 / amountGrams),
    proteinGrams: _scale(totals.proteinGrams, 100 / amountGrams),
    carbohydrateGrams: _scale(totals.carbohydrateGrams, 100 / amountGrams),
    fatGrams: _scale(totals.fatGrams, 100 / amountGrams),
    saltGrams: _scale(totals.saltGrams, 100 / amountGrams),
    fiberGrams: _scale(totals.fiberGrams, 100 / amountGrams),
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
    throw const NutritionValidationException({
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

/// Stückwerte lokal flach, vom Server als `portion`-Objekt.
double? _portionValue(Map<String, dynamic> json, String key) {
  final portion = json['portion'];
  final value = portion is Map ? portion[key] : json[key];
  return value is num ? value.toDouble() : null;
}

/// Gramm für [count] Stück zu je [pieceGrams], auf zwei Stellen gerundet.
double gramsForPieces(double count, double pieceGrams) =>
    roundNutrition(count * pieceGrams);

void validatePortion(
  double amountGrams,
  double? pieceGrams,
  double? pieceCount,
) {
  if (pieceGrams == null && pieceCount == null) return;
  if (pieceGrams == null ||
      !pieceGrams.isFinite ||
      pieceGrams <= 0 ||
      pieceGrams > 5000) {
    throw const NutritionValidationException({
      'pieceGrams': 'Das Gewicht pro Stück muss zwischen 0 und 5.000 g liegen.',
    });
  }
  if (pieceCount == null) return;
  if (!pieceCount.isFinite || pieceCount <= 0 || pieceCount > 1000) {
    throw const NutritionValidationException({
      'pieceCount': 'Die Stückzahl muss zwischen 0 und 1.000 liegen.',
    });
  }
  if ((gramsForPieces(pieceCount, pieceGrams) - amountGrams).abs() > 0.01) {
    throw const NutritionValidationException({
      'amountGrams': 'Die Menge passt nicht zur Stückzahl.',
    });
  }
}

void validateNutritionEntry(NutritionEntry entry) {
  if (entry.entryId.isEmpty ||
      entry.position < 0 ||
      entry.productName.isEmpty ||
      entry.productName.length > 160) {
    throw const NutritionValidationException({
      'entry': 'Eintrag ist ungültig.',
    });
  }
  if (!entry.amountGrams.isFinite ||
      entry.amountGrams <= 0 ||
      entry.amountGrams > 100000) {
    throw const NutritionValidationException({
      'amountGrams': 'Menge muss positiv und plausibel sein.',
    });
  }
  if (entry.brand != null && entry.brand!.length > 120) {
    throw const NutritionValidationException({'brand': 'Marke ist zu lang.'});
  }
  _validateTotals(entry.per100Grams);
  validatePortion(entry.amountGrams, entry.pieceGrams, entry.pieceCount);
  if (entry.source case final source?) {
    if (!source.basisGrams.isFinite || source.basisGrams <= 0) {
      throw const NutritionValidationException({
        'source': 'Quellenbasis muss positiv sein.',
      });
    }
  }
}

/// 0 kcal ist gültig, z. B. für Salz, Wasser oder Zero-Getränke.
void _validateTotals(NutritionTotals totals) {
  if (!totals.kilocalories.isFinite || totals.kilocalories < 0) {
    throw const NutritionValidationException({
      'kilocalories': 'Kalorien dürfen nicht negativ sein.',
    });
  }
  for (final (key, value) in [
    ('proteinGrams', totals.proteinGrams),
    ('carbohydrateGrams', totals.carbohydrateGrams),
    ('fatGrams', totals.fatGrams),
    ('saltGrams', totals.saltGrams),
    ('fiberGrams', totals.fiberGrams),
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
    _validateTargetVersion(target, index, errors);
    if (index > 0) {
      _validateTargetOverlap(versions[index - 1], target, index, errors);
    }
  }
  if (errors.isNotEmpty) throw NutritionValidationException(errors);
}

void _validateTargetVersion(
  NutritionTargetVersion target,
  int index,
  Map<String, String> errors,
) {
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
  _validateDayTarget(target.trainingDay, 'versions.$index', errors);
  if (target.restDay case final rest?) {
    _validateDayTarget(rest, 'versions.$index.restDay', errors);
  }
  final salt = target.saltGrams;
  if (salt != null && (!salt.isFinite || salt <= 0 || salt > 100)) {
    errors['versions.$index.saltGrams'] =
        'Die Salzgrenze muss zwischen 0 und 100 g liegen.';
  }
  final fiber = target.fiberGrams;
  if (fiber != null && (!fiber.isFinite || fiber <= 0 || fiber > 100)) {
    errors['versions.$index.fiberGrams'] =
        'Das Ballaststoffziel muss zwischen 0 und 100 g liegen.';
  }
}

/// Prüft kcal, Makros und Prozentanteile eines Tagesziels.
void _validateDayTarget(
  NutritionDayTarget target,
  String prefix,
  Map<String, String> errors,
) {
  if (![
        target.kilocalories,
        target.proteinGrams,
        target.carbohydrateGrams,
        target.fatGrams,
      ].every((v) => v.isFinite && v >= 0) ||
      target.kilocalories <= 0) {
    errors['$prefix.nutrients'] =
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
      errors['$prefix.percentages'] =
          'Makroanteile müssen zusammen 100 % ergeben.';
    }
  }
}

/// Prüft ein Tagesziel einzeln, z. B. im Editor vor dem Speichern.
Map<String, String> validateDayTarget(NutritionDayTarget target) {
  final errors = <String, String>{};
  _validateDayTarget(target, 'target', errors);
  return errors;
}

void _validateTargetOverlap(
  NutritionTargetVersion previous,
  NutritionTargetVersion target,
  int index,
  Map<String, String> errors,
) {
  if (previous.effectiveUntil == null ||
      previous.effectiveUntil!.compareTo(target.effectiveFrom) >= 0) {
    errors['versions.$index.effectiveFrom'] = 'Zielphasen dürfen sich nicht überschneiden; die vorherige Phase braucht ein Enddatum.';
  }
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
