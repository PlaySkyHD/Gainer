import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/api/api_models.dart';
import 'package:gainer_mobile/data/repositories/insights/insights_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/repositories/training/api_exercise_catalog_provider.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:path/path.dart' as p;

const _categoryA = '00000000-0000-4000-8000-000000000301';
const _accountA = 'a1234567-1234-4234-8234-123456789abc';
const _accountB = 'b1234567-1234-4234-8234-123456789abc';
const _exerciseA = '00000000-0000-4000-8000-000000000001';

void main() {
  late Directory directory;
  final databases = <LocalDatabase>[];
  final clients = <ApiClient>[];
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('gainer-insights-');
    databases.clear();
    clients.clear();
  });
  tearDown(() async {
    for (final client in clients) {
      client.close();
    }
    for (final database in databases) {
      await database.close();
    }
    final tempRoot = await Directory.systemTemp.resolveSymbolicLinks();
    final resolvedDirectory = await directory.resolveSymbolicLinks();
    if (!p.isWithin(tempRoot, resolvedDirectory) ||
        !p.basename(resolvedDirectory).startsWith('gainer-insights-')) {
      throw StateError(
        'Refusing to remove an unowned insights test directory.',
      );
    }
    await Directory(resolvedDirectory).delete(recursive: true);
  });
  Future<void> closeDatabase(LocalDatabase database) async {
    databases.remove(database);
    await database.close();
  }

  LocalDatabase open(String name) {
    final database = LocalDatabase(
      NativeDatabase(File('${directory.path}/$name.sqlite')),
    );
    databases.add(database);
    return database;
  }

  ApiClient unusedApi() {
    final client = ApiClient(
      configuration: ApiConfiguration(
        apiOrigin: Uri.parse('http://127.0.0.1:5099'),
        trustedFrontendOrigin: Uri.parse('http://127.0.0.1:5099'),
        allowInsecureLoopbackForDevelopment: true,
      ),
    );
    clients.add(client);
    return client;
  }

  test(
    'exercise analytics cache survives reopen and stays account scoped',
    () async {
      final firstDb = open('account-a');
      final firstRepository = InsightsRepository(
        unusedApi(),
        store: LocalSyncStore(database: firstDb, accountId: _accountA),
      );
      await firstRepository.cacheExerciseProgress(
        exerciseId: _exerciseA,
        window: '30',
        value: _progress(_exerciseA, 30),
        cachedAtUtc: DateTime.utc(2026, 10, 14),
      );
      await closeDatabase(firstDb);
      final reopenedDb = open('account-a');
      final reopened = InsightsRepository(
        unusedApi(),
        store: LocalSyncStore(database: reopenedDb, accountId: _accountA),
      );
      final cached = await reopened.readCachedExerciseProgress(
        exerciseId: _exerciseA,
        window: '30',
      );
      expect(cached?.value.points.single.estimatedOneRepMaxKg, 82.5);
      expect(cached?.cachedAtUtc, DateTime.utc(2026, 10, 14));
      final otherDb = open('account-b');
      final other = InsightsRepository(
        unusedApi(),
        store: LocalSyncStore(database: otherDb, accountId: _accountB),
      );
      expect(
        await other.readCachedExerciseProgress(
          exerciseId: _exerciseA,
          window: '30',
        ),
        isNull,
      );
      await closeDatabase(reopenedDb);
      await closeDatabase(otherDb);
    },
  );

  test(
    'exercise analytics cache retains at most 64 selection windows',
    () async {
      final database = open('bounded');
      final repository = InsightsRepository(
        unusedApi(),
        store: LocalSyncStore(database: database, accountId: _accountA),
      );
      for (var index = 1; index <= 65; index++) {
        final id =
            '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}';
        await repository.cacheExerciseProgress(
          exerciseId: id,
          window: '7',
          value: _progress(id, 7),
          cachedAtUtc: DateTime.utc(2026, 10, 1).add(Duration(minutes: index)),
        );
      }
      expect(
        await repository.readCachedExerciseProgress(
          exerciseId: '00000000-0000-4000-8000-000000000001',
          window: '7',
        ),
        isNull,
      );
      expect(
        await repository.readCachedExerciseProgress(
          exerciseId: '00000000-0000-4000-8000-000000000065',
          window: '7',
        ),
        isNotNull,
      );
      await closeDatabase(database);
    },
  );

  test(
    'catalog provider falls back to complete account cache after offline error',
    () async {
      final database = open('catalog');
      final store = LocalSyncStore(database: database, accountId: _accountA);
      final api = _CatalogApi();
      clients.add(api);
      final provider = ApiExerciseCatalogProvider(api, store: store);
      expect((await provider.loadBaseCatalog()).exercises.single.name, 'Squat');
      expect(provider.lastLoadWasStale, isFalse);
      api.fail = true;
      final offline = ApiExerciseCatalogProvider(api, store: store);
      final cached = await offline.loadBaseCatalog();
      expect(cached.exercises.single.id, _exerciseA);
      expect(cached.categories.single.name, 'Beine');
      expect(offline.lastLoadWasStale, isTrue);
      expect(offline.lastLoadedAtUtc, isNotNull);
      await closeDatabase(database);
    },
  );

  test(
    'exercise analytics cache ignores v1 entries and older algorithm versions',
    () async {
      final database = open('versioned');
      final store = LocalSyncStore(database: database, accountId: _accountA);
      final repository = InsightsRepository(unusedApi(), store: store);
      await store.writeSyncMetadata('local-cache:insights:exercise:v1', {
        'schemaVersion': 1,
        'entries': {
          '$_exerciseA:30': {
            'schemaVersion': 1,
            'cachedAtUtc': DateTime.utc(2026, 10, 14).toIso8601String(),
            'payload': _progress(_exerciseA, 30).toJson(),
          },
        },
      });
      expect(
        await repository.readCachedExerciseProgress(
          exerciseId: _exerciseA,
          window: '30',
        ),
        isNull,
      );

      final outdated = ApiExerciseProgress(
        asOfRevision: 19,
        exerciseId: _exerciseA,
        windowDays: 30,
        fromUtc: DateTime.utc(2026, 9, 14),
        throughUtc: DateTime.utc(2026, 10, 14),
        volumeAlgorithmVersion: 'training-volume-v1',
        estimatedOneRepMaxAlgorithmVersion: 'e1rm-epley-v1',
        points: const [],
        bestSet: null,
        records: _emptyRecords,
      );
      await repository.cacheExerciseProgress(
        exerciseId: _exerciseA,
        window: '30',
        value: outdated,
      );
      expect(
        await repository.readCachedExerciseProgress(
          exerciseId: _exerciseA,
          window: '30',
        ),
        isNull,
      );
      await closeDatabase(database);
    },
  );
}

ApiExerciseProgress _progress(String exerciseId, int window) =>
    ApiExerciseProgress(
      asOfRevision: 19,
      exerciseId: exerciseId,
      windowDays: window,
      fromUtc: DateTime.utc(2026, 9, 14),
      throughUtc: DateTime.utc(2026, 10, 14),
      volumeAlgorithmVersion: 'training-volume-v2',
      estimatedOneRepMaxAlgorithmVersion: 'e1rm-epley-v2',
      records: _emptyRecords,
      points: [
        ApiExerciseProgressPoint(
          workoutId: '00000000-0000-4000-8000-000000000099',
          completedAtUtc: DateTime.utc(2026, 10, 12),
          volumeKgRepetitions: 825,
          bodyweightMissing: false,
          maxWeightKg: 75,
          maxRepetitions: 5,
          estimatedOneRepMaxKg: 82.5,
        ),
      ],
      bestSet: null,
    );

const _emptyRecords = ApiExerciseRecords(
  maxWeightKg: null,
  estimatedOneRepMaxKg: null,
  volumeKgRepetitions: null,
  maxRepetitions: null,
  repetitionRecords: [],
);

class _CatalogApi extends ApiClient {
  _CatalogApi()
    : super(
        configuration: ApiConfiguration(
          apiOrigin: Uri.parse('http://127.0.0.1:5099'),
          trustedFrontendOrigin: Uri.parse('http://127.0.0.1:5099'),
          allowInsecureLoopbackForDevelopment: true,
        ),
      );
  bool fail = false;
  @override
  Future<ApiExerciseCatalogResponse> getExercises({
    String? search,
    String? targetMuscle,
    String? muscleGroup,
    String? equipment,
    int offset = 0,
    int limit = 100,
  }) async {
    if (fail) {
      throw const ApiException(
        statusCode: null,
        code: 'offline',
        message: 'offline',
      );
    }
    return ApiExerciseCatalogResponse(
      items: const [
        ApiExerciseCatalogItem(
          id: _exerciseA,
          name: 'Squat',
          isCustom: false,
          version: 2,
          exerciseType: 'strength',
          targetMuscle: 'Quadriceps',
          categoryIds: [_categoryA],
        ),
      ],
      offset: offset,
      limit: limit,
      total: 1,
      categories: const [
        ApiExerciseCategory(id: _categoryA, name: 'Beine', isBase: true),
      ],
    );
  }
}
