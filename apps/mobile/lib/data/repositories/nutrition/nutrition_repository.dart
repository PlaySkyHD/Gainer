import 'dart:math';
import 'dart:typed_data';

import '../../../domain/models/nutrition/nutrition.dart';
import '../../models/local/local_aggregate.dart';
import '../../models/local/local_mutation.dart';
import '../../services/platform/platform_ports.dart';
import '../sync/local_sync_store.dart';

typedef NutritionIdFactory = String Function();

const _nutritionDayType = 'nutrition-day';
const _reusableMealType = 'reusable-meal';
const _nutritionTargetScheduleType = 'nutrition-target-schedule';

abstract interface class NutritionOnlineProvider {
  Future<List<NutritionFood>> searchFoods(String query);
  Future<NutritionFood?> lookupBarcode(String barcode);
  Future<MealEstimateDraft> estimateMeal(String description);
  Future<MealEstimateDraft> estimateMealImage({
    required Uint8List image,
    required String mimeType,
  });
  Future<NutritionLabelScanDraft> scanLabel({
    required Uint8List image,
    required String mimeType,
  });
}

class NutritionFood {
  const NutritionFood({
    required this.name,
    required this.brand,
    required this.per100Grams,
    required this.source,
  });
  final String name;
  final String? brand;
  final NutritionTotals per100Grams;
  final NutritionSource source;
}

class MealEstimateDraft {
  const MealEstimateDraft({
    required this.components,
    required this.provider,
    required this.schemaVersion,
    required this.estimatedAtUtc,
  });
  final List<NutritionEstimateComponent> components;
  final String provider;
  final String schemaVersion;
  final DateTime estimatedAtUtc;
}

class NutritionEstimateComponent {
  const NutritionEstimateComponent({
    required this.name,
    required this.amountGrams,
    required this.totals,
    required this.confidence,
    required this.dataGaps,
  });
  final String name;
  final double amountGrams;
  final NutritionTotals totals;
  final String confidence;
  final List<String> dataGaps;
}

class NutritionLabelFieldDraft {
  const NutritionLabelFieldDraft({
    required this.originalValue,
    required this.per100Grams,
    required this.status,
    required this.evidence,
  });
  final double? originalValue;
  final double? per100Grams;
  final String status;
  final String? evidence;
}

class NutritionLabelScanDraft {
  const NutritionLabelScanDraft({
    required this.basis,
    required this.servingMassGrams,
    required this.kilocalories,
    required this.proteinGrams,
    required this.carbohydrateGrams,
    required this.fatGrams,
    required this.canConfirm,
    required this.provider,
    required this.providerModelVersion,
    required this.parserVersion,
    required this.scannedAtUtc,
  });
  final String basis;
  final double? servingMassGrams;
  final NutritionLabelFieldDraft kilocalories;
  final NutritionLabelFieldDraft proteinGrams;
  final NutritionLabelFieldDraft carbohydrateGrams;
  final NutritionLabelFieldDraft fatGrams;
  final bool canConfirm;
  final String provider;
  final String providerModelVersion;
  final String parserVersion;
  final DateTime scannedAtUtc;

  NutritionTotals? get confirmedPer100Grams {
    final kcal = kilocalories.per100Grams;
    if (!canConfirm || kcal == null || !kcal.isFinite || kcal <= 0) return null;
    return NutritionTotals(
      kilocalories: kcal,
      proteinGrams: proteinGrams.per100Grams,
      carbohydrateGrams: carbohydrateGrams.per100Grams,
      fatGrams: fatGrams.per100Grams,
    );
  }
}

/// A capture stays in memory and is deliberately not serializable into local resources or outbox.
class NutritionImageReview {
  NutritionImageReview({
    required Uint8List bytes,
    required this.mimeType,
    required this.capturedAtUtc,
  }) : bytes = Uint8List.fromList(bytes) {
    if (bytes.isEmpty ||
        bytes.length > 8 * 1024 * 1024 ||
        !{'image/jpeg', 'image/png'}.contains(mimeType)) {
      throw const FormatException(
        'Das Bild muss ein unterstütztes JPEG/PNG mit höchstens 8 MiB sein.',
      );
    }
  }
  final Uint8List bytes;
  final String mimeType;
  final DateTime capturedAtUtc;
  void clear() => bytes.fillRange(0, bytes.length, 0);
}

class NutritionSnapshot {
  const NutritionSnapshot({
    required this.day,
    required this.meals,
    required this.targetSchedule,
    required this.recentFoods,
  });
  final NutritionDay day;
  final List<({String id, ReusableMeal value})> meals;
  final NutritionTargetSchedule? targetSchedule;
  final List<NutritionFood> recentFoods;
}

/// Local-first diary, reusable meals and target phases over the account-bound SQLite outbox.
class NutritionRepository {
  NutritionRepository({
    required this.store,
    this.online,
    this.capture,
    NutritionIdFactory? ids,
    DateTime Function()? clock,
  }) : ids = ids ?? _newUuidV4,
       clock = clock ?? DateTime.now;

  final LocalSyncStore store;
  final NutritionOnlineProvider? online;
  final CapturePlatform? capture;
  final NutritionIdFactory ids;
  final DateTime Function() clock;

  Future<NutritionSnapshot> read(String localDate) async {
    if (!isValidLocalDate(localDate)) {
      throw const NutritionValidationException({
        'localDate': 'Ungültiger Kalendertag.',
      });
    }
    final dayRow = (await store.readAggregates(_nutritionDayType))
        .where((row) => _map(row.workingCopy)['localDate'] == localDate)
        .firstOrNull;
    final day = dayRow == null
        ? NutritionDay(localDate: localDate, entries: const [])
        : NutritionDay.fromJson(_map(dayRow.workingCopy));
    final mealRows = await store.readAggregates(_reusableMealType);
    final meals =
        [
          for (final row in mealRows)
            (
              id: row.aggregateId,
              value: ReusableMeal.fromJson(_map(row.workingCopy)),
            ),
        ]..sort(
          (a, b) =>
              a.value.name.toLowerCase().compareTo(b.value.name.toLowerCase()),
        );
    final scheduleRows = await store.readAggregates(
      _nutritionTargetScheduleType,
    );
    final schedule = scheduleRows.isEmpty
        ? null
        : NutritionTargetSchedule(
            versions: _list(_map(scheduleRows.first.workingCopy)['versions'])
                .map(_targetFromJson)
                .toList(),
          );
    return NutritionSnapshot(
      day: day,
      meals: List.unmodifiable(meals),
      targetSchedule: schedule,
      recentFoods: await recentFoods(),
    );
  }

  Future<List<NutritionFood>> recentFoods({int limit = 20}) async {
    if (limit < 1 || limit > 50) throw RangeError.range(limit, 1, 50, 'limit');
    final rows = await store.readAggregates(_nutritionDayType);
    final candidates = <({NutritionFood food, String stamp})>[];
    for (final row in rows) {
      final body = _map(row.workingCopy);
      final entries = _list(body['entries']).map(NutritionEntry.fromJson);
      final stamp = (body['updatedAtUtc'] as String?) ?? '';
      for (final entry in entries) {
        if (entry.source == null) continue;
        candidates.add((
          food: NutritionFood(
            name: entry.productName,
            brand: entry.brand,
            per100Grams: entry.per100Grams,
            source: entry.source!,
          ),
          stamp: stamp,
        ));
      }
    }
    candidates.sort((a, b) => b.stamp.compareTo(a.stamp));
    final seen = <String>{};
    final result = <NutritionFood>[];
    for (final item in candidates) {
      final key =
          '${item.food.name.toLowerCase()}|${item.food.brand?.toLowerCase() ?? ''}|${item.food.source.barcode ?? ''}';
      if (seen.add(key)) result.add(item.food);
      if (result.length == limit) break;
    }
    return List.unmodifiable(result);
  }

  Future<void> saveEntry(String localDate, NutritionEntry entry) async {
    final current = await read(localDate);
    await saveDay(current.day.replace(entry));
  }

  Future<void> removeEntry(String localDate, String entryId) async {
    final current = await read(localDate);
    if (!current.day.entries.any((entry) => entry.entryId == entryId)) return;
    await saveDay(current.day.remove(entryId));
  }

  Future<void> moveEntry(
    String localDate,
    String entryId,
    NutritionMeal meal,
    int position,
  ) async {
    final current = await read(localDate);
    await saveDay(current.day.move(entryId, meal, position));
  }

  Future<void> saveDay(NutritionDay day) async {
    final existing = (await store.readAggregates(_nutritionDayType))
        .where((row) => _map(row.workingCopy)['localDate'] == day.localDate)
        .firstOrNull;
    final aggregateId = existing?.aggregateId ?? ids();
    final now = clock().toUtc();
    final body = {
      ...day.toJson(),
      'updatedAtUtc': now.toIso8601String(),
      if (existing == null) 'createdAtUtc': now.toIso8601String(),
    };
    await store.commitMutation(
      mutationId: ids(),
      aggregateType: _nutritionDayType,
      aggregateId: aggregateId,
      operation: existing == null
          ? LocalMutationOperation.create
          : LocalMutationOperation.update,
      baseVersion: existing?.serverVersion,
      body: body,
      envelope: existing == null
          ? localEnvelope(aggregateId: aggregateId, workingCopy: body)
          : _pending(existing, body),
      createdAtUtc: now,
    );
  }

  Future<String> saveReusableMeal(ReusableMeal input, {String? id}) async {
    final existing = id == null
        ? null
        : await store.readAggregate(_reusableMealType, id);
    if (existing != null &&
        _map(existing.workingCopy)['status'] == 'Archived') {
      throw StateError('Archivierte Gerichte sind schreibgeschützt.');
    }
    final mealId = id ?? ids();
    final now = clock().toUtc().toIso8601String();
    final value = ReusableMeal(
      name: input.name,
      description: input.description,
      standardPortion: input.standardPortion,
      components: input.components,
      status: 'Active',
      createdAtUtc: existing == null
          ? now
          : _map(existing.workingCopy)['createdAtUtc'] as String?,
      updatedAtUtc: now,
    ).toJson();
    await _commitResource(
      type: _reusableMealType,
      id: mealId,
      value: value,
      existing: existing,
      operation: existing == null
          ? LocalMutationOperation.create
          : LocalMutationOperation.update,
    );
    return mealId;
  }

  Future<void> archiveReusableMeal(String id) async {
    final existing = await _required(_reusableMealType, id);
    final meal = ReusableMeal.fromJson(_map(existing.workingCopy));
    if (meal.status == 'Archived') return;
    final value = {
      ...meal.archived().toJson(),
      'updatedAtUtc': clock().toUtc().toIso8601String(),
    };
    await _commitResource(
      type: _reusableMealType,
      id: id,
      value: value,
      existing: existing,
      operation: LocalMutationOperation.update,
    );
  }

  Future<String> duplicateReusableMeal(
    String id, {
    required String name,
  }) async {
    final source = ReusableMeal.fromJson(
      _map((await _required(_reusableMealType, id)).workingCopy),
    );
    if (name.trim().isEmpty) {
      throw const NutritionValidationException({'name': 'Name erforderlich.'});
    }
    return saveReusableMeal(
      ReusableMeal(
        name: name,
        description: source.description,
        standardPortion: source.standardPortion,
        components: [
          for (var index = 0; index < source.components.length; index++)
            ReusableMealComponent(
              componentId: ids(),
              position: index,
              name: source.components[index].name,
              brand: source.components[index].brand,
              amountGrams: source.components[index].amountGrams,
              per100Grams: source.components[index].per100Grams,
              source: source.components[index].source,
            ),
        ],
      ),
    );
  }

  Future<String> createReusableMealFromDay({
    required String localDate,
    required NutritionMeal meal,
    required String name,
    String? description,
    double standardPortion = 1,
  }) async {
    final day = (await read(localDate)).day;
    final entries = day.entries.where((entry) => entry.meal == meal).toList();
    if (entries.isEmpty) {
      throw StateError('Die ausgewählte Mahlzeit enthält keine Einträge.');
    }
    return saveReusableMeal(
      ReusableMeal(
        name: name,
        description: description,
        standardPortion: standardPortion,
        components: [
          for (var index = 0; index < entries.length; index++)
            ReusableMealComponent(
              componentId: ids(),
              position: index,
              name: entries[index].productName,
              brand: entries[index].brand,
              amountGrams: entries[index].amountGrams,
              per100Grams: entries[index].per100Grams,
              source: entries[index].source,
            ),
        ],
      ),
    );
  }

  Future<void> copyReusableMealToDay({
    required String mealId,
    required String localDate,
    required NutritionMeal meal,
    double? portionScale,
  }) async {
    final row = await _required(_reusableMealType, mealId);
    final reusable = ReusableMeal.fromJson(_map(row.workingCopy));
    if (reusable.status != 'Active') {
      throw StateError('Archivierte Gerichte können nicht übernommen werden.');
    }
    final scale = portionScale ?? reusable.standardPortion;
    if (!scale.isFinite || scale < .01 || scale > 100) {
      throw const NutritionValidationException({
        'portionScale': 'Portion muss zwischen 0,01 und 100 liegen.',
      });
    }
    final snapshot = await read(localDate);
    final entries = [...snapshot.day.entries];
    var position =
        entries
            .where((item) => item.meal == meal)
            .fold<int>(
              0,
              (max, item) => max > item.position ? max : item.position,
            ) +
        1;
    for (final component in reusable.components) {
      entries.add(
        NutritionEntry(
          entryId: ids(),
          meal: meal,
          position: position++,
          productName: component.name,
          brand: component.brand,
          amountGrams: roundNutrition(component.amountGrams * scale),
          per100Grams: component.per100Grams,
          source: component.source,
        ),
      );
    }
    await saveDay(NutritionDay(localDate: localDate, entries: entries));
  }

  Future<void> saveTargetSchedule(NutritionTargetSchedule schedule) async {
    final rows = await store.readAggregates(_nutritionTargetScheduleType);
    final existing = rows.isEmpty ? null : rows.first;
    final id = existing?.aggregateId ?? ids();
    final now = clock().toUtc().toIso8601String();
    final body = {
      ...schedule.toJson(),
      'updatedAtUtc': now,
      if (existing == null) 'createdAtUtc': now,
    };
    await _commitResource(
      type: _nutritionTargetScheduleType,
      id: id,
      value: body,
      existing: existing,
      operation: existing == null
          ? LocalMutationOperation.create
          : LocalMutationOperation.update,
    );
  }

  Future<void> addTargetPhase(
    NutritionTargetVersion phase, {
    required bool closeOpenPreviousPhase,
  }) async {
    final current = await _readTargetSchedule();
    final versions = [...?current?.versions];
    final open = versions.where((item) => item.effectiveUntil == null).toList();
    if (open.isNotEmpty) {
      final prior = open.single;
      if (!closeOpenPreviousPhase) {
        throw StateError(
          'Die offene Zielphase muss vor der neuen Phase beendet werden.',
        );
      }
      final previousDay = _dateBefore(phase.effectiveFrom);
      if (previousDay.compareTo(prior.effectiveFrom) < 0) {
        throw const NutritionValidationException({
          'effectiveFrom':
              'Neue Phase muss nach Beginn der offenen Phase liegen.',
        });
      }
      versions[versions.indexOf(prior)] = _withEndDate(prior, previousDay);
    }
    versions.add(phase);
    await saveTargetSchedule(NutritionTargetSchedule(versions: versions));
  }

  Future<void> updateTargetPhase(NutritionTargetVersion updated) async {
    final current = await _readTargetSchedule();
    if (current == null) throw StateError('Es gibt keinen Zielplan.');
    final index = current.versions.indexWhere(
      (item) => item.targetVersionId == updated.targetVersionId,
    );
    if (index < 0) throw StateError('Die Zielphase ist nicht verfügbar.');
    if (current.versions[index].effectiveFrom.compareTo(_dateString(clock())) <=
        0) {
      throw StateError(
        'Eine bereits begonnene Zielphase ist schreibgeschützt.',
      );
    }
    final versions = [...current.versions]..[index] = updated;
    await saveTargetSchedule(NutritionTargetSchedule(versions: versions));
  }

  Future<void> removeTargetPhase(String targetVersionId) async {
    final current = await _readTargetSchedule();
    if (current == null) return;
    final target = current.versions
        .where((item) => item.targetVersionId == targetVersionId)
        .firstOrNull;
    if (target == null) return;
    if (target.effectiveFrom.compareTo(_dateString(clock())) <= 0) {
      throw StateError(
        'Eine bereits begonnene Zielphase ist schreibgeschützt.',
      );
    }
    if (current.versions.length == 1) {
      throw StateError(
        'Der letzte Zielplan kann nicht ohne Server-Löschvertrag entfernt werden.',
      );
    }
    await saveTargetSchedule(
      NutritionTargetSchedule(
        versions: current.versions
            .where((item) => item.targetVersionId != targetVersionId)
            .toList(),
      ),
    );
  }

  Future<NutritionTargetSchedule?> _readTargetSchedule() async {
    final rows = await store.readAggregates(_nutritionTargetScheduleType);
    if (rows.isEmpty) return null;
    return NutritionTargetSchedule(
      versions: _list(_map(rows.first.workingCopy)['versions'])
          .map(_targetFromJson)
          .toList(),
    );
  }

  Future<List<NutritionFood>> searchFoods(String query) async {
    final normalized = query.trim();
    if (normalized.length < 2 || normalized.length > 120) {
      throw const NutritionValidationException({
        'query': 'Mindestens 2 und höchstens 120 Zeichen eingeben.',
      });
    }
    final provider = online;
    if (provider == null) {
      throw StateError('Food-Suche erfordert eine aktive Onlineverbindung.');
    }
    return List.unmodifiable(await provider.searchFoods(normalized));
  }

  Future<NutritionFood?> lookupBarcode(String barcode) async {
    final normalized = barcode.trim();
    if (!RegExp(r'^\d{8,14}$').hasMatch(normalized)) {
      throw const NutritionValidationException({
        'barcode': 'Ungültiger Barcode.',
      });
    }
    final provider = online;
    if (provider == null) {
      throw StateError('Barcode-Suche erfordert eine aktive Onlineverbindung.');
    }
    return provider.lookupBarcode(normalized);
  }

  Future<MealEstimateDraft> estimateMeal(String description) async {
    final normalized = description.trim();
    if (normalized.isEmpty || normalized.length > 1000) {
      throw const NutritionValidationException({
        'description': 'Beschreibung ist erforderlich (maximal 1000 Zeichen).',
      });
    }
    final provider = online;
    if (provider == null) {
      throw StateError(
        'Die Mahlzeitenschätzung erfordert eine aktive Onlineverbindung.',
      );
    }
    return provider.estimateMeal(normalized);
  }

  Future<String?> scanBarcode() async =>
      capture?.scanBarcode() ??
      Future<String?>.error(
        StateError('Barcode-Scanner ist auf dieser Plattform nicht verfügbar.'),
      );

  Future<NutritionImageReview?> captureLabelImage({
    required bool photoConsentConfirmed,
    required bool useCamera,
  }) async {
    if (!photoConsentConfirmed) {
      throw StateError(
        'Vor der Fotoaufnahme ist eine ausdrückliche Zustimmung erforderlich.',
      );
    }
    final platform = capture;
    if (platform == null) {
      throw StateError(
        'Kamera und Fotomediathek sind auf dieser Plattform nicht verfügbar.',
      );
    }
    final image = useCamera
        ? await platform.capturePhoto()
        : await platform.chooseImage();
    if (image == null) return null;
    return NutritionImageReview(
      bytes: image.bytes,
      mimeType: image.mimeType,
      capturedAtUtc: clock().toUtc(),
    );
  }

  Future<NutritionLabelScanDraft> scanCapturedLabel({
    required NutritionImageReview review,
    required bool uploadConsentConfirmed,
  }) async {
    if (!uploadConsentConfirmed) {
      throw StateError(
        'Vor dem Upload ist die ausdrückliche Zustimmung erforderlich.',
      );
    }
    final provider = online;
    if (provider == null) {
      throw StateError('Der Labelscan erfordert eine aktive Onlineverbindung.');
    }
    final uploadBytes = Uint8List.fromList(review.bytes);
    try {
      return await provider.scanLabel(
        image: uploadBytes,
        mimeType: review.mimeType,
      );
    } finally {
      uploadBytes.fillRange(0, uploadBytes.length, 0);
      review.clear();
    }
  }

  Future<MealEstimateDraft> estimateCapturedMeal({
    required NutritionImageReview review,
    required bool uploadConsentConfirmed,
  }) async {
    if (!uploadConsentConfirmed) {
      throw StateError(
        'Vor dem Upload ist die ausdrückliche Zustimmung erforderlich.',
      );
    }
    final provider = online;
    if (provider == null) {
      review.clear();
      throw StateError(
        'Die Mahlzeitenschätzung erfordert eine aktive Onlineverbindung.',
      );
    }
    final uploadBytes = Uint8List.fromList(review.bytes);
    try {
      return await provider.estimateMealImage(
        image: uploadBytes,
        mimeType: review.mimeType,
      );
    } finally {
      uploadBytes.fillRange(0, uploadBytes.length, 0);
      review.clear();
    }
  }

  Future<void> _commitResource({
    required String type,
    required String id,
    required Map<String, Object?> value,
    required LocalAggregateEnvelope<Object?>? existing,
    required LocalMutationOperation operation,
  }) async {
    final now = clock().toUtc();
    await store.commitMutation(
      mutationId: ids(),
      aggregateType: type,
      aggregateId: id,
      operation: operation,
      baseVersion: existing?.serverVersion,
      body: value,
      envelope: existing == null
          ? localEnvelope(aggregateId: id, workingCopy: value)
          : _pending(existing, value),
      createdAtUtc: now,
    );
  }

  Future<LocalAggregateEnvelope<Object?>> _required(
    String type,
    String id,
  ) async =>
      await store.readAggregate(type, id) ??
      (throw StateError('Die lokale Ressource ist nicht verfügbar.'));
}

LocalAggregateEnvelope<Object?> _pending(
  LocalAggregateEnvelope<Object?> prior,
  Object? value,
) => LocalAggregateEnvelope(
  aggregateId: prior.aggregateId,
  serverSnapshot: prior.serverSnapshot,
  workingCopy: value,
  serverVersion: prior.serverVersion,
  optimisticVersion: prior.optimisticVersion + 1,
  syncState: LocalSyncState.pending,
);
Map<String, dynamic> _map(Object? value) => value is Map<String, dynamic>
    ? value
    : throw const FormatException('Expected nutrition object.');
List<Map<String, dynamic>> _list(Object? value) =>
    value is List && value.every((item) => item is Map<String, dynamic>)
    ? value.cast<Map<String, dynamic>>()
    : throw const FormatException('Expected nutrition list.');
NutritionTargetVersion _targetFromJson(Map<String, dynamic> json) =>
    NutritionTargetVersion(
      targetVersionId: json['targetVersionId'] as String,
      name: json['name'] as String,
      category: NutritionTargetCategory.values.firstWhere(
        (e) =>
            e.name.toLowerCase() == (json['category'] as String).toLowerCase(),
      ),
      effectiveFrom: json['effectiveFrom'] as String,
      effectiveUntil: json['effectiveUntil'] as String?,
      inputMode: NutritionTargetInputMode.values.firstWhere(
        (e) =>
            e.name.toLowerCase() == (json['inputMode'] as String).toLowerCase(),
      ),
      kilocalories: (json['kilocalories'] as num).toDouble(),
      proteinGrams: (json['proteinGrams'] as num).toDouble(),
      carbohydrateGrams: (json['carbohydrateGrams'] as num).toDouble(),
      fatGrams: (json['fatGrams'] as num).toDouble(),
      proteinPercent: (json['proteinPercent'] as num?)?.toDouble(),
      carbohydratePercent: (json['carbohydratePercent'] as num?)?.toDouble(),
      fatPercent: (json['fatPercent'] as num?)?.toDouble(),
      origin: json['origin'] as String? ?? 'Manual',
      algorithmVersion: json['algorithmVersion'] as String?,
      reason: json['reason'] as String?,
    );

String _dateString(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String _dateBefore(String localDate) {
  final date = DateTime.parse(localDate).subtract(const Duration(days: 1));
  return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

NutritionTargetVersion _withEndDate(NutritionTargetVersion value, String end) =>
    NutritionTargetVersion(
      targetVersionId: value.targetVersionId,
      name: value.name,
      category: value.category,
      effectiveFrom: value.effectiveFrom,
      effectiveUntil: end,
      inputMode: value.inputMode,
      kilocalories: value.kilocalories,
      proteinGrams: value.proteinGrams,
      carbohydrateGrams: value.carbohydrateGrams,
      fatGrams: value.fatGrams,
      proteinPercent: value.proteinPercent,
      carbohydratePercent: value.carbohydratePercent,
      fatPercent: value.fatPercent,
      origin: value.origin,
      algorithmVersion: value.algorithmVersion,
      reason: value.reason,
    );

String _newUuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
