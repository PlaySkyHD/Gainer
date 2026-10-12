import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/repositories/training/training_repository.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/domain/models/training/training.dart';
import 'package:gainer_mobile/ui/features/training/training_screen.dart';
import 'package:gainer_mobile/ui/features/training/training_view_model.dart';

const accountId = '00000000-0000-4000-8000-000000000004';

class WidgetCatalog implements ExerciseCatalogProvider {
  @override
  Future<List<ExerciseCatalogEntry>> loadExercises() async => const [
    ExerciseCatalogEntry(
      id: 'catalog-squat',
      name: 'Kniebeuge',
      catalogVersion: 1,
    ),
  ];
}

void main() {
  testWidgets('Training screen starts a persisted workout from a template', (
    tester,
  ) async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = TrainingRepository(
      store: LocalSyncStore(database: database, accountId: accountId),
      catalog: WidgetCatalog(),
    );
    final templateId = await repository.saveTemplate(
      name: 'Kraft A',
      items: [
        TrainingTemplateItem(
          id: 'template-item',
          exerciseId: 'catalog-squat',
          plannedSets: 2,
          minimumRepetitions: 5,
          maximumRepetitions: 8,
          targetRir: 2,
          restSeconds: 90,
          notes: null,
        ),
      ],
    );
    final model = TrainingViewModel(repository);
    await tester.pumpWidget(
      CupertinoApp(home: TrainingScreen(viewModel: model)),
    );
    await tester.pumpAndSettle();

    final start = find.byKey(ValueKey('training-start-$templateId'));
    expect(start, findsOneWidget);
    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('running-workout-title')), findsOneWidget);
    expect(find.text('Kraft A'), findsOneWidget);
    expect(
      await repository.store.readOutbox(aggregateType: 'workout'),
      hasLength(1),
    );
  });
}
