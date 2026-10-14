import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/api/api_models.dart';
import 'package:gainer_mobile/data/repositories/insights/insights_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/repositories/training/training_repository.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/domain/models/training/training.dart';
import 'package:gainer_mobile/ui/features/progress/exercise_progress_section.dart';
import 'package:gainer_mobile/ui/features/progress/progress_view_model.dart';

const _account = '10000000-0000-4000-8000-000000000001';
const _squat = '00000000-0000-4000-8000-000000000004';
const _row = '00000000-0000-4000-8000-000000000005';

void main() {
  testWidgets('exercise picker and period update real progress request', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    final database = LocalDatabase(NativeDatabase.memory());
    final store = LocalSyncStore(database: database, accountId: _account);
    final api = _ProgressApi();
    final training = TrainingRepository(
      store: store,
      catalog: _FixtureCatalog(),
    );
    final model = ProgressViewModel(
      InsightsRepository(api, store: store),
      trainingRepository: training,
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
    final training = TrainingRepository(
      store: store,
      catalog: _FixtureCatalog(),
    );
    final model = ProgressViewModel(
      InsightsRepository(api, store: store),
      trainingRepository: training,
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
}

class _FixtureCatalog implements ExerciseCatalogProvider {
  @override
  Future<List<ExerciseCatalogEntry>> loadExercises() async => const [
    ExerciseCatalogEntry(id: _squat, name: 'Kniebeuge', catalogVersion: 1),
    ExerciseCatalogEntry(id: _row, name: 'Rudern', catalogVersion: 1),
  ];
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
  final requests = <(String, String)>[];
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
          bestWeightKg: 110,
          bestRepetitions: 3,
          estimatedOneRepMaxKg: estimate + 10,
        ),
        ApiExerciseProgressPoint(
          workoutId: '30000000-0000-4000-8000-000000000001',
          completedAtUtc: DateTime.utc(2026, 10, 12),
          volumeKgRepetitions: 1000,
          bestWeightKg: 100,
          bestRepetitions: 3,
          estimatedOneRepMaxKg: estimate,
        ),
      ],
      bestSet: null,
    );
  }
}
