import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/repositories/training/api_exercise_catalog_provider.dart';
import 'package:gainer_mobile/data/repositories/training/training_log_repository.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/domain/models/training/exercise_catalog_model.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';

const _pushup = CatalogExercise(
  id: 'base-pushup',
  name: 'Liegestütz',
  exerciseType: ExerciseKind.bodyweightOnly,
  bodyweightFactor: 0.64,
  isBase: true,
);

/// Wie der API-Katalog: Laden ginge übers Netz, der Cache ist lokal.
class _CachedCatalog
    implements ExerciseCatalogProvider, CachedExerciseCatalogProvider {
  _CachedCatalog(this.cached);

  final BaseCatalog? cached;
  int networkLoads = 0;

  @override
  bool get lastLoadWasStale => false;

  @override
  Future<BaseCatalog> loadBaseCatalog() async {
    networkLoads++;
    throw StateError('offline');
  }

  @override
  Future<BaseCatalog?> readCachedBaseCatalog() async => cached;
}

class _LocalCatalog implements ExerciseCatalogProvider {
  @override
  bool get lastLoadWasStale => false;

  @override
  Future<BaseCatalog> loadBaseCatalog() async =>
      const BaseCatalog(exercises: [_pushup], categories: []);
}

void main() {
  late LocalDatabase database;

  setUp(() => database = LocalDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  TrainingLogRepository repository(ExerciseCatalogProvider catalog) =>
      TrainingLogRepository(
        store: LocalSyncStore(
          database: database,
          accountId: '00000000-0000-4000-8000-000000000011',
        ),
        catalog: catalog,
        ids: () => '00000000-0000-4000-8000-000000000100',
        clock: () => DateTime.utc(2026, 10, 22, 10),
      );

  test('uses the cached base catalog without a network request', () async {
    final catalog = _CachedCatalog(
      const BaseCatalog(exercises: [_pushup], categories: []),
    );

    final exercises = await repository(catalog).readExercisesOffline();

    expect(exercises.map((e) => e.id), ['base-pushup']);
    expect(exercises.single.bodyweightFactor, 0.64);
    expect(catalog.networkLoads, 0);
  });

  test('without a cache only own exercises remain', () async {
    final catalog = _CachedCatalog(null);

    expect(await repository(catalog).readExercisesOffline(), isEmpty);
    expect(catalog.networkLoads, 0);
  });

  test('a catalog without cache is loaded directly', () async {
    final exercises = await repository(_LocalCatalog()).readExercisesOffline();

    expect(exercises.map((e) => e.id), ['base-pushup']);
  });
}
