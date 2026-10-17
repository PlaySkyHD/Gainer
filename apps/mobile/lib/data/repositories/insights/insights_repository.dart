import '../../models/api/api_models.dart';
import '../../services/api/api_client.dart';
import '../sync/local_sync_store.dart';

class CachedExerciseProgress {
  const CachedExerciseProgress({
    required this.value,
    required this.cachedAtUtc,
  });
  final ApiExerciseProgress value;
  final DateTime cachedAtUtc;
}

class CachedDashboardInsights {
  const CachedDashboardInsights({
    required this.value,
    required this.cachedAtUtc,
  });
  final ApiDashboardInsights value;
  final DateTime cachedAtUtc;
}

class InsightsRepository {
  const InsightsRepository(this.api, {this.store});

  // Die Schlüssel und das Schema sind versioniert, damit v1-Antworten
  // (vor training-volume-v2 / e1rm-epley-v2) nicht gelesen werden.
  static const _exerciseProgressCacheKey = 'local-cache:insights:exercise:v2';
  static const _dashboardCacheKey = 'local-cache:insights:dashboard:v2';
  static const _cacheSchemaVersion = 2;
  static const _volumeAlgorithmVersion = 'training-volume-v2';
  static const _estimatedOneRepMaxAlgorithmVersion = 'e1rm-epley-v2';
  static const _maxExerciseProgressEntries = 64;
  static const _maxDashboardEntries = 8;
  static const _supportedWindows = {'7', '30', '90', 'all'};

  final ApiClient api;
  final LocalSyncStore? store;

  Future<ApiDashboardInsights> loadDashboard({int days = 30}) =>
      api.getDashboardInsights(days: days);

  Future<CachedDashboardInsights?> readCachedDashboard({int days = 30}) async {
    if (days < 1 || days > 365) throw ArgumentError.value(days, 'days');
    final accountStore = store;
    if (accountStore == null) return null;
    final raw = await accountStore.readSyncMetadata(_dashboardCacheKey);
    if (raw is! Map<String, dynamic> ||
        raw['schemaVersion'] != _cacheSchemaVersion ||
        raw['entries'] is! Map<String, dynamic>) {
      return null;
    }
    final entry = (raw['entries'] as Map<String, dynamic>)[days.toString()];
    if (entry is! Map<String, dynamic> ||
        entry['schemaVersion'] != _cacheSchemaVersion ||
        entry['payload'] is! Map<String, dynamic> ||
        entry['cachedAtUtc'] is! String) {
      return null;
    }
    final cachedAt = DateTime.tryParse(entry['cachedAtUtc'] as String)?.toUtc();
    if (cachedAt == null) return null;
    try {
      final value = ApiDashboardInsights.fromJson(
        entry['payload'] as Map<String, dynamic>,
      );
      if (!_matchesTrainingAlgorithms(
        value.training.volumeAlgorithmVersion,
        value.training.estimatedOneRepMaxAlgorithmVersion,
      )) {
        return null;
      }
      return CachedDashboardInsights(value: value, cachedAtUtc: cachedAt);
    } on Object {
      return null;
    }
  }

  Future<void> cacheDashboard({
    int days = 30,
    required ApiDashboardInsights value,
    DateTime? cachedAtUtc,
  }) async {
    if (days < 1 || days > 365) throw ArgumentError.value(days, 'days');
    final payload = value.rawJson;
    final accountStore = store;
    if (accountStore == null || payload == null) return;
    await _writeBoundedEntry(
      accountStore: accountStore,
      cacheKey: _dashboardCacheKey,
      entryKey: days.toString(),
      maximumEntries: _maxDashboardEntries,
      entry: {
        'schemaVersion': _cacheSchemaVersion,
        'cachedAtUtc': (cachedAtUtc ?? DateTime.now())
            .toUtc()
            .toIso8601String(),
        'payload': payload,
      },
    );
  }

  Future<ApiExerciseProgress> loadExerciseProgress({
    required String exerciseId,
    required String window,
    String timeZone = 'Europe/Berlin',
  }) {
    _validateExerciseProgressKey(exerciseId, window);
    return api.getExerciseProgress(
      exerciseId: exerciseId,
      window: window,
      timeZone: timeZone,
    );
  }

  Future<CachedExerciseProgress?> readCachedExerciseProgress({
    required String exerciseId,
    required String window,
  }) async {
    _validateExerciseProgressKey(exerciseId, window);
    final accountStore = store;
    if (accountStore == null) return null;
    final raw = await accountStore.readSyncMetadata(_exerciseProgressCacheKey);
    if (raw is! Map<String, dynamic> ||
        raw['schemaVersion'] != _cacheSchemaVersion ||
        raw['entries'] is! Map<String, dynamic>) {
      return null;
    }
    final entry =
        (raw['entries'] as Map<String, dynamic>)[_entryKey(exerciseId, window)];
    if (entry is! Map<String, dynamic> ||
        entry['schemaVersion'] != _cacheSchemaVersion ||
        entry['payload'] is! Map<String, dynamic> ||
        entry['cachedAtUtc'] is! String) {
      return null;
    }
    final cachedAt = DateTime.tryParse(entry['cachedAtUtc'] as String)?.toUtc();
    if (cachedAt == null) return null;
    try {
      final value = ApiExerciseProgress.fromJson(
        entry['payload'] as Map<String, dynamic>,
      );
      if (value.exerciseId.toLowerCase() != exerciseId.toLowerCase() ||
          !_matchesWindow(value.windowDays, window) ||
          !_matchesTrainingAlgorithms(
            value.volumeAlgorithmVersion,
            value.estimatedOneRepMaxAlgorithmVersion,
          )) {
        return null;
      }
      return CachedExerciseProgress(value: value, cachedAtUtc: cachedAt);
    } on Object {
      return null;
    }
  }

  Future<void> cacheExerciseProgress({
    required String exerciseId,
    required String window,
    required ApiExerciseProgress value,
    DateTime? cachedAtUtc,
  }) async {
    _validateExerciseProgressKey(exerciseId, window);
    if (value.exerciseId.toLowerCase() != exerciseId.toLowerCase() ||
        !_matchesWindow(value.windowDays, window)) {
      throw const FormatException('Exercise progress cache key mismatch.');
    }
    final accountStore = store;
    if (accountStore == null) return;
    await _writeBoundedEntry(
      accountStore: accountStore,
      cacheKey: _exerciseProgressCacheKey,
      entryKey: _entryKey(exerciseId, window),
      maximumEntries: _maxExerciseProgressEntries,
      entry: {
        'schemaVersion': _cacheSchemaVersion,
        'cachedAtUtc': (cachedAtUtc ?? DateTime.now())
            .toUtc()
            .toIso8601String(),
        'payload': value.toJson(),
      },
    );
  }

  Future<void> _writeBoundedEntry({
    required LocalSyncStore accountStore,
    required String cacheKey,
    required String entryKey,
    required int maximumEntries,
    required Map<String, Object?> entry,
  }) async {
    final prior = await accountStore.readSyncMetadata(cacheKey);
    final entries = <String, dynamic>{};
    if (prior is Map<String, dynamic> &&
        prior['schemaVersion'] == _cacheSchemaVersion &&
        prior['entries'] is Map<String, dynamic>) {
      entries.addAll(prior['entries'] as Map<String, dynamic>);
    }
    entries[entryKey] = entry;
    final ordered = entries.entries.toList()
      ..sort(
        (a, b) => _entryTimestamp(b.value).compareTo(_entryTimestamp(a.value)),
      );
    await accountStore.writeSyncMetadata(cacheKey, {
      'schemaVersion': _cacheSchemaVersion,
      'entries': <String, dynamic>{
        for (final item in ordered.take(maximumEntries)) item.key: item.value,
      },
    });
  }

  int _entryTimestamp(Object? value) {
    if (value is! Map<String, dynamic> || value['cachedAtUtc'] is! String) {
      return 0;
    }
    return DateTime.tryParse(value['cachedAtUtc'] as String)
            ?.millisecondsSinceEpoch ??
        0;
  }

  String _entryKey(String exerciseId, String window) =>
      '${exerciseId.toLowerCase()}:$window';

  bool _matchesTrainingAlgorithms(String volumeVersion, String e1rmVersion) =>
      volumeVersion == _volumeAlgorithmVersion &&
      e1rmVersion == _estimatedOneRepMaxAlgorithmVersion;

  bool _matchesWindow(int? windowDays, String window) =>
      window == 'all' ? windowDays == null : windowDays == int.parse(window);

  void _validateExerciseProgressKey(String exerciseId, String window) {
    if (!RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(exerciseId) ||
        !_supportedWindows.contains(window)) {
      throw ArgumentError('Invalid exercise progress cache key.');
    }
  }
}

class CoachRepository {
  const CoachRepository(this.api);
  final ApiClient api;
  Future<ApiCoachResponse> ask(String question) => api.askCoach(question);
}
