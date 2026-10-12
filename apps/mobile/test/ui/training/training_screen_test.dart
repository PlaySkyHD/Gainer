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
    await _scrollTo(tester, start);
    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('running-workout-title')), findsOneWidget);
    expect(find.text('Kraft A'), findsOneWidget);
    expect(
      await repository.store.readOutbox(aggregateType: 'workout'),
      hasLength(1),
    );
    model.dispose();
  });

  testWidgets(
    'two set editors keep values by set identity and preserve RIR and notes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final database = LocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = TrainingRepository(
        store: LocalSyncStore(database: database, accountId: accountId),
        catalog: WidgetCatalog(),
      );
      final templateId = await repository.saveTemplate(
        name: 'Sätze',
        items: [
          TrainingTemplateItem(
            id: 'two-set-item',
            exerciseId: 'catalog-squat',
            plannedSets: 2,
            minimumRepetitions: 5,
            maximumRepetitions: 8,
            targetRir: null,
            restSeconds: 90,
            notes: null,
          ),
        ],
      );
      await repository.startWorkout(templateId);
      final model = TrainingViewModel(repository);
      await tester.pumpWidget(
        CupertinoApp(home: TrainingScreen(viewModel: model)),
      );
      await tester.pumpAndSettle();

      final sets = model.runningWorkout!.exercises.single.sets;
      final first = sets[0];
      final second = sets[1];
      await tester.enterText(
        find.byKey(ValueKey('set-weight-${first.id}')),
        '42.5',
      );
      await tester.enterText(
        find.byKey(ValueKey('set-repetitions-${first.id}')),
        '7',
      );
      await tester.enterText(find.byKey(ValueKey('set-rir-${first.id}')), '2');
      await tester.enterText(
        find.byKey(ValueKey('set-notes-${first.id}')),
        'saubere Wiederholung',
      );
      await tester.enterText(
        find.byKey(ValueKey('set-weight-${second.id}')),
        '60',
      );
      await tester.enterText(
        find.byKey(ValueKey('set-repetitions-${second.id}')),
        '5',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('training-log-${first.id}')));
      await tester.pumpAndSettle();

      final savedFirst = model.runningWorkout!.exercises.single.sets.firstWhere(
        (set) => set.id == first.id,
      );
      expect(savedFirst.weightKg, 42.5);
      expect(savedFirst.repetitions, 7);
      expect(savedFirst.rir, 2);
      expect(savedFirst.notes, 'saubere Wiederholung');
      expect(find.text('60'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(ValueKey('training-set-down-${first.id}')),
      );
      await tester.tap(find.byKey(ValueKey('training-set-down-${first.id}')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('training-set-card-${second.id}')),
        findsWidgets,
      );
      expect(
        tester
            .widget<CupertinoTextField>(
              find.byKey(ValueKey('set-weight-${first.id}')),
            )
            .controller!
            .text,
        '42.5',
      );
      expect(
        tester
            .widget<CupertinoTextField>(
              find.byKey(ValueKey('set-weight-${second.id}')),
            )
            .controller!
            .text,
        '60',
      );
      expect(tester.takeException(), isNull);
      model.dispose();
    },
  );

  testWidgets(
    'multi-exercise template edits preserve completed workout snapshots and fit large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final database = LocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = TrainingRepository(
        store: LocalSyncStore(database: database, accountId: accountId),
        catalog: WidgetCatalog(),
      );
      final customId = await repository.createCustomExercise(
        const ExerciseValues(
          name: 'Kreuzheben',
          description: 'Hantel vom Boden heben',
          targetMuscle: 'Rücken',
          muscleGroup: 'hintere Kette',
          equipment: 'Langhantel',
        ),
      );
      final templateId = await repository.saveTemplate(
        name: 'Ganzkörper',
        items: [
          TrainingTemplateItem(
            id: 'squat-item',
            exerciseId: 'catalog-squat',
            plannedSets: 1,
            minimumRepetitions: 5,
            maximumRepetitions: 8,
            targetRir: 2,
            restSeconds: 90,
            notes: 'Kontrolliert',
          ),
          TrainingTemplateItem(
            id: 'deadlift-item',
            exerciseId: customId,
            plannedSets: 1,
            minimumRepetitions: 4,
            maximumRepetitions: 6,
            targetRir: 1,
            restSeconds: 120,
            notes: 'Rücken neutral',
          ),
        ],
      );
      final workoutId = await repository.startWorkout(templateId);
      var workout = (await repository.readRunningWorkout())!;
      for (final exercise in workout.exercises) {
        final set = exercise.sets.single;
        workout = await repository.logSet(
          workoutId: workoutId,
          exerciseId: exercise.id,
          setId: set.id,
          weightKg: 50,
          repetitions: 6,
          rir: 2,
          notes: 'Historischer Wert',
          complete: true,
        );
      }
      await repository.completeWorkout(workoutId);

      final model = TrainingViewModel(repository);
      await tester.pumpWidget(
        CupertinoApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 568),
              textScaler: TextScaler.linear(2),
            ),
            child: TrainingScreen(viewModel: model),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _scrollTo(
        tester,
        find.byKey(ValueKey('training-template-edit-$templateId')),
      );
      await tester.tap(
        find.byKey(ValueKey('training-template-edit-$templateId')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('training-template-item-squat-item')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('training-template-item-deadlift-item')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('training-item-sets-squat-item')),
        '3',
      );
      await tester.enterText(
        find.byKey(const ValueKey('training-item-min-squat-item')),
        '6',
      );
      await tester.enterText(
        find.byKey(const ValueKey('training-item-max-squat-item')),
        '10',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await _scrollTo(
        tester,
        find.byKey(const ValueKey('training-create-template')),
      );
      await tester.tap(find.byKey(const ValueKey('training-create-template')));
      await tester.pumpAndSettle();

      final edited = (await repository.readPlanning()).templates
          .singleWhere((item) => item.id == templateId)
          .value;
      expect(edited.items, hasLength(2));
      expect(edited.items.first.plannedSets, 3);
      expect(edited.items.first.minimumRepetitions, 6);
      expect(edited.items.first.maximumRepetitions, 10);
      expect(edited.items.last.exerciseId, customId);
      await _scrollTo(
        tester,
        find.byKey(ValueKey('training-history-$workoutId')),
      );
      await tester.tap(find.byKey(ValueKey('training-history-$workoutId')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ganzkörper'), findsWidgets);
      expect(find.text('Kniebeuge'), findsWidgets);
      expect(find.textContaining('50.0 kg × 6 Wdh.'), findsWidgets);
      expect(find.textContaining('Historischer Wert'), findsWidgets);
      expect(tester.takeException(), isNull);
      model.dispose();
    },
  );
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  final list = find.byType(ListView).first;
  for (var attempt = 0; attempt < 12; attempt++) {
    final rect = tester.getRect(finder);
    if (rect.top >= 0 && rect.bottom <= tester.view.physicalSize.height) return;
    final delta = rect.bottom > tester.view.physicalSize.height
        ? -350.0
        : 350.0;
    await tester.drag(list, Offset(0, delta));
    await tester.pumpAndSettle();
  }
}
