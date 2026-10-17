import '../../../domain/models/training/exercise_catalog_model.dart';
import '../../../domain/models/training/workout_model.dart';
import '../../models/api/api_models.dart';
import '../../services/api/api_client.dart';
import '../sync/local_sync_store.dart';

/// Unveränderlicher Basiskatalog. Eigene Übungen und Kategorien kommen aus
/// dem lokalen Konto-Store, nicht aus diesem Katalog.
class BaseCatalog {
  const BaseCatalog({required this.exercises, required this.categories});

  final List<CatalogExercise> exercises;
  final List<CatalogCategory> categories;
}

abstract interface class ExerciseCatalogProvider {
  /// True, wenn der letzte Abruf nicht frisch war und ein Cache-Stand dient.
  bool get lastLoadWasStale;

  Future<BaseCatalog> loadBaseCatalog();
}

class ApiExerciseCatalogProvider implements ExerciseCatalogProvider {
  ApiExerciseCatalogProvider(this.api, {this.store});

  static const _cacheKey = 'local-cache:exercise-catalog:v2';
  final ApiClient api;
  final LocalSyncStore? store;

  @override
  bool lastLoadWasStale = false;
  DateTime? lastLoadedAtUtc;

  @override
  Future<BaseCatalog> loadBaseCatalog() async {
    try {
      final page = await _fetchBase();
      lastLoadWasStale = false;
      lastLoadedAtUtc = DateTime.now().toUtc();
      final accountStore = store;
      if (accountStore != null) {
        try {
          await accountStore.writeSyncMetadata(_cacheKey, {
            'schemaVersion': 2,
            'cachedAtUtc': lastLoadedAtUtc!.toIso8601String(),
            'exercises': [for (final item in page.exercises) item.toJson()],
            'categories': [for (final item in page.categories) item.toJson()],
          });
        } on Object {
          // The fresh catalog remains usable if local cache writing fails.
        }
      }
      return page;
    } on Object {
      final cached = await _readCache();
      if (cached == null) rethrow;
      lastLoadWasStale = true;
      lastLoadedAtUtc = cached.$1;
      return cached.$2;
    }
  }

  /// Liest alle Seiten und übernimmt nur Basiseinträge; eigene Übungen des
  /// Kontos liefert der Store.
  Future<BaseCatalog> _fetchBase() async {
    const pageSize = 100;
    final items = <ApiExerciseCatalogItem>[];
    var categories = const <ApiExerciseCategory>[];
    var offset = 0;
    int? total;
    while (true) {
      final page = await api.getExercises(offset: offset, limit: pageSize);
      if (page.offset != offset || (total != null && total != page.total)) {
        throw const FormatException('Exercise catalog pages changed mid-read.');
      }
      total = page.total;
      if (offset == 0) categories = page.categories;
      items.addAll(page.items);
      offset += page.items.length;
      if (offset >= page.total) break;
      if (page.items.isEmpty) {
        throw const FormatException('Exercise catalog is incomplete.');
      }
    }
    if (items.length != total) {
      throw const FormatException('Exercise catalog is incomplete.');
    }
    return _toDomain(items, categories);
  }

  Future<(DateTime, BaseCatalog)?> _readCache() async {
    final accountStore = store;
    if (accountStore == null) return null;
    final raw = await accountStore.readSyncMetadata(_cacheKey);
    if (raw is! Map<String, dynamic> ||
        raw['schemaVersion'] != 2 ||
        raw['exercises'] is! List ||
        raw['categories'] is! List) {
      return null;
    }
    final timestamp = raw['cachedAtUtc'];
    if (timestamp is! String) return null;
    final cachedAt = DateTime.tryParse(timestamp)?.toUtc();
    if (cachedAt == null) return null;
    try {
      final catalog = BaseCatalog(
        exercises: [
          for (final item in raw['exercises'] as List)
            CatalogExercise.fromJson(Map<String, dynamic>.from(item as Map)),
        ],
        categories: [
          for (final item in raw['categories'] as List)
            CatalogCategory.fromJson(Map<String, dynamic>.from(item as Map)),
        ],
      );
      return (cachedAt, catalog);
    } on Object {
      return null;
    }
  }

  BaseCatalog _toDomain(
    List<ApiExerciseCatalogItem> items,
    List<ApiExerciseCategory> categories,
  ) {
    return BaseCatalog(
      exercises: [
        for (final item in items)
          if (!item.isCustom)
            CatalogExercise(
              id: item.id,
              name: item.name,
              exerciseType: ExerciseKind.fromWireValue(item.exerciseType),
              description: item.description,
              targetMuscle: item.targetMuscle,
              muscleGroup: item.muscleGroup,
              equipment: item.equipment,
              notes: item.notes,
              bodyweightFactor: item.bodyweightFactor,
              weightFactor: item.weightFactor,
              categoryIds: item.categoryIds,
              isBase: true,
            ),
      ],
      categories: [
        for (final category in categories)
          if (category.isBase)
            CatalogCategory(id: category.id, name: category.name, isBase: true),
      ],
    );
  }
}
