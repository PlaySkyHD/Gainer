import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/api/api_models.dart';
import 'package:gainer_mobile/data/repositories/insights/insights_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/repositories/training/api_exercise_catalog_provider.dart';
import 'package:gainer_mobile/data/repositories/training/training_log_repository.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/domain/models/training/exercise_catalog_model.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/ui/features/progress/progress_view_model.dart';

const _account = '10000000-0000-4000-8000-000000000001';
const _squat = '00000000-0000-4000-8000-000000000004';
const _row = '00000000-0000-4000-8000-000000000005';

void main() {
  late LocalDatabase database;
  late LocalSyncStore store;
  late _ProgressApi api;
  late ProgressViewModel model;
  var databaseClosed = false;

  setUp(() {
    databaseClosed = false;
    database = LocalDatabase(NativeDatabase.memory());
    store = LocalSyncStore(database: database, accountId: _account);
    api = _ProgressApi();
    final training = TrainingLogRepository(
      store: store,
      catalog: _FixtureCatalog(),
    );
    model = ProgressViewModel(
      InsightsRepository(api, store: store),
      training: training,
    );
  });

  tearDown(() async {
    model.dispose();
    api.close();
    if (!databaseClosed) await database.close();
  });

  test(
    'offline error shows matching cached selection and window as stale',
    () async {
      await model.repository.cacheExerciseProgress(
        exerciseId: _squat,
        window: '30',
        value: _sample(_squat, 30),
      );
      api.fail = true;
      await model.loadExerciseOptions();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(model.selectedExerciseId, _squat);
      expect(model.exerciseProgress?.exerciseId, _squat);
      expect(model.isExerciseProgressStale, isTrue);
      expect(model.exerciseProgressErrorMessage, isNull);

      await model.selectExercise(_row);
      expect(model.exerciseProgress, isNull);
      expect(model.isExerciseProgressStale, isFalse);
      expect(
        model.exerciseProgressErrorMessage,
        contains('gerade nicht verfügbar'),
      );
    },
  );

  test(
    'late response from previous exercise cannot replace active selection',
    () async {
      api.defer = true;
      await model.loadExerciseOptions();
      await _until(() => api.pending.containsKey(_squat));
      final selectingRow = model.selectExercise(_row);
      await _until(() => api.pending.containsKey(_row));
      api.pending[_row]!.complete(_sample(_row, 30));
      await selectingRow;
      api.pending[_squat]!.complete(_sample(_squat, 30));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(model.selectedExerciseId, _row);
      expect(model.exerciseProgress?.exerciseId, _row);
      expect(model.exerciseProgress?.points.single.estimatedOneRepMaxKg, 105);
    },
  );
  test(
    'progress refresh reloads custom exercises and drops archived selection',
    () async {
      await model.loadExerciseOptions(refresh: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final training = model.training!;
      final customId = training.newId();
      await training.createCustomExercise(
        CatalogExercise(
          id: customId,
          name: 'Kurzhantelzug',
          exerciseType: ExerciseKind.strength,
          isBase: false,
        ),
      );
      await model.loadExerciseOptions(refresh: true);
      expect(model.exerciseOptions.any((item) => item.id == customId), isTrue);
      await model.selectExercise(customId);
      await training.archiveCustomExercise(customId);
      await model.loadExerciseOptions(refresh: true);
      expect(model.exerciseOptions.any((item) => item.id == customId), isFalse);
      expect(model.selectedExerciseId, _squat);
      await _until(() => model.exerciseProgress?.exerciseId == _squat);
      expect(model.exerciseProgress?.exerciseId, _squat);
    },
  );

  test(
    'fresh API progress remains visible if local cache write fails',
    () async {
      await model.loadExerciseOptions(refresh: true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await database.close();
      databaseClosed = true;
      await model.loadSelectedExerciseProgress(refresh: true);
      expect(model.exerciseProgress?.exerciseId, _squat);
      expect(model.exerciseProgress?.points.single.estimatedOneRepMaxKg, 110);
      expect(model.isExerciseProgressStale, isFalse);
    },
  );
}

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue, reason: 'Expected async request did not start.');
}

ApiExerciseProgress _sample(String exerciseId, int window) =>
    ApiExerciseProgress(
      asOfRevision: 3,
      exerciseId: exerciseId,
      windowDays: window,
      fromUtc: DateTime.utc(2026, 9, 14),
      throughUtc: DateTime.utc(2026, 10, 14),
      points: [
        ApiExerciseProgressPoint(
          workoutId: '30000000-0000-4000-8000-000000000001',
          completedAtUtc: DateTime.utc(2026, 10, 12),
          volumeKgRepetitions: 1000,
          bodyweightMissing: false,
          maxWeightKg: 100,
          maxRepetitions: 3,
          estimatedOneRepMaxKg: exerciseId == _row ? 105 : 110,
        ),
      ],
      volumeAlgorithmVersion: 'training-volume-v2',
      estimatedOneRepMaxAlgorithmVersion: 'e1rm-epley-v2',
      records: const ApiExerciseRecords(
        maxWeightKg: null,
        estimatedOneRepMaxKg: null,
        volumeKgRepetitions: null,
        maxRepetitions: null,
        repetitionRecords: [],
      ),
      bestSet: null,
    );

class _FixtureCatalog implements ExerciseCatalogProvider {
  @override
  bool get lastLoadWasStale => false;

  @override
  Future<BaseCatalog> loadBaseCatalog() async => const BaseCatalog(
    exercises: [
      CatalogExercise(
        id: _squat,
        name: 'Kniebeuge',
        exerciseType: ExerciseKind.strength,
        isBase: true,
      ),
      CatalogExercise(
        id: _row,
        name: 'Rudern',
        exerciseType: ExerciseKind.strength,
        isBase: true,
      ),
    ],
    categories: [],
  );
}

class _ProgressApi extends ApiClient {
  _ProgressApi()
    : super(
        configuration: ApiConfiguration(
          apiOrigin: Uri.parse('http://127.0.0.1:5099'),
          trustedFrontendOrigin: Uri.parse('http://127.0.0.1:5099'),
          allowInsecureLoopbackForDevelopment: true,
        ),
      );
  bool fail = false;
  bool defer = false;
  final pending = <String, Completer<ApiExerciseProgress>>{};

  @override
  Future<ApiExerciseProgress> getExerciseProgress({
    required String exerciseId,
    required String window,
    String timeZone = 'Europe/Berlin',
  }) {
    if (fail) {
      throw const ApiException(
        statusCode: null,
        code: 'offline',
        message: 'offline',
      );
    }
    if (defer) {
      final completer = Completer<ApiExerciseProgress>();
      pending[exerciseId] = completer;
      return completer.future;
    }
    return Future.value(_sample(exerciseId, int.parse(window)));
  }
}
