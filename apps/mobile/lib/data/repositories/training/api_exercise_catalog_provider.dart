import '../../../domain/models/training/training.dart';
import '../../models/api/api_models.dart';
import '../../services/api/api_client.dart';
import '../sync/local_sync_store.dart';
import 'training_repository.dart';

class ApiExerciseCatalogProvider implements ExerciseCatalogProvider {
  ApiExerciseCatalogProvider(this.api, {this.store});

  static const _cacheKey = 'local-cache:exercise-catalog:v1';
  final ApiClient api;
  final LocalSyncStore? store;

  bool lastLoadWasStale = false;
  DateTime? lastLoadedAtUtc;

  @override
  Future<List<ExerciseCatalogEntry>> loadExercises() async {
    const pageSize = 100;
    final items = <Map<String, dynamic>>[];
    var offset = 0;
    int? total;
    try {
      while (true) {
        final page = await api.getExercises(offset: offset, limit: pageSize);
        if (page.offset != offset || (total != null && total != page.total)) {
          throw const FormatException(
            'Exercise catalog pages changed mid-read.',
          );
        }
        total = page.total;
        items.addAll(page.items.map(_serializeItem));
        offset += page.items.length;
        if (offset >= page.total) break;
        if (page.items.isEmpty) {
          throw const FormatException('Exercise catalog is incomplete.');
        }
      }
      if (items.length != total) {
        throw const FormatException('Exercise catalog is incomplete.');
      }
      final exercises = _toDomain(items);
      lastLoadWasStale = false;
      lastLoadedAtUtc = DateTime.now().toUtc();
      final accountStore = store;
      if (accountStore != null) {
        try {
          await accountStore.writeSyncMetadata(_cacheKey, {
            'schemaVersion': 1,
            'cachedAtUtc': lastLoadedAtUtc!.toIso8601String(),
            'items': items,
          });
        } on Object {
          // The fresh catalog remains usable if local cache writing fails.
        }
      }
      return List.unmodifiable(exercises);
    } on Object {
      final cached = await _readCache();
      if (cached == null) rethrow;
      lastLoadWasStale = true;
      lastLoadedAtUtc = cached.$1;
      return List.unmodifiable(_toDomain(cached.$2));
    }
  }

  Future<(DateTime, List<Map<String, dynamic>>)?> _readCache() async {
    final accountStore = store;
    if (accountStore == null) return null;
    final raw = await accountStore.readSyncMetadata(_cacheKey);
    if (raw is! Map<String, dynamic> ||
        raw['schemaVersion'] != 1 ||
        raw['items'] is! List ||
        raw['items'].any((item) => item is! Map<String, dynamic>)) {
      return null;
    }
    final timestamp = raw['cachedAtUtc'];
    if (timestamp is! String) return null;
    final cachedAt = DateTime.tryParse(timestamp)?.toUtc();
    if (cachedAt == null) return null;
    final items = (raw['items'] as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
    try {
      _toDomain(items);
    } on Object {
      return null;
    }
    return (cachedAt, items);
  }

  List<ExerciseCatalogEntry> _toDomain(List<Map<String, dynamic>> items) =>
      items
          .map((item) {
            final id = item['id'];
            final name = item['name'];
            final version = item['version'];
            if (id is! String ||
                !RegExp(
                  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
                ).hasMatch(id) ||
                name is! String ||
                name.trim().isEmpty ||
                version is! int) {
              throw const FormatException(
                'Invalid cached exercise catalog item.',
              );
            }
            return ExerciseCatalogEntry(
              id: id,
              name: name,
              description: _stringOrNull(item['description']),
              targetMuscle: _stringOrNull(item['targetMuscle']),
              muscleGroup: _stringOrNull(item['muscleGroup']),
              equipment: _stringOrNull(item['equipment']),
              catalogVersion: version,
            );
          })
          .toList(growable: false);

  String? _stringOrNull(Object? value) {
    if (value == null || value is String) return value as String?;
    throw const FormatException('Invalid cached exercise catalog text.');
  }

  Map<String, dynamic> _serializeItem(ApiExerciseCatalogItem item) => {
    'id': item.id,
    'name': item.name,
    'description': item.description,
    'targetMuscle': item.targetMuscle,
    'muscleGroup': item.muscleGroup,
    'equipment': item.equipment,
    'version': item.version,
  };
}
