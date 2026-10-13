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

class ApiAntiforgeryToken {
  const ApiAntiforgeryToken(this.requestToken, this.authenticatedUserId);

  final String requestToken;
  final String? authenticatedUserId;

  factory ApiAntiforgeryToken.fromJson(Map<String, dynamic> json) =>
      ApiAntiforgeryToken(
        _requiredString(json, 'requestToken'),
        json['authenticatedUserId'] as String?,
      );
}

class ApiExerciseCatalogItem {
  const ApiExerciseCatalogItem({
    required this.id,
    required this.name,
    required this.isCustom,
    required this.version,
    this.description,
    this.targetMuscle,
    this.muscleGroup,
    this.equipment,
    this.catalogVersion,
  });

  final String id;
  final String name;
  final String? description;
  final String? targetMuscle;
  final String? muscleGroup;
  final String? equipment;
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
        isCustom: _requiredBool(json, 'isCustom'),
        catalogVersion: json['catalogVersion'] as String?,
        version: _requiredInt(json, 'version'),
      );
}

class ApiExerciseCatalogResponse {
  const ApiExerciseCatalogResponse({
    required this.items,
    required this.offset,
    required this.limit,
    required this.total,
  });

  final List<ApiExerciseCatalogItem> items;
  final int offset;
  final int limit;
  final int total;

  factory ApiExerciseCatalogResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    if (rawItems is! List ||
        rawItems.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException('Invalid exercise catalog items.');
    }
    return ApiExerciseCatalogResponse(
      items: rawItems
          .cast<Map<String, dynamic>>()
          .map(ApiExerciseCatalogItem.fromJson)
          .toList(growable: false),
      offset: _requiredInt(json, 'offset'),
      limit: _requiredInt(json, 'limit'),
      total: _requiredInt(json, 'total'),
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
  });

  final String barcode;
  final String productName;
  final String? brand;
  final double basisGrams;
  final double kilocaloriesPer100Grams;
  final double? proteinGramsPer100Grams;
  final double? carbohydrateGramsPer100Grams;
  final double? fatGramsPer100Grams;
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
  });

  final String name;
  final double amountGrams;
  final double kilocalories;
  final double? proteinGrams;
  final double? carbohydrateGrams;
  final double? fatGrams;
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
    this.servingMassGrams,
  });

  final String basis;
  final double? servingMassGrams;
  final ApiNutritionLabelField kilocalories;
  final ApiNutritionLabelField proteinGrams;
  final ApiNutritionLabelField carbohydrateGrams;
  final ApiNutritionLabelField fatGrams;
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
}

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
    required this.workoutCount,
    required this.volumeKgRepetitions,
  });
  final int workoutCount;
  final double volumeKgRepetitions;
  factory ApiTrainingInsights.fromJson(Map<String, dynamic> json) =>
      ApiTrainingInsights(
        workoutCount: _requiredInt(json, 'workoutCount'),
        volumeKgRepetitions: _requiredDouble(json, 'volumeKgRepetitions'),
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
  const ApiLoginRequest({required this.email, required this.password});

  final String email;
  final String password;

  Map<String, Object?> toJson() => {'email': email, 'password': password};
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
  const ApiProblem({this.title, this.detail, this.code});

  final String? title;
  final String? detail;
  final String? code;

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
