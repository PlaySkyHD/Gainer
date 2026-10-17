import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
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
import 'package:gainer_mobile/ui/features/progress/exercise_progress_section.dart';
import 'package:gainer_mobile/ui/features/progress/progress_view_model.dart';

const _account = '10000000-0000-4000-8000-000000000001';
const _squat = '00000000-0000-4000-8000-000000000004';
const _row = '00000000-0000-4000-8000-000000000005';
const _workoutLatest = '30000000-0000-4000-8000-000000000002';

void main() {
  testWidgets('exercise picker and period update real progress request', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    final database = LocalDatabase(NativeDatabase.memory());
    final store = LocalSyncStore(database: database, accountId: _account);
    final api = _ProgressApi();
    final training = TrainingLogRepository(
      store: store,
      catalog: _FixtureCatalog(),
    );
    final model = ProgressViewModel(
      InsightsRepository(api, store: store),
      training: training,
    );
    addTearDown(() async {
      model.dispose();
      api.close();
      await database.close();
    });

    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [ExerciseProgressSection(viewModel: model)],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bestes geschätztes 1RM · 120.0 kg'), findsOneWidget);
    expect(find.text('Min. 110.0 kg'), findsOneWidget);
    expect(find.text('Max. 120.0 kg'), findsOneWidget);
    await tester.tap(find.text('7 T.'));
    await tester.pumpAndSettle();
    expect(api.requests.last, (_squat, '7'));

    await tester.tap(find.text('Kniebeuge').first);
    await tester.pumpAndSettle();
    expect(find.text('Übung suchen'), findsOneWidget);
    await tester.tap(find.text('Rudern'));
    await tester.pumpAndSettle();
    expect(find.text('Rudern'), findsOneWidget);
    expect(api.requests.last, (_row, '7'));
    expect(find.text('Bestes geschätztes 1RM · 115.0 kg'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('section stays usable at 320 points with 2x text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    final database = LocalDatabase(NativeDatabase.memory());
    final store = LocalSyncStore(database: database, accountId: _account);
    final api = _ProgressApi();
    final training = TrainingLogRepository(
      store: store,
      catalog: _FixtureCatalog(),
    );
    final model = ProgressViewModel(
      InsightsRepository(api, store: store),
      training: training,
    );
    addTearDown(() async {
      model.dispose();
      api.close();
      await database.close();
    });

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 568),
          textScaler: TextScaler.linear(2),
        ),
        child: CupertinoApp(
          home: CupertinoPageScaffold(
            child: SafeArea(
              child: ListView(
                children: [ExerciseProgressSection(viewModel: model)],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Übungsfortschritt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows records and bodyweight gaps as text', (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = LocalDatabase(NativeDatabase.memory());
    final store = LocalSyncStore(database: database, accountId: _account);
    final api = _ProgressApi(bodyweightMissing: true, withRecords: true);
    final model = ProgressViewModel(
      InsightsRepository(api, store: store),
      training: TrainingLogRepository(store: store, catalog: _FixtureCatalog()),
    );
    addTearDown(() async {
      model.dispose();
      api.close();
      await database.close();
    });

    await _pumpSection(tester, model);

    expect(
      find.text('Für korrekte Werte fehlt ein Check-in mit Körpergewicht.'),
      findsOneWidget,
    );
    expect(
      find.text('Bestes Set am 05.10.2026 · 110.0 kg × 3'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Effektives Gewicht: enthält bei Körpergewichtsübungen dein Körpergewicht.',
      ),
      findsOneWidget,
    );
    expect(find.text('Rekorde'), findsOneWidget);
    expect(find.text('Gesamte Historie bis heute'), findsOneWidget);
    expect(find.text('Geschätztes 1RM'), findsOneWidget);
    expect(find.text('120.0 kg'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('omits the records card and bodyweight hint when absent', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = LocalDatabase(NativeDatabase.memory());
    final store = LocalSyncStore(database: database, accountId: _account);
    final api = _ProgressApi();
    final model = ProgressViewModel(
      InsightsRepository(api, store: store),
      training: TrainingLogRepository(store: store, catalog: _FixtureCatalog()),
    );
    addTearDown(() async {
      model.dispose();
      api.close();
      await database.close();
    });

    await _pumpSection(tester, model);

    expect(find.text('Rekorde'), findsNothing);
    expect(
      find.text('Für korrekte Werte fehlt ein Check-in mit Körpergewicht.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpSection(WidgetTester tester, ProgressViewModel model) async {
  await tester.pumpWidget(
    CupertinoApp(
      home: CupertinoPageScaffold(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [ExerciseProgressSection(viewModel: model)],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

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
  _ProgressApi({this.bodyweightMissing = false, this.withRecords = false})
    : super(
        configuration: ApiConfiguration(
          apiOrigin: Uri.parse('http://127.0.0.1:5099'),
          trustedFrontendOrigin: Uri.parse('http://127.0.0.1:5099'),
          allowInsecureLoopbackForDevelopment: true,
        ),
      );
  final requests = <(String, String)>[];
  final bool bodyweightMissing;
  final bool withRecords;
  @override
  Future<ApiExerciseProgress> getExerciseProgress({
    required String exerciseId,
    required String window,
    String timeZone = 'Europe/Berlin',
  }) async {
    requests.add((exerciseId, window));
    final estimate = exerciseId == _row ? 105.0 : 110.0;
    return ApiExerciseProgress(
      asOfRevision: 4,
      exerciseId: exerciseId,
      windowDays: window == 'all' ? null : int.parse(window),
      fromUtc: DateTime.utc(2026, 9, 14),
      throughUtc: DateTime.utc(2026, 10, 14),
      points: [
        ApiExerciseProgressPoint(
          workoutId: '30000000-0000-4000-8000-000000000002',
          completedAtUtc: DateTime.utc(2026, 10, 5),
          volumeKgRepetitions: 1100,
          bodyweightMissing: bodyweightMissing,
          maxWeightKg: 110,
          maxRepetitions: 3,
          estimatedOneRepMaxKg: estimate + 10,
        ),
        ApiExerciseProgressPoint(
          workoutId: '30000000-0000-4000-8000-000000000001',
          completedAtUtc: DateTime.utc(2026, 10, 12),
          volumeKgRepetitions: 1000,
          bodyweightMissing: bodyweightMissing,
          maxWeightKg: 100,
          maxRepetitions: 3,
          estimatedOneRepMaxKg: estimate,
        ),
      ],
      volumeAlgorithmVersion: 'training-volume-v2',
      estimatedOneRepMaxAlgorithmVersion: 'e1rm-epley-v2',
      records: withRecords
          ? const ApiExerciseRecords(
              maxWeightKg: ApiRecordEvent(
                workoutId: _workoutLatest,
                value: 110,
              ),
              estimatedOneRepMaxKg: ApiRecordEvent(
                workoutId: _workoutLatest,
                value: 120,
              ),
              volumeKgRepetitions: ApiRecordEvent(
                workoutId: _workoutLatest,
                value: 1100,
              ),
              maxRepetitions: ApiRecordEvent(
                workoutId: _workoutLatest,
                value: 5,
              ),
              repetitionRecords: [],
            )
          : const ApiExerciseRecords(
              maxWeightKg: null,
              estimatedOneRepMaxKg: null,
              volumeKgRepetitions: null,
              maxRepetitions: null,
              repetitionRecords: [],
            ),
      bestSet: withRecords
          ? ApiBestSetInsight(
              workoutId: _workoutLatest,
              exerciseId: exerciseId,
              completedAtUtc: DateTime.utc(2026, 10, 5),
              effectiveWeightKg: 110,
              repetitions: 3,
              estimatedOneRepMaxKg: 120,
            )
          : null,
    );
  }
}
