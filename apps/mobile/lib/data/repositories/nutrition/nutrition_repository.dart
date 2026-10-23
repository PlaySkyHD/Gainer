import 'dart:math';
import 'dart:typed_data';

import '../../../domain/models/nutrition/day_target.dart';
import '../../../domain/models/nutrition/nutrition.dart';
import '../../../domain/models/nutrition/nutrition_averages.dart';
import '../../../domain/models/training/training_schedule.dart';
import '../../models/local/local_aggregate.dart';
import '../../models/local/local_mutation.dart';
import '../../services/platform/platform_ports.dart';
import '../sync/local_sync_store.dart';

typedef NutritionIdFactory = String Function();

const _nutritionDayType = 'nutrition-day';
const _reusableMealType = 'reusable-meal';
const _nutritionTargetScheduleType = 'nutrition-target-schedule';
const _dayTemplateType = 'nutrition-day-template';

/// Liest die Rhythmus-Vorschau aus den lokalen Trainingsdaten.
typedef ScheduleProjectionReader =
    Future<TrainingScheduleProjection> Function();

/// Wie eine Vorlage auf einen Tag mit Einträgen angewendet wird.
enum TemplateApplyMode { replace, append }

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
    this.pieceGrams,
  });
  final String name;
  final String? brand;
  final NutritionTotals per100Grams;
  final NutritionSource source;

  /// Gewicht eines Stücks, z. B. aus der Portionsgröße oder einem früheren
  /// Eintrag; null, wenn nur Gramm sinnvoll sind.
  final double? pieceGrams;
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
    this.sourceUrl,
    this.pieceCount,
    this.pieceGrams,
  });
  final String name;
  final double amountGrams;
  final NutritionTotals totals;
  final String confidence;
  final List<String> dataGaps;
  final String? sourceUrl;

  /// Gezählte Stücke („4 Eier“) mit Gewicht je Stück; sonst null.
  final double? pieceCount;
  final double? pieceGrams;

  /// „fddb.info“ aus der Quelle, ohne „www.“; null ohne Quelle.
  String? get sourceHost {
    final host = Uri.tryParse(sourceUrl ?? '')?.host;
    if (host == null || host.isEmpty) return null;
    return host.startsWith('www.') ? host.substring(4) : host;
  }
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
    this.saltGrams = const NutritionLabelFieldDraft(
      originalValue: null,
      per100Grams: null,
      status: 'Missing',
      evidence: null,
    ),
    this.fiberGrams = const NutritionLabelFieldDraft(
      originalValue: null,
      per100Grams: null,
      status: 'Missing',
      evidence: null,
    ),
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
  final NutritionLabelFieldDraft saltGrams;
  final NutritionLabelFieldDraft fiberGrams;
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
      saltGrams: saltGrams.per100Grams,
      fiberGrams: fiberGrams.per100Grams,
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
    this.dayTarget,
    this.automaticDayKind = NutritionDayKind.rest,
    this.templates = const [],
    this.suggestedTemplate,
  });
  final NutritionDay day;
  final List<({String id, ReusableMeal value})> meals;
  final NutritionTargetSchedule? targetSchedule;
  final List<NutritionFood> recentFoods;

  /// Ziel des Tages nach Tagesart; null ohne Ziele.
  final NutritionDayTargetResult? dayTarget;

  /// Tagesart ohne Festlegung, für „Automatisch (…)“.
  final NutritionDayKind automaticDayKind;

  /// Tagesvorlagen, zuletzt geänderte zuerst.
  final List<NutritionDayTemplate> templates;

  /// Vorlage, die zur Tagesart des leeren Tages passt (nur heute und künftig).
  final NutritionDayTemplate? suggestedTemplate;
}

/// Local-first diary, reusable meals and target phases over the account-bound SQLite outbox.
class NutritionRepository {
  NutritionRepository({
    required this.store,
    this.online,
    this.capture,
    NutritionIdFactory? ids,
    DateTime Function()? clock,
    this.scheduleProjection,
  }) : ids = ids ?? _newUuidV4,
       clock = clock ?? DateTime.now;

  final LocalSyncStore store;

  /// Rhythmus und Trainings für die Tagesart; ohne zählt jeder Tag ohne
  /// Festlegung als Ruhetag.
  final ScheduleProjectionReader? scheduleProjection;
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
    final schedule = await _readTargetSchedule();
    final projection = await readProjection();
    final templates = await readTemplates();
    final automatic = automaticDayKind(LocalDay.parse(localDate), projection);
    final kind = day.dayKind ?? automatic;
    return NutritionSnapshot(
      day: day,
      meals: List.unmodifiable(meals),
      targetSchedule: schedule,
      recentFoods: await recentFoods(),
      dayTarget: dayTarget(
        localDate: localDate,
        targets: schedule,
        manualKind: day.dayKind,
        projection: projection,
      ),
      automaticDayKind: automatic,
      templates: templates,
      suggestedTemplate:
          day.entries.isNotEmpty ||
              localDate.compareTo(_dateString(clock())) < 0
          ? null
          : templates.where((item) => item.dayKind == kind).firstOrNull,
    );
  }

  /// Rhythmus-Vorschau für die Tagesart. Fehlen Trainingsdaten, zählt jeder
  /// Tag ohne Festlegung als Ruhetag, statt das Essen-Tab zu blockieren.
  Future<TrainingScheduleProjection> readProjection() async {
    final reader = scheduleProjection;
    if (reader != null) {
      try {
        return await reader();
      } on Object {
        // Fällt unten auf eine leere Vorschau zurück.
      }
    }
    return TrainingScheduleProjection(
      schedule: null,
      plans: const [],
      workouts: const [],
      today: LocalDay.of(clock()),
    );
  }

  /// Alle lokalen Tage von [from] bis [to] (einschließlich) in einem
  /// Durchlauf, dazu die Zielphasen. Für den Kalender; braucht keine
  /// Verbindung. Tage ohne Eintrag fehlen.
  Future<({List<NutritionDay> days, NutritionTargetSchedule? targets})>
  readDays(String from, String to) async {
    if (!isValidLocalDate(from) || !isValidLocalDate(to)) {
      throw const NutritionValidationException({
        'localDate': 'Ungültiger Kalendertag.',
      });
    }
    return (
      days: await _readDaysBetween(from, to),
      targets: await _readTargetSchedule(),
    );
  }

  /// Durchschnitte der letzten 7 und 30 Tage aus den lokalen Tagen (offline).
  Future<NutritionAveragesOverview> readAverages(String today) async {
    if (!isValidLocalDate(today)) {
      throw const NutritionValidationException({
        'localDate': 'Ungültiger Kalendertag.',
      });
    }
    return NutritionAveragesOverview(
      days: await _readDaysBetween(shiftLocalDate(today, -30), today),
      schedule: await _readTargetSchedule(),
      today: today,
      projection: await readProjection(),
    );
  }

  /// Lokale Tage von [from] bis [to] einschließlich; jede Zeile wird nur
  /// einmal dekodiert.
  Future<List<NutritionDay>> _readDaysBetween(String from, String to) async {
    final days = <NutritionDay>[];
    for (final row in await store.readAggregates(_nutritionDayType)) {
      final body = _map(row.workingCopy);
      final date = body['localDate'];
      if (date is String &&
          date.compareTo(from) >= 0 &&
          date.compareTo(to) <= 0) {
        days.add(NutritionDay.fromJson(body));
      }
    }
    return days;
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
            pieceGrams: entry.pieceGrams,
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
              pieceGrams: source.components[index].pieceGrams,
              pieceCount: source.components[index].pieceCount,
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
              pieceGrams: entries[index].pieceGrams,
              pieceCount: entries[index].pieceCount,
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
      // Stückzahl mit der Portion skalieren; Gramm daraus ableiten, damit
      // beide zusammenpassen.
      final pieceGrams = component.pieceGrams;
      final pieceCount = component.pieceCount == null
          ? null
          : roundNutrition(component.pieceCount! * scale);
      entries.add(
        NutritionEntry(
          entryId: ids(),
          meal: meal,
          position: position++,
          productName: component.name,
          brand: component.brand,
          amountGrams: pieceCount != null && pieceGrams != null
              ? gramsForPieces(pieceCount, pieceGrams)
              : roundNutrition(component.amountGrams * scale),
          per100Grams: component.per100Grams,
          source: component.source,
          pieceGrams: pieceGrams,
          pieceCount: pieceCount,
        ),
      );
    }
    await saveDay(snapshot.day.withEntries(entries));
  }

  /// Legt fest, ob der Tag als Trainings- oder Ruhetag zählt; null hebt die
  /// Festlegung auf. Ein Tag ohne Einträge bleibt mit leerer Liste erhalten.
  Future<void> setDayKind(String localDate, NutritionDayKind? kind) async {
    final current = await read(localDate);
    if (current.day.dayKind == kind) return;
    await saveDay(current.day.withDayKind(kind));
  }

  /// Tagesvorlagen ohne gelöschte, zuletzt geänderte zuerst.
  Future<List<NutritionDayTemplate>> readTemplates() async {
    final templates = <NutritionDayTemplate>[];
    for (final row in await store.readAggregates(_dayTemplateType)) {
      final working = row.workingCopy;
      if (working is! Map<String, dynamic> || working['deletedAtUtc'] != null) {
        continue;
      }
      templates.add(NutritionDayTemplate.fromJson(working));
    }
    templates.sort((a, b) {
      final stamp = (b.updatedAtUtc ?? DateTime(0)).compareTo(
        a.updatedAtUtc ?? DateTime(0),
      );
      return stamp != 0
          ? stamp
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return List.unmodifiable(templates);
  }

  /// Speichert die Einträge des Tages als neue Vorlage oder überschreibt die
  /// Vorlage [overwriteId]; beim Überschreiben bleiben Name und Tagesart.
  Future<String> saveDayAsTemplate(
    String localDate, {
    String? overwriteId,
    String? name,
    NutritionDayKind? dayKind,
  }) async {
    final day = (await read(localDate)).day;
    if (day.entries.isEmpty) {
      throw const NutritionValidationException({
        'entries': 'Ein leerer Tag kann keine Vorlage werden.',
      });
    }
    final entries = [
      for (final entry in day.entries)
        NutritionEntry(
          entryId: ids(),
          meal: entry.meal,
          position: entry.position,
          productName: entry.productName,
          brand: entry.brand,
          amountGrams: entry.amountGrams,
          per100Grams: entry.per100Grams,
          source: entry.source,
          pieceGrams: entry.pieceGrams,
          pieceCount: entry.pieceCount,
        ),
    ];
    final now = clock().toUtc();
    if (overwriteId != null) {
      final existing = await _required(_dayTemplateType, overwriteId);
      final prior = NutritionDayTemplate.fromJson(_map(existing.workingCopy));
      final value = NutritionDayTemplate(
        templateId: overwriteId,
        name: prior.name,
        dayKind: prior.dayKind,
        entries: entries,
        updatedAtUtc: now,
      );
      await _commitResource(
        type: _dayTemplateType,
        id: overwriteId,
        value: value.toJson(),
        existing: existing,
        operation: LocalMutationOperation.update,
      );
      return overwriteId;
    }
    if ((await readTemplates()).length >= NutritionDayTemplate.maxTemplates) {
      throw const NutritionValidationException({
        'templates': 'Es sind höchstens 50 Vorlagen möglich.',
      });
    }
    final id = ids();
    final value = NutritionDayTemplate(
      templateId: id,
      name: name ?? '',
      dayKind: dayKind,
      entries: entries,
      updatedAtUtc: now,
    );
    await _commitResource(
      type: _dayTemplateType,
      id: id,
      value: value.toJson(),
      existing: null,
      operation: LocalMutationOperation.create,
    );
    return id;
  }

  /// Speichert eine bearbeitete Vorlage: Name, Tagesart und Einträge. Die
  /// Positionen werden je Mahlzeit in der übergebenen Reihenfolge neu
  /// vergeben. Tage, auf die die Vorlage angewendet wurde, bleiben unverändert.
  Future<void> updateTemplate(
    String templateId, {
    required String name,
    required NutritionDayKind? dayKind,
    required List<NutritionEntry> entries,
  }) async {
    final existing = await _required(_dayTemplateType, templateId);
    final counters = <NutritionMeal, int>{};
    final value = NutritionDayTemplate(
      templateId: templateId,
      name: name,
      dayKind: dayKind,
      entries: [
        for (final entry in entries)
          entry.copyWith(
            position: counters.update(
              entry.meal,
              (value) => value + 1,
              ifAbsent: () => 0,
            ),
          ),
      ],
      updatedAtUtc: clock().toUtc(),
    );
    await _commitResource(
      type: _dayTemplateType,
      id: templateId,
      value: value.toJson(),
      existing: existing,
      operation: LocalMutationOperation.update,
    );
  }

  /// Löscht die Vorlage lokal sofort; der Server folgt über Sync. Tage, auf
  /// die sie angewendet wurde, behalten ihre Einträge.
  Future<void> deleteTemplate(String templateId) async {
    final existing = await store.readAggregate(_dayTemplateType, templateId);
    final working = existing?.workingCopy;
    if (existing == null ||
        working is! Map<String, dynamic> ||
        working['deletedAtUtc'] != null) {
      return;
    }
    await _commitResource(
      type: _dayTemplateType,
      id: templateId,
      value: {...working, 'deletedAtUtc': clock().toUtc().toIso8601String()},
      existing: existing,
      operation: LocalMutationOperation.delete,
    );
  }

  /// Übernimmt die Einträge der Vorlage als Kopien mit neuen IDs. [mode] ist
  /// nur relevant, wenn der Tag schon Einträge hat. Die Tagesart des Tages
  /// bleibt unverändert.
  Future<void> applyTemplate(
    String templateId,
    String localDate, {
    TemplateApplyMode mode = TemplateApplyMode.append,
  }) async {
    final row = await _required(_dayTemplateType, templateId);
    final template = NutritionDayTemplate.fromJson(_map(row.workingCopy));
    final day = (await read(localDate)).day;
    final kept = mode == TemplateApplyMode.replace
        ? const <NutritionEntry>[]
        : day.entries;
    if (kept.length + template.entries.length > maxEntriesPerDay) {
      throw const NutritionValidationException({
        'entries': 'Ein Tag kann höchstens 200 Einträge haben.',
      });
    }
    final next = <NutritionEntry>[...kept];
    for (final meal in NutritionMeal.values) {
      var position = kept
          .where((item) => item.meal == meal)
          .fold<int>(
            0,
            (max, item) => item.position >= max ? item.position + 1 : max,
          );
      for (final entry in template.entries.where((item) => item.meal == meal)) {
        next.add(
          NutritionEntry(
            entryId: ids(),
            meal: meal,
            position: position++,
            productName: entry.productName,
            brand: entry.brand,
            amountGrams: entry.amountGrams,
            per100Grams: entry.per100Grams,
            source: entry.source,
            pieceGrams: entry.pieceGrams,
            pieceCount: entry.pieceCount,
          ),
        );
      }
    }
    await saveDay(day.withEntries(next));
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

  /// Speichert die Ziele mit Wirkung ab heute (lokaler Tag). Vergangene Tage
  /// behalten ihr Ziel; eine zweite Änderung am selben Tag ersetzt die
  /// Version von heute. Alte, noch nicht begonnene Planungen entfallen.
  Future<void> saveTargets({
    required NutritionDayTarget training,
    required NutritionDayTarget? restDay,
    required double? saltGrams,
    required double? fiberGrams,
  }) async {
    final today = _dateString(clock());
    final current = await _readTargetSchedule();
    final versions = [
      for (final version
          in current?.versions ?? const <NutritionTargetVersion>[])
        if (version.effectiveFrom.compareTo(today) <= 0) version,
    ];
    final active = versions
        .where(
          (item) =>
              item.effectiveUntil == null ||
              item.effectiveUntil!.compareTo(today) >= 0,
        )
        .lastOrNull;
    if (active != null && active.effectiveFrom == today) {
      versions[versions.indexOf(active)] = active.copyWith(
        clearEffectiveUntil: true,
        trainingDay: training,
        saltGrams: saltGrams,
        clearSaltGrams: saltGrams == null,
        fiberGrams: fiberGrams,
        clearFiberGrams: fiberGrams == null,
        restDay: restDay,
        clearRestDay: restDay == null,
      );
    } else {
      if (active != null) {
        versions[versions.indexOf(active)] = active.copyWith(
          effectiveUntil: shiftLocalDate(today, -1),
        );
      }
      versions.add(
        NutritionTargetVersion(
          targetVersionId: ids(),
          name: 'Ziele',
          category: NutritionTargetCategory.custom,
          effectiveFrom: today,
          effectiveUntil: null,
          inputMode: training.inputMode,
          kilocalories: training.kilocalories,
          proteinGrams: training.proteinGrams,
          carbohydrateGrams: training.carbohydrateGrams,
          fatGrams: training.fatGrams,
          proteinPercent: training.proteinPercent,
          carbohydratePercent: training.carbohydratePercent,
          fatPercent: training.fatPercent,
          saltGrams: saltGrams,
          restDay: restDay,
          fiberGrams: fiberGrams,
        ),
      );
    }
    await saveTargetSchedule(NutritionTargetSchedule(versions: versions));
  }

  /// Ziele, die heute gelten; null ohne Ziele.
  Future<NutritionTargetVersion?> currentTargets() async =>
      (await _readTargetSchedule())?.targetOn(_dateString(clock()));

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
      saltGrams: (json['saltGrams'] as num?)?.toDouble(),
      fiberGrams: (json['fiberGrams'] as num?)?.toDouble(),
      restDay: json['restDay'] is Map<String, dynamic>
          ? NutritionDayTarget.fromJson(json['restDay'] as Map<String, dynamic>)
          : null,
    );

String _dateString(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

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
