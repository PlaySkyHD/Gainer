import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/exercise_catalog_model.dart';
import 'package:gainer_mobile/domain/models/training/training_plan_model.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/ui/features/training/exercise_merge_sheet.dart';
import 'package:gainer_mobile/ui/features/training/exercise_statistics_view_model.dart';

import 'exercise_catalog_test_support.dart';
import 'training_plans_test_support.dart';
import 'training_test_support.dart';

const _source = CatalogExercise(
  id: '00000000-0000-4000-8000-0000000000b1',
  name: 'Bankdrücken LH',
  exerciseType: ExerciseKind.strength,
  isBase: false,
);

/// Legt die eigene Quellübung mit Serverstand an, verwendet in einem Training und einem Plan.
Future<void> _seedSource(CatalogHarness harness) async {
  await harness.seedServer('custom-exercise', _source.id, {
    ..._source.toJson(),
    'isArchived': false,
  });
  await seedFinishedWorkout(
    harness,
    exerciseId: _source.id,
    exerciseName: _source.name,
    weightKg: 80,
    repetitions: 8,
  );
  await harness.repository.createPlan(
    TrainingPlanModel(
      planId: harness.repository.newId(),
      name: 'Push',
      previousValueSource: PreviousValueSource.exercise,
      entries: [
        PlanEntry(entryId: harness.repository.newId(), exerciseId: _source.id),
      ],
    ),
  );
}

void main() {
  group('Zusammenführen', () {
    late CatalogHarness harness;

    setUp(() async {
      harness = await CatalogHarness.create();
    });

    tearDown(() => harness.dispose());

    test('Trainings und Pläne zählen danach für das Ziel, die Quelle ist archiviert', () async {
      await _seedSource(harness);

      await harness.repository.mergeExercises(
        sourceExerciseId: _source.id,
        targetExerciseId: 'base-bench',
      );

      final everything = await harness.repository.readExercises(
        includeArchived: true,
      );
      expect(
        everything.singleWhere((item) => item.id == _source.id).isArchived,
        isTrue,
      );
      final diary = await harness.repository.readDiary();
      final block = diary.single.exercises.single;
      expect(block.sourceExerciseId, 'base-bench');
      expect(block.exerciseNameSnapshot, 'Bankdrücken LH');
      final plans = await harness.repository.readPlans();
      expect(plans.single.entries.single.exerciseId, 'base-bench');

      final statistics = ExerciseStatisticsViewModel(
        repository: harness.repository,
        exerciseId: 'base-bench',
      );
      addTearDown(statistics.dispose);
      await statistics.load();
      expect(statistics.sessions, hasLength(1));
    });

    test('ein Zusammenführen mit der Quelle als Ziel wird abgelehnt', () async {
      await _seedSource(harness);

      expect(
        () => harness.repository.mergeExercises(
          sourceExerciseId: _source.id,
          targetExerciseId: _source.id,
        ),
        throwsStateError,
      );
    });
  });

  testWidgets('Bestätigung führt die Zusammenführung aus', (tester) async {
    usePhoneSize(tester);
    final harness = await tester.runAsync(CatalogHarness.create);
    if (harness == null) throw StateError('Harness nicht erstellt.');
    addTearDown(() => tester.runAsync(harness.dispose));
    await tester.runAsync(() => _seedSource(harness));

    bool? merged;
    await tester.pumpWidget(
      catalogHost(
        buildRoute: (_) => Builder(
          builder: (context) => CupertinoPageScaffold(
            child: Center(
              child: CupertinoButton(
                key: const ValueKey('merge-under-test'),
                onPressed: () async {
                  merged = await mergeExerciseInto(
                    context,
                    repository: harness.repository,
                    source: _source,
                    target: baseBench,
                  );
                },
                child: const Text('Zusammenführen'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-under-test')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('merge-under-test')));
    await settle(tester);

    expect(
      find.text(
        '„Bankdrücken LH“ wird in „Bankdrücken“ zusammengeführt. Trainings und Pläne zählen danach zu „Bankdrücken“, „Bankdrücken LH“ wird archiviert.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Zusammenführen').last);
    await settle(tester);

    expect(merged, isTrue);
    final archived = await tester.runAsync(
      () => harness.repository
          .readExercises(includeArchived: true)
          .then((all) => all.singleWhere((item) => item.id == _source.id)),
    );
    expect(archived!.isArchived, isTrue);
  });

  testWidgets('Abbrechen lässt die Quelle unverändert', (tester) async {
    usePhoneSize(tester);
    final harness = await tester.runAsync(CatalogHarness.create);
    if (harness == null) throw StateError('Harness nicht erstellt.');
    addTearDown(() => tester.runAsync(harness.dispose));
    await tester.runAsync(() => _seedSource(harness));

    bool? merged;
    await tester.pumpWidget(
      catalogHost(
        buildRoute: (_) => Builder(
          builder: (context) => CupertinoPageScaffold(
            child: Center(
              child: CupertinoButton(
                key: const ValueKey('merge-under-test'),
                onPressed: () async {
                  merged = await mergeExerciseInto(
                    context,
                    repository: harness.repository,
                    source: _source,
                    target: baseBench,
                  );
                },
                child: const Text('Zusammenführen'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-under-test')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('merge-under-test')));
    await settle(tester);
    await tester.tap(find.text('Abbrechen').last);
    await settle(tester);

    expect(merged, isFalse);
    final source = await tester.runAsync(
      () => harness.repository
          .readExercises(includeArchived: true)
          .then((all) => all.singleWhere((item) => item.id == _source.id)),
    );
    expect(source!.isArchived, isFalse);
  });
}
