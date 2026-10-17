import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/local/local_aggregate.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/repositories/training/api_exercise_catalog_provider.dart';
import 'package:gainer_mobile/data/repositories/training/training_log_repository.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/domain/models/training/exercise_catalog_model.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';

import 'training_test_support.dart';

const baseChest = CatalogCategory(
  id: 'base-chest',
  name: 'Brust',
  isBase: true,
);
const baseLegs = CatalogCategory(id: 'base-legs', name: 'Beine', isBase: true);

const baseBench = CatalogExercise(
  id: 'base-bench',
  name: 'Bankdrücken',
  exerciseType: ExerciseKind.strength,
  categoryIds: ['base-chest'],
  isBase: true,
);
const baseSquat = CatalogExercise(
  id: 'base-squat',
  name: 'Kniebeuge',
  exerciseType: ExerciseKind.strength,
  categoryIds: ['base-legs'],
  isBase: true,
);
const baseBulgarian = CatalogExercise(
  id: 'base-bulgarian',
  name: 'Bulgarische Kniebeuge',
  exerciseType: ExerciseKind.strength,
  categoryIds: ['base-legs'],
  isBase: true,
);
const basePushup = CatalogExercise(
  id: 'base-pushup',
  name: 'Liegestütz',
  exerciseType: ExerciseKind.bodyweightOnly,
  bodyweightFactor: 0.64,
  categoryIds: ['base-chest'],
  isBase: true,
);

class _FixedCatalog implements ExerciseCatalogProvider {
  @override
  bool get lastLoadWasStale => false;

  @override
  Future<BaseCatalog> loadBaseCatalog() async => const BaseCatalog(
    exercises: [baseBench, baseSquat, baseBulgarian, basePushup],
    categories: [baseChest, baseLegs],
  );
}

class _Clock {
  DateTime value = DateTime.utc(2026, 10, 17, 9);
}

/// Repository mit festem Basiskatalog und In-Memory-Datenbank.
class CatalogHarness {
  CatalogHarness._(this.database, this.store, this.repository, this._clock);

  final LocalDatabase database;
  final LocalSyncStore store;
  final TrainingLogRepository repository;
  final _Clock _clock;

  set now(DateTime value) => _clock.value = value;

  static Future<CatalogHarness> create() async {
    final database = LocalDatabase(NativeDatabase.memory());
    final store = LocalSyncStore(
      database: database,
      accountId: trainingAccountId,
    );
    final clock = _Clock();
    var id = 500;
    final repository = TrainingLogRepository(
      store: store,
      catalog: _FixedCatalog(),
      ids: () => testId(id++),
      clock: () => clock.value,
    );
    return CatalogHarness._(database, store, repository, clock);
  }

  /// Legt einen Serverstand an. Nötig für Zusammenführungen, die nur auf
  /// synchronisierten Übungen laufen.
  Future<void> seedServer(
    String aggregateType,
    String aggregateId,
    Map<String, Object?> snapshot,
  ) async {
    await store.ensureAccountBound();
    await database
        .into(database.localResources)
        .insertOnConflictUpdate(
          LocalResourcesCompanion.insert(
            aggregateType: aggregateType,
            aggregateId: aggregateId,
            envelopeJson: serverEnvelope(
              aggregateId: aggregateId,
              snapshot: snapshot,
              version: 1,
            ).encode(),
            updatedAtEpochMs: _clock.value.millisecondsSinceEpoch,
          ),
        );
  }

  Future<void> dispose() => database.close();
}

/// Eigene Übung ohne Server-Stand, also lokal angelegt.
Future<CatalogExercise> seedOwnExercise(
  CatalogHarness harness, {
  required String name,
  ExerciseKind kind = ExerciseKind.strength,
  List<String> categoryIds = const [],
  String? notes,
  double? bodyweightFactor,
  double? weightFactor,
}) => harness.repository.createCustomExercise(
  CatalogExercise(
    id: harness.repository.newId(),
    name: name,
    exerciseType: kind,
    categoryIds: categoryIds,
    notes: notes,
    bodyweightFactor: bodyweightFactor,
    weightFactor: weightFactor,
    isBase: false,
  ),
);

/// Beendetes Training mit einem Satz der angegebenen Übung.
Future<Workout> seedFinishedWorkout(
  CatalogHarness harness, {
  required String exerciseId,
  required String exerciseName,
  DateTime? start,
  double weightKg = 40,
  int repetitions = 10,
}) async {
  final startedAt = start ?? DateTime.utc(2026, 10, 10, 18);
  harness.now = startedAt;
  final repository = harness.repository;
  var workout = await repository.startEmpty(title: 'Training');
  workout = await repository.saveWorkout(
    workout.copyWith(
      exercises: [
        WorkoutBlock(
          workoutExerciseId: repository.newId(),
          sourceExerciseId: exerciseId,
          exerciseNameSnapshot: exerciseName,
          exerciseTypeSnapshot: ExerciseKind.strength,
          sets: [
            LoggedSet(
              setId: repository.newId(),
              weightKg: weightKg,
              repetitions: repetitions,
            ),
          ],
        ),
      ],
    ),
  );
  harness.now = startedAt.add(const Duration(hours: 1));
  return repository.finishWorkout(workout.workoutId);
}

/// Hält ein Widget in einer Host-Seite, die den Testgegenstand per Knopf öffnet.
Widget catalogHost({
  required Widget Function(BuildContext context) buildRoute,
  Brightness brightness = Brightness.light,
}) => trainingTestApp(
  brightness: brightness,
  home: Builder(
    builder: (context) => CupertinoPageScaffold(
      child: Center(
        child: CupertinoButton(
          key: const ValueKey('open-under-test'),
          onPressed: () => Navigator.of(context)
              .push<Object?>(CupertinoPageRoute<Object?>(builder: buildRoute)),
          child: const Text('Öffnen'),
        ),
      ),
    ),
  ),
);
