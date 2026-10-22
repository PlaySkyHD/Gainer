import 'dart:convert';

class ApiSession {
  const ApiSession({
    required this.userId,
    required this.email,
    required this.isAccountOperator,
  });

  final String userId;
  final String email;
  final bool isAccountOperator;

  factory ApiSession.fromJson(Map<String, dynamic> json) => ApiSession(
    userId: _requiredString(json, 'userId'),
    email: _requiredString(json, 'email'),
    isAccountOperator: _requiredBool(json, 'isAccountOperator'),
  );
}

/// Token pair of a device session. The refresh token rotates on every use.
class ApiTokenResponse {
  const ApiTokenResponse({
    required this.accessToken,
    required this.expiresIn,
    required this.refreshToken,
  });

  final String accessToken;

  /// Lifetime of [accessToken] in seconds.
  final int expiresIn;
  final String refreshToken;

  factory ApiTokenResponse.fromJson(Map<String, dynamic> json) =>
      ApiTokenResponse(
        accessToken: _requiredString(json, 'accessToken'),
        expiresIn: _requiredInt(json, 'expiresIn'),
        refreshToken: _requiredString(json, 'refreshToken'),
      );
}

class ApiExerciseCatalogItem {
  const ApiExerciseCatalogItem({
    required this.id,
    required this.name,
    required this.isCustom,
    required this.version,
    required this.exerciseType,
    this.description,
    this.targetMuscle,
    this.muscleGroup,
    this.equipment,
    this.notes,
    this.bodyweightFactor,
    this.weightFactor,
    this.categoryIds = const [],
    this.primaryMuscles = const [],
    this.secondaryMuscles = const [],
    this.catalogVersion,
  });

  final String id;
  final String name;
  final String? description;
  final String? targetMuscle;
  final String? muscleGroup;
  final String? equipment;
  final String exerciseType;
  final String? notes;
  final double? bodyweightFactor;
  final double? weightFactor;
  final List<String> categoryIds;
  final List<String> primaryMuscles;
  final List<String> secondaryMuscles;
  final bool isCustom;
  final String? catalogVersion;
  final int version;

  factory ApiExerciseCatalogItem.fromJson(Map<String, dynamic> json) =>
      ApiExerciseCatalogItem(
        id: _requiredString(json, 'id'),
        name: _requiredString(json, 'name'),
        description: json['description'] as String?,
        targetMuscle: json['targetMuscle'] as String?,
        muscleGroup: json['muscleGroup'] as String?,
        equipment: json['equipment'] as String?,
        exerciseType: _requiredString(json, 'exerciseType'),
        notes: json['notes'] as String?,
        bodyweightFactor: (json['bodyweightFactor'] as num?)?.toDouble(),
        weightFactor: (json['weightFactor'] as num?)?.toDouble(),
        categoryIds: [
          for (final id in (json['categoryIds'] as List<Object?>? ?? const []))
            id! as String,
        ],
        primaryMuscles: [
          for (final key in (json['primaryMuscles'] as List<Object?>? ?? []))
            key! as String,
        ],
        secondaryMuscles: [
          for (final key in (json['secondaryMuscles'] as List<Object?>? ?? []))
            key! as String,
        ],
        isCustom: _requiredBool(json, 'isCustom'),
        catalogVersion: json['catalogVersion'] as String?,
        version: _requiredInt(json, 'version'),
      );
}

class ApiExerciseCategory {
  const ApiExerciseCategory({
    required this.id,
    required this.name,
    required this.isBase,
  });

  final String id;
  final String name;
  final bool isBase;

  factory ApiExerciseCategory.fromJson(Map<String, dynamic> json) =>
      ApiExerciseCategory(
        id: _requiredString(json, 'id'),
        name: _requiredString(json, 'name'),
        isBase: _requiredBool(json, 'isBase'),
      );
}

class ApiExerciseCatalogResponse {
  const ApiExerciseCatalogResponse({
    required this.items,
    required this.offset,
    required this.limit,
    required this.total,
    required this.categories,
  });

  final List<ApiExerciseCatalogItem> items;
  final int offset;
  final int limit;
  final int total;
  final List<ApiExerciseCategory> categories;

  factory ApiExerciseCatalogResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    if (rawItems is! List ||
        rawItems.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException('Invalid exercise catalog items.');
    }
    final rawCategories = json['categories'];
    if (rawCategories is! List ||
        rawCategories.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException('Invalid exercise categories.');
    }
    return ApiExerciseCatalogResponse(
      items: rawItems
          .cast<Map<String, dynamic>>()
          .map(ApiExerciseCatalogItem.fromJson)
          .toList(growable: false),
      offset: _requiredInt(json, 'offset'),
      limit: _requiredInt(json, 'limit'),
      total: _requiredInt(json, 'total'),
      categories: rawCategories
          .cast<Map<String, dynamic>>()
          .map(ApiExerciseCategory.fromJson)
          .toList(growable: false),
    );
  }
}

class ApiFoodProduct {
  const ApiFoodProduct({
    required this.barcode,
    required this.productName,
    required this.basisGrams,
    required this.kilocaloriesPer100Grams,
    required this.qualityIndicators,
    required this.retrievedAtUtc,
    required this.isStale,
    required this.source,
    this.brand,
    this.proteinGramsPer100Grams,
    this.carbohydrateGramsPer100Grams,
    this.fatGramsPer100Grams,
    this.saltGramsPer100Grams,
  });

  final String barcode;
  final String productName;
  final String? brand;
  final double basisGrams;
  final double kilocaloriesPer100Grams;
  final double? proteinGramsPer100Grams;
  final double? carbohydrateGramsPer100Grams;
  final double? fatGramsPer100Grams;
  final double? saltGramsPer100Grams;
  final List<String> qualityIndicators;
  final DateTime retrievedAtUtc;
  final bool isStale;
  final String source;

  factory ApiFoodProduct.fromJson(Map<String, dynamic> json) {
    final indicators = json['qualityIndicators'];
    if (indicators is! List || indicators.any((item) => item is! String)) {
      throw const FormatException('Invalid food quality indicators.');
    }
    return ApiFoodProduct(
      barcode: _requiredString(json, 'barcode'),
      productName: _requiredString(json, 'productName'),
      brand: json['brand'] as String?,
      basisGrams: _requiredDouble(json, 'basisGrams'),
      kilocaloriesPer100Grams: _requiredDouble(json, 'kilocaloriesPer100Grams'),
      proteinGramsPer100Grams: _nullableDouble(json, 'proteinGramsPer100Grams'),
      carbohydrateGramsPer100Grams: _nullableDouble(
        json,
        'carbohydrateGramsPer100Grams',
      ),
      fatGramsPer100Grams: _nullableDouble(json, 'fatGramsPer100Grams'),
      saltGramsPer100Grams: _nullableDouble(json, 'saltGramsPer100Grams'),
      qualityIndicators: indicators.cast<String>(),
      retrievedAtUtc: DateTime.parse(_requiredString(json, 'retrievedAtUtc'))
          .toUtc(),
      isStale: _requiredBool(json, 'isStale'),
      source: _requiredString(json, 'source'),
    );
  }
}

class ApiFoodSearchResponse {
  const ApiFoodSearchResponse({
    required this.products,
    required this.page,
    required this.hasMore,
  });

  final List<ApiFoodProduct> products;
  final int page;
  final bool hasMore;

  factory ApiFoodSearchResponse.fromJson(Map<String, dynamic> json) {
    final products = json['products'];
    if (products is! List ||
        products.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException('Invalid food products.');
    }
    return ApiFoodSearchResponse(
      products: products
          .cast<Map<String, dynamic>>()
          .map(ApiFoodProduct.fromJson)
          .toList(growable: false),
      page: _requiredInt(json, 'page'),
      hasMore: _requiredBool(json, 'hasMore'),
    );
  }
}

class ApiMealEstimateComponent {
  const ApiMealEstimateComponent({
    required this.name,
    required this.amountGrams,
    required this.kilocalories,
    required this.confidence,
    required this.dataGaps,
    this.proteinGrams,
    this.carbohydrateGrams,
    this.fatGrams,
    this.saltGrams,
  });

  final String name;
  final double amountGrams;
  final double kilocalories;
  final double? proteinGrams;
  final double? carbohydrateGrams;
  final double? fatGrams;

  /// Nur bei Salz, das im Essen selbst steckt; fehlt bei älteren Servern.
  final double? saltGrams;
  final String confidence;
  final List<String> dataGaps;

  factory ApiMealEstimateComponent.fromJson(Map<String, dynamic> json) {
    final gaps = json['dataGaps'];
    if (gaps is! List || gaps.any((item) => item is! String)) {
      throw const FormatException('Invalid meal estimate data gaps.');
    }
    return ApiMealEstimateComponent(
      name: _requiredString(json, 'name'),
      amountGrams: _requiredDouble(json, 'amountGrams'),
      kilocalories: _requiredDouble(json, 'kilocalories'),
      proteinGrams: _nullableDouble(json, 'proteinGrams'),
      carbohydrateGrams: _nullableDouble(json, 'carbohydrateGrams'),
      fatGrams: _nullableDouble(json, 'fatGrams'),
      saltGrams: _nullableDouble(json, 'saltGrams'),
      confidence: _requiredString(json, 'confidence'),
      dataGaps: gaps.cast<String>(),
    );
  }
}

class ApiMealEstimateResponse {
  const ApiMealEstimateResponse({
    required this.components,
    required this.provider,
    required this.schemaVersion,
    required this.estimatedAtUtc,
  });

  final List<ApiMealEstimateComponent> components;
  final String provider;
  final String schemaVersion;
  final DateTime estimatedAtUtc;

  factory ApiMealEstimateResponse.fromJson(Map<String, dynamic> json) {
    final components = json['components'];
    if (components is! List ||
        components.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException('Invalid meal estimate components.');
    }
    return ApiMealEstimateResponse(
      components: components
          .cast<Map<String, dynamic>>()
          .map(ApiMealEstimateComponent.fromJson)
          .toList(growable: false),
      provider: _requiredString(json, 'provider'),
      schemaVersion: _requiredString(json, 'schemaVersion'),
      estimatedAtUtc: DateTime.parse(_requiredString(json, 'estimatedAtUtc'))
          .toUtc(),
    );
  }
}

class ApiNutritionLabelField {
  const ApiNutritionLabelField({
    this.originalValue,
    this.per100Grams,
    required this.status,
    this.evidence,
  });

  final double? originalValue;
  final double? per100Grams;
  final String status;
  final String? evidence;

  factory ApiNutritionLabelField.fromJson(Map<String, dynamic> json) =>
      ApiNutritionLabelField(
        originalValue: _nullableDouble(json, 'originalValue'),
        per100Grams: _nullableDouble(json, 'per100Grams'),
        status: _requiredString(json, 'status'),
        evidence: json['evidence'] as String?,
      );
}

class ApiNutritionLabelScanResponse {
  const ApiNutritionLabelScanResponse({
    required this.basis,
    required this.canConfirm,
    required this.provider,
    required this.providerModelVersion,
    required this.parserVersion,
    required this.scannedAtUtc,
    required this.kilocalories,
    required this.proteinGrams,
    required this.carbohydrateGrams,
    required this.fatGrams,
    this.saltGrams,
    this.servingMassGrams,
  });

  final String basis;
  final double? servingMassGrams;
  final ApiNutritionLabelField kilocalories;
  final ApiNutritionLabelField proteinGrams;
  final ApiNutritionLabelField carbohydrateGrams;
  final ApiNutritionLabelField fatGrams;

  /// Fehlt bei älteren Servern.
  final ApiNutritionLabelField? saltGrams;
  final bool canConfirm;
  final String provider;
  final String providerModelVersion;
  final String parserVersion;
  final DateTime scannedAtUtc;

  factory ApiNutritionLabelScanResponse.fromJson(Map<String, dynamic> json) =>
      ApiNutritionLabelScanResponse(
        basis: _requiredString(json, 'basis'),
        servingMassGrams: _nullableDouble(json, 'servingMassGrams'),
        kilocalories: ApiNutritionLabelField.fromJson(
          _requiredObject(json, 'kilocalories'),
        ),
        proteinGrams: ApiNutritionLabelField.fromJson(
          _requiredObject(json, 'proteinGrams'),
        ),
        carbohydrateGrams: ApiNutritionLabelField.fromJson(
          _requiredObject(json, 'carbohydrateGrams'),
        ),
        fatGrams: ApiNutritionLabelField.fromJson(
          _requiredObject(json, 'fatGrams'),
        ),
        saltGrams: json['saltGrams'] is Map<String, dynamic>
            ? ApiNutritionLabelField.fromJson(
                json['saltGrams'] as Map<String, dynamic>,
              )
            : null,
        canConfirm: _requiredBool(json, 'canConfirm'),
        provider: _requiredString(json, 'provider'),
        providerModelVersion: _requiredString(json, 'providerModelVersion'),
        parserVersion: _requiredString(json, 'parserVersion'),
        scannedAtUtc: DateTime.parse(_requiredString(json, 'scannedAtUtc'))
            .toUtc(),
      );
}

class ApiDashboardInsights {
  const ApiDashboardInsights({
    required this.asOfRevision,
    required this.from,
    required this.through,
    required this.weightSeries,
    required this.sevenDayWeight,
    required this.weight,
    required this.nutrition,
    required this.training,
    required this.workoutsLast7Days,
    this.rawJson,
    this.activeGoal,
    this.latestWeight,
  });

  final int asOfRevision;
  final String from;
  final String through;
  final List<ApiWeightPoint> weightSeries;
  final ApiWeightInsights sevenDayWeight;
  final ApiWeightInsights weight;
  final ApiNutritionInsights nutrition;
  final ApiTrainingInsights training;
  final int workoutsLast7Days;
  final Map<String, dynamic>? rawJson;
  final ApiActiveGoalInsight? activeGoal;
  final ApiWeightPoint? latestWeight;

  factory ApiDashboardInsights.fromJson(Map<String, dynamic> json) {
    final points = json['weightSeries'];
    if (points is! List ||
        points.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException('Invalid dashboard weight series.');
    }
    final active = json['activeGoal'];
    final latest = json['latestWeight'];
    return ApiDashboardInsights(
      asOfRevision: _requiredInt(json, 'asOfRevision'),
      rawJson: Map<String, dynamic>.unmodifiable(json),
      from: _requiredString(json, 'from'),
      through: _requiredString(json, 'through'),
      activeGoal: active == null
          ? null
          : ApiActiveGoalInsight.fromJson(_objectValue(active, 'activeGoal')),
      latestWeight: latest == null
          ? null
          : ApiWeightPoint.fromJson(_objectValue(latest, 'latestWeight')),
      weightSeries: points
          .cast<Map<String, dynamic>>()
          .map(ApiWeightPoint.fromJson)
          .toList(growable: false),
      sevenDayWeight: ApiWeightInsights.fromJson(
        _requiredObject(json, 'sevenDayWeight'),
      ),
      weight: ApiWeightInsights.fromJson(_requiredObject(json, 'weight')),
      nutrition: ApiNutritionInsights.fromJson(
        _requiredObject(json, 'nutrition'),
      ),
      training: ApiTrainingInsights.fromJson(_requiredObject(json, 'training')),
      workoutsLast7Days: _requiredInt(json, 'workoutsLast7Days'),
    );
  }

  Map<String, dynamic>? toCacheJson() => rawJson;
}

class ApiExerciseProgress {
  const ApiExerciseProgress({
    required this.asOfRevision,
    required this.exerciseId,
    required this.windowDays,
    required this.fromUtc,
    required this.throughUtc,
    required this.volumeAlgorithmVersion,
    required this.estimatedOneRepMaxAlgorithmVersion,
    required this.points,
    required this.bestSet,
    required this.records,
  });

  final int asOfRevision;
  final String exerciseId;
  final int? windowDays;
  final DateTime fromUtc;
  final DateTime throughUtc;
  final String volumeAlgorithmVersion;
  final String estimatedOneRepMaxAlgorithmVersion;
  final List<ApiExerciseProgressPoint> points;
  final ApiBestSetInsight? bestSet;
  final ApiExerciseRecords records;

  factory ApiExerciseProgress.fromJson(Map<String, dynamic> json) {
    final rawPoints = json['points'];
    if (rawPoints is! List ||
        rawPoints.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException('Invalid exercise progress points.');
    }
    final rawWindow = json['windowDays'];
    return ApiExerciseProgress(
      asOfRevision: _requiredInt(json, 'asOfRevision'),
      exerciseId: _requiredString(json, 'exerciseId'),
      windowDays: rawWindow == null ? null : _intValue(rawWindow, 'windowDays'),
      fromUtc: DateTime.parse(_requiredString(json, 'fromUtc')).toUtc(),
      throughUtc: DateTime.parse(_requiredString(json, 'throughUtc')).toUtc(),
      volumeAlgorithmVersion: _requiredString(json, 'volumeAlgorithmVersion'),
      estimatedOneRepMaxAlgorithmVersion: _requiredString(
        json,
        'estimatedOneRepMaxAlgorithmVersion',
      ),
      points: rawPoints
          .cast<Map<String, dynamic>>()
          .map(ApiExerciseProgressPoint.fromJson)
          .toList(growable: false),
      bestSet: json['bestSet'] == null
          ? null
          : ApiBestSetInsight.fromJson(
              _objectValue(json['bestSet'], 'bestSet'),
            ),
      records: ApiExerciseRecords.fromJson(_requiredObject(json, 'records')),
    );
  }

  Map<String, dynamic> toJson() => {
    'asOfRevision': asOfRevision,
    'exerciseId': exerciseId,
    'windowDays': windowDays,
    'fromUtc': fromUtc.toIso8601String(),
    'throughUtc': throughUtc.toIso8601String(),
    'volumeAlgorithmVersion': volumeAlgorithmVersion,
    'estimatedOneRepMaxAlgorithmVersion': estimatedOneRepMaxAlgorithmVersion,
    'points': points.map((point) => point.toJson()).toList(growable: false),
    'bestSet': bestSet?.toJson(),
    'records': records.toJson(),
  };
}

class ApiExerciseProgressPoint {
  const ApiExerciseProgressPoint({
    required this.workoutId,
    required this.completedAtUtc,
    required this.volumeKgRepetitions,
    required this.maxWeightKg,
    required this.maxRepetitions,
    required this.estimatedOneRepMaxKg,
    required this.bodyweightMissing,
  });

  final String workoutId;
  final DateTime completedAtUtc;
  final double volumeKgRepetitions;
  final double? maxWeightKg;
  final int maxRepetitions;
  final double? estimatedOneRepMaxKg;
  final bool bodyweightMissing;

  factory ApiExerciseProgressPoint.fromJson(Map<String, dynamic> json) =>
      ApiExerciseProgressPoint(
        workoutId: _requiredString(json, 'workoutId'),
        completedAtUtc: DateTime.parse(_requiredString(json, 'completedAtUtc'))
            .toUtc(),
        volumeKgRepetitions: _requiredDouble(json, 'volumeKgRepetitions'),
        maxWeightKg: _nullableDouble(json, 'maxWeightKg'),
        maxRepetitions: _requiredInt(json, 'maxRepetitions'),
        estimatedOneRepMaxKg: _nullableDouble(json, 'estimatedOneRepMaxKg'),
        bodyweightMissing: _requiredBool(json, 'bodyweightMissing'),
      );

  Map<String, dynamic> toJson() => {
    'workoutId': workoutId,
    'completedAtUtc': completedAtUtc.toIso8601String(),
    'volumeKgRepetitions': volumeKgRepetitions,
    'maxWeightKg': maxWeightKg,
    'maxRepetitions': maxRepetitions,
    'estimatedOneRepMaxKg': estimatedOneRepMaxKg,
    'bodyweightMissing': bodyweightMissing,
  };
}

/// Bestes Set; [effectiveWeightKg] enthält bei Körpergewichtsübungen den Körpergewichtsanteil.
class ApiBestSetInsight {
  const ApiBestSetInsight({
    required this.workoutId,
    required this.exerciseId,
    required this.completedAtUtc,
    required this.effectiveWeightKg,
    required this.repetitions,
    required this.estimatedOneRepMaxKg,
  });

  final String workoutId;
  final String exerciseId;
  final DateTime completedAtUtc;
  final double effectiveWeightKg;
  final int repetitions;
  final double estimatedOneRepMaxKg;

  factory ApiBestSetInsight.fromJson(Map<String, dynamic> json) =>
      ApiBestSetInsight(
        workoutId: _requiredString(json, 'workoutId'),
        exerciseId: _requiredString(json, 'exerciseId'),
        completedAtUtc: DateTime.parse(_requiredString(json, 'completedAtUtc'))
            .toUtc(),
        effectiveWeightKg: _requiredDouble(json, 'effectiveWeightKg'),
        repetitions: _requiredInt(json, 'repetitions'),
        estimatedOneRepMaxKg: _requiredDouble(json, 'estimatedOneRepMaxKg'),
      );

  Map<String, dynamic> toJson() => {
    'workoutId': workoutId,
    'exerciseId': exerciseId,
    'completedAtUtc': completedAtUtc.toIso8601String(),
    'effectiveWeightKg': effectiveWeightKg,
    'repetitions': repetitions,
    'estimatedOneRepMaxKg': estimatedOneRepMaxKg,
  };
}

class ApiRecordEvent {
  const ApiRecordEvent({required this.workoutId, required this.value});
  final String workoutId;
  final double value;

  factory ApiRecordEvent.fromJson(Map<String, dynamic> json) => ApiRecordEvent(
    workoutId: _requiredString(json, 'workoutId'),
    value: _requiredDouble(json, 'value'),
  );

  Map<String, dynamic> toJson() => {'workoutId': workoutId, 'value': value};
}

class ApiRepetitionRecord {
  const ApiRepetitionRecord({
    required this.repetitions,
    required this.maxWeightKg,
  });
  final int repetitions;
  final double? maxWeightKg;

  factory ApiRepetitionRecord.fromJson(Map<String, dynamic> json) =>
      ApiRepetitionRecord(
        repetitions: _requiredInt(json, 'repetitions'),
        maxWeightKg: _nullableDouble(json, 'maxWeightKg'),
      );

  Map<String, dynamic> toJson() => {
    'repetitions': repetitions,
    'maxWeightKg': maxWeightKg,
  };
}

/// Rekorde gelten für die gesamte Historie bis zum Stichtag, nicht nur für das gewählte Fenster.
class ApiExerciseRecords {
  const ApiExerciseRecords({
    required this.maxWeightKg,
    required this.estimatedOneRepMaxKg,
    required this.volumeKgRepetitions,
    required this.maxRepetitions,
    required this.repetitionRecords,
  });

  final ApiRecordEvent? maxWeightKg;
  final ApiRecordEvent? estimatedOneRepMaxKg;
  final ApiRecordEvent? volumeKgRepetitions;
  final ApiRecordEvent? maxRepetitions;
  final List<ApiRepetitionRecord> repetitionRecords;

  factory ApiExerciseRecords.fromJson(Map<String, dynamic> json) {
    final rawRepetitionRecords = json['repetitionRecords'];
    if (rawRepetitionRecords is! List ||
        rawRepetitionRecords.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException('Invalid repetition records.');
    }
    return ApiExerciseRecords(
      maxWeightKg: _nullableRecordEvent(json, 'maxWeightKg'),
      estimatedOneRepMaxKg: _nullableRecordEvent(json, 'estimatedOneRepMaxKg'),
      volumeKgRepetitions: _nullableRecordEvent(json, 'volumeKgRepetitions'),
      maxRepetitions: _nullableRecordEvent(json, 'maxRepetitions'),
      repetitionRecords: rawRepetitionRecords
          .cast<Map<String, dynamic>>()
          .map(ApiRepetitionRecord.fromJson)
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
    'maxWeightKg': maxWeightKg?.toJson(),
    'estimatedOneRepMaxKg': estimatedOneRepMaxKg?.toJson(),
    'volumeKgRepetitions': volumeKgRepetitions?.toJson(),
    'maxRepetitions': maxRepetitions?.toJson(),
    'repetitionRecords': repetitionRecords
        .map((record) => record.toJson())
        .toList(growable: false),
  };
}

ApiRecordEvent? _nullableRecordEvent(Map<String, dynamic> json, String name) =>
    json[name] == null
    ? null
    : ApiRecordEvent.fromJson(_objectValue(json[name], name));

class ApiWeightPoint {
  const ApiWeightPoint({required this.date, required this.weightKg});
  final String date;
  final double weightKg;
  factory ApiWeightPoint.fromJson(Map<String, dynamic> json) => ApiWeightPoint(
    date: _requiredString(json, 'date'),
    weightKg: _requiredDouble(json, 'weightKg'),
  );
}

class ApiWeightInsights {
  const ApiWeightInsights({
    required this.unit,
    required this.expectedDays,
    required this.observedDays,
    required this.coverage,
    this.averageKg,
    this.trendKgPerWeek,
  });
  final String unit;
  final int expectedDays;
  final int observedDays;
  final double coverage;
  final double? averageKg;
  final double? trendKgPerWeek;
  factory ApiWeightInsights.fromJson(Map<String, dynamic> json) =>
      ApiWeightInsights(
        unit: _requiredString(json, 'unit'),
        expectedDays: _requiredInt(json, 'expectedDays'),
        observedDays: _requiredInt(json, 'observedDays'),
        coverage: _requiredDouble(json, 'coverage'),
        averageKg: _nullableDouble(json, 'averageKg'),
        trendKgPerWeek: _nullableDouble(json, 'trendKgPerWeek'),
      );
}

class ApiActiveGoalInsight {
  const ApiActiveGoalInsight({
    required this.kind,
    required this.startWeightKg,
    required this.targetWeightKg,
    required this.startDate,
    this.targetDate,
  });
  final String kind;
  final double startWeightKg;
  final double targetWeightKg;
  final String startDate;
  final String? targetDate;
  factory ApiActiveGoalInsight.fromJson(Map<String, dynamic> json) =>
      ApiActiveGoalInsight(
        kind: _requiredString(json, 'kind'),
        startWeightKg: _requiredDouble(json, 'startWeightKg'),
        targetWeightKg: _requiredDouble(json, 'targetWeightKg'),
        startDate: _requiredString(json, 'startDate'),
        targetDate: json['targetDate'] as String?,
      );
}

class ApiNutritionInsights {
  const ApiNutritionInsights({
    required this.expectedDays,
    required this.observedDays,
    required this.coverage,
    required this.mealDiaryDays,
    required this.legacyCheckInDays,
    required this.caloriesKcal,
    required this.proteinGrams,
    required this.carbohydrateGrams,
    required this.fatGrams,
  });
  final int expectedDays, observedDays, mealDiaryDays, legacyCheckInDays;
  final double coverage;
  final ApiMetricAverage caloriesKcal,
      proteinGrams,
      carbohydrateGrams,
      fatGrams;
  factory ApiNutritionInsights.fromJson(Map<String, dynamic> json) =>
      ApiNutritionInsights(
        expectedDays: _requiredInt(json, 'expectedDays'),
        observedDays: _requiredInt(json, 'observedDays'),
        coverage: _requiredDouble(json, 'coverage'),
        mealDiaryDays: _requiredInt(json, 'mealDiaryDays'),
        legacyCheckInDays: _requiredInt(json, 'legacyCheckInDays'),
        caloriesKcal: ApiMetricAverage.fromJson(
          _requiredObject(json, 'caloriesKcal'),
        ),
        proteinGrams: ApiMetricAverage.fromJson(
          _requiredObject(json, 'proteinGrams'),
        ),
        carbohydrateGrams: ApiMetricAverage.fromJson(
          _requiredObject(json, 'carbohydrateGrams'),
        ),
        fatGrams: ApiMetricAverage.fromJson(_requiredObject(json, 'fatGrams')),
      );
}

class ApiMetricAverage {
  const ApiMetricAverage({required this.observedDays, this.value});
  final double? value;
  final int observedDays;
  factory ApiMetricAverage.fromJson(Map<String, dynamic> json) =>
      ApiMetricAverage(
        value: _nullableDouble(json, 'value'),
        observedDays: _requiredInt(json, 'observedDays'),
      );
}

class ApiTrainingInsights {
  const ApiTrainingInsights({
    required this.volumeAlgorithmVersion,
    required this.estimatedOneRepMaxAlgorithmVersion,
    required this.volumeUnit,
    required this.workoutCount,
    required this.volumeKgRepetitions,
    required this.bestSet,
    required this.bodyweightMissing,
  });
  final String volumeAlgorithmVersion;
  final String estimatedOneRepMaxAlgorithmVersion;
  final String volumeUnit;
  final int workoutCount;
  final double volumeKgRepetitions;
  final ApiBestSetInsight? bestSet;
  final bool bodyweightMissing;
  factory ApiTrainingInsights.fromJson(Map<String, dynamic> json) =>
      ApiTrainingInsights(
        volumeAlgorithmVersion: _requiredString(json, 'volumeAlgorithmVersion'),
        estimatedOneRepMaxAlgorithmVersion: _requiredString(
          json,
          'estimatedOneRepMaxAlgorithmVersion',
        ),
        volumeUnit: _requiredString(json, 'volumeUnit'),
        workoutCount: _requiredInt(json, 'workoutCount'),
        volumeKgRepetitions: _requiredDouble(json, 'volumeKgRepetitions'),
        bestSet: json['bestSet'] == null
            ? null
            : ApiBestSetInsight.fromJson(
                _objectValue(json['bestSet'], 'bestSet'),
              ),
        bodyweightMissing: _requiredBool(json, 'bodyweightMissing'),
      );
}

class ApiCoachResponse {
  const ApiCoachResponse({
    required this.summary,
    required this.observations,
    required this.dataGaps,
    required this.suggestions,
    required this.asOfRevision,
  });
  final String summary;
  final List<String> observations, dataGaps, suggestions;
  final int asOfRevision;
  factory ApiCoachResponse.fromJson(Map<String, dynamic> json) {
    final observations = json['observations'];
    if (observations is! List ||
        observations.any(
          (item) => item is! Map<String, dynamic> || item['text'] is! String,
        )) {
      throw const FormatException('Invalid coach observations.');
    }
    return ApiCoachResponse(
      summary: _requiredString(json, 'summary'),
      observations: observations
          .map((item) => (item as Map<String, dynamic>)['text'] as String)
          .toList(growable: false),
      dataGaps: _requiredStringList(json, 'dataGaps'),
      suggestions: _requiredStringList(json, 'suggestions'),
      asOfRevision: _requiredInt(json, 'asOfRevision'),
    );
  }
}

class ApiLoginRequest {
  const ApiLoginRequest({
    required this.email,
    required this.password,
    this.deviceName,
  });

  final String email;
  final String password;

  /// Shown in the device session list, e.g. „Gainer iPhone“.
  final String? deviceName;

  Map<String, Object?> toJson() => {
    'email': email,
    'password': password,
    'deviceName': ?deviceName,
  };
}

class ApiAcceptInvitationRequest {
  const ApiAcceptInvitationRequest({
    required this.token,
    required this.password,
  });

  final String token;
  final String password;

  Map<String, Object?> toJson() => {'token': token, 'password': password};
}

class ApiAccountSummary {
  const ApiAccountSummary({
    required this.accountId,
    required this.email,
    required this.isActive,
  });

  final String accountId;
  final String email;
  final bool isActive;

  factory ApiAccountSummary.fromJson(Map<String, dynamic> json) =>
      ApiAccountSummary(
        accountId: _requiredString(json, 'accountId'),
        email: _requiredString(json, 'email'),
        isActive: _requiredBool(json, 'isActive'),
      );
}

/// WebAuthn options and the opaque single-use state of a passkey ceremony.
class ApiPasskeyOptions {
  const ApiPasskeyOptions({required this.optionsJson, required this.state});

  final String optionsJson;
  final String state;

  factory ApiPasskeyOptions.fromJson(Map<String, dynamic> json) =>
      ApiPasskeyOptions(
        optionsJson: _requiredString(json, 'optionsJson'),
        state: _requiredString(json, 'state'),
      );
}

class ApiPasskey {
  const ApiPasskey({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  /// Base64Url credential id.
  final String id;
  final String name;
  final DateTime createdAt;

  factory ApiPasskey.fromJson(Map<String, dynamic> json) => ApiPasskey(
    id: _requiredString(json, 'id'),
    name: _requiredString(json, 'name'),
    createdAt: DateTime.parse(_requiredString(json, 'createdAt')).toUtc(),
  );
}

class ApiInvitation {
  const ApiInvitation({required this.activationPath, required this.expiresAt});

  final String activationPath;
  final DateTime expiresAt;

  factory ApiInvitation.fromJson(Map<String, dynamic> json) => ApiInvitation(
    activationPath: _requiredString(json, 'activationPath'),
    expiresAt: DateTime.parse(_requiredString(json, 'expiresAt')).toUtc(),
  );
}

/// Error fields are read from both top-level API extensions and ProblemDetails.
class ApiProblem {
  const ApiProblem({this.title, this.detail, this.code, this.errors});

  final String? title;
  final String? detail;
  final String? code;
  final Map<String, Object?>? errors;

  String get message => detail ?? title ?? 'Die Anfrage ist fehlgeschlagen.';

  factory ApiProblem.fromJson(Map<String, dynamic> json) {
    final extensions = json['extensions'];
    return ApiProblem(
      title: json['title'] as String?,
      detail: json['detail'] as String?,
      code:
          json['code'] as String? ??
          (extensions is Map<String, dynamic>
              ? extensions['code'] as String?
              : null),
      errors: json['errors'] is Map<String, dynamic>
          ? Map<String, Object?>.from(json['errors'] as Map<String, dynamic>)
          : null,
    );
  }
}

Map<String, dynamic> decodeJsonObject(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Expected a JSON object.');
  }
  return decoded;
}

String _requiredString(Map<String, dynamic> json, String name) {
  final value = json[name];
  if (value is! String || value.isEmpty) {
    throw FormatException('Missing or invalid "$name".');
  }
  return value;
}

bool _requiredBool(Map<String, dynamic> json, String name) {
  final value = json[name];
  if (value is! bool) throw FormatException('Missing or invalid "$name".');
  return value;
}

int _requiredInt(Map<String, dynamic> json, String name) {
  final value = json[name];
  if (value is int) return value;
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw FormatException('Missing or invalid "$name".');
}

int _intValue(Object? value, String name) {
  if (value is int) return value;
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw FormatException('Missing or invalid "$name".');
}

double _requiredDouble(Map<String, dynamic> json, String name) {
  final result = _nullableDouble(json, name);
  if (result == null) throw FormatException('Missing or invalid "$name".');
  return result;
}

double? _nullableDouble(Map<String, dynamic> json, String name) {
  final value = json[name];
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  throw FormatException('Invalid "$name".');
}

Map<String, dynamic> _requiredObject(Map<String, dynamic> json, String name) {
  final value = json[name];
  if (value is! Map<String, dynamic>) {
    throw FormatException('Missing or invalid "$name".');
  }
  return value;
}

Map<String, dynamic> _objectValue(Object? value, String name) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('Missing or invalid "$name".');
  }
  return value;
}

List<String> _requiredStringList(Map<String, dynamic> json, String name) {
  final value = json[name];
  if (value is! List || value.any((item) => item is! String)) {
    throw FormatException('Missing or invalid "$name".');
  }
  return value.cast<String>();
}
