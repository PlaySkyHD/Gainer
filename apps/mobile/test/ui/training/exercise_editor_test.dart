import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/training/training_log_repository.dart';
import 'package:gainer_mobile/domain/models/training/exercise_catalog_model.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';
import 'package:gainer_mobile/ui/features/training/exercise_editor_screen.dart';
import 'package:gainer_mobile/ui/features/training/exercise_editor_view_model.dart';

import 'exercise_catalog_test_support.dart';
import 'training_plans_test_support.dart';
import 'training_test_support.dart';

/// Repository, dessen Kategorien beim ersten Laden scheitern.
class _FlakyRepository extends TrainingLogRepository {
  _FlakyRepository(CatalogHarness harness)
    : super(store: harness.store, catalog: harness.repository.catalog);

  bool failing = true;

  @override
  Future<List<CatalogCategory>> readCategories({
    bool includeArchived = false,
  }) async {
    if (failing) throw StateError('offline');
    return super.readCategories(includeArchived: includeArchived);
  }
}

Future<CatalogHarness> _harness(WidgetTester tester) async {
  final harness = await tester.runAsync(CatalogHarness.create);
  if (harness == null) throw StateError('Harness nicht erstellt.');
  addTearDown(() => tester.runAsync(harness.dispose));
  return harness;
}

/// Öffnet den Editor aus einer Host-Seite, damit „Speichern“ zurückpoppt.
Future<void> _openEditor(
  WidgetTester tester,
  CatalogHarness harness, {
  CatalogExercise? exercise,
}) async {
  usePhoneSize(tester);
  await tester.pumpWidget(
    catalogHost(
      buildRoute: (_) => ExerciseEditorScreen(
        repository: harness.repository,
        exercise: exercise,
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-under-test')));
  await settle(tester);
}

Future<void> _enter(WidgetTester tester, Key key, String text) async {
  await scrollIntoView(tester, find.byKey(key));
  await tester.enterText(find.byKey(key), text);
  await settle(tester);
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('exercise-save')));
  await settle(tester);
}

void main() {
  testWidgets('eigene Übung lässt sich offline anlegen und ist sofort lesbar', (
    tester,
  ) async {
    final harness = await _harness(tester);
    await _openEditor(tester, harness);

    await _enter(tester, const ValueKey('exercise-name'), 'Landmine Press');
    await tester.tap(find.byKey(const ValueKey('exercise-kind-strength')));
    await settle(tester);
    await _save(tester);

    expect(find.byKey(const ValueKey('exercise-save')), findsNothing);
    final own = await tester.runAsync(
      () async => [
        for (final exercise in await harness.repository.readExercises())
          if (!exercise.isBase) exercise,
      ],
    );
    expect(own, hasLength(1));
    expect(own!.single.name, 'Landmine Press');
    expect(own.single.exerciseType, ExerciseKind.strength);
    expect(own.single.isBase, isFalse);
  });

  testWidgets('Basisübung ist nur lesbar und lässt sich nicht speichern', (
    tester,
  ) async {
    final harness = await _harness(tester);
    await _openEditor(tester, harness, exercise: baseBench);

    expect(find.byKey(const ValueKey('exercise-name')), findsNothing);
    expect(find.byKey(const ValueKey('exercise-save')), findsNothing);
    expect(find.byKey(const ValueKey('exercise-archive')), findsNothing);
    expect(find.text('Basisübung. Sie ist schreibgeschützt.'), findsOneWidget);
    expect(find.text('Bankdrücken'), findsWidgets);

    final refused = await tester.runAsync(() async {
      try {
        await harness.repository.updateCustomExercise(baseBench);
        return false;
      } on StateError {
        return true;
      }
    });
    expect(refused, isTrue);
  });

  testWidgets(
    'Typwechsel einer verwendeten Übung speichert erst nach Bestätigung',
    (tester) async {
      final harness = await _harness(tester);
      final exercise = await tester.runAsync(() async {
        final own = await seedOwnExercise(harness, name: 'Ausfallschritt');
        await seedFinishedWorkout(
          harness,
          exerciseId: own.id,
          exerciseName: own.name,
        );
        return own;
      });
      await _openEditor(tester, harness, exercise: exercise);

      await tester.tap(
        find.byKey(const ValueKey('exercise-kind-bodyweightOnly')),
      );
      await settle(tester);
      await _save(tester);

      expect(
        find.text('Bestehende Sätze werden nach dem neuen Typ ausgewertet.'),
        findsOneWidget,
      );
      var stored = await tester.runAsync(
        () => harness.repository.readExercises().then(
          (all) => all.singleWhere((item) => item.id == exercise!.id),
        ),
      );
      expect(stored!.exerciseType, ExerciseKind.strength);

      await tester.tap(find.text('Ändern').last);
      await settle(tester);

      stored = await tester.runAsync(
        () => harness.repository.readExercises().then(
          (all) => all.singleWhere((item) => item.id == exercise!.id),
        ),
      );
      expect(stored!.exerciseType, ExerciseKind.bodyweightOnly);
    },
  );

  testWidgets('Speichern ist gesperrt, solange das Laden nicht gelang', (
    tester,
  ) async {
    final harness = await _harness(tester);
    final exercise = await tester.runAsync(
      () => seedOwnExercise(harness, name: 'Ausfallschritt'),
    );
    // Eine geschlossene Datenbank lässt readCategories scheitern.
    await tester.runAsync(harness.database.close);
    await _openEditor(tester, harness, exercise: exercise);

    expect(find.text('Die Übung konnte nicht geladen werden.'), findsOneWidget);
    final save = tester.widget<GainerPillButton>(
      find.byKey(const ValueKey('exercise-save')),
    );
    expect(save.onPressed, isNull);

    final viewModel = ExerciseEditorViewModel(
      repository: harness.repository,
      exercise: exercise,
    );
    addTearDown(viewModel.dispose);
    await tester.runAsync(viewModel.load);
    final saved = await viewModel.save(
      const ExerciseEditorInput(
        name: 'Ausfallschritt',
        kind: ExerciseKind.strength,
        categoryIds: [],
      ),
    );
    expect(saved, isFalse);
    expect(viewModel.errorMessage, isNotNull);
  });

  test('eine neue Übung lässt sich auch nach Ladefehler speichern', () async {
    final harness = await CatalogHarness.create();
    addTearDown(harness.dispose);
    final flaky = _FlakyRepository(harness);
    final viewModel = ExerciseEditorViewModel(repository: flaky);
    addTearDown(viewModel.dispose);

    await viewModel.load();
    expect(viewModel.loadFailed, isTrue);
    expect(viewModel.canSave, isTrue);

    final saved = await viewModel.save(
      const ExerciseEditorInput(
        name: 'Landmine Press',
        kind: ExerciseKind.strength,
        categoryIds: [],
      ),
    );
    expect(saved, isTrue);
  });

  test('Erneut laden hebt die Sperre einer bestehenden Übung auf', () async {
    final harness = await CatalogHarness.create();
    addTearDown(harness.dispose);
    final exercise = await seedOwnExercise(harness, name: 'Ausfallschritt');
    final flaky = _FlakyRepository(harness);
    final viewModel = ExerciseEditorViewModel(
      repository: flaky,
      exercise: exercise,
    );
    addTearDown(viewModel.dispose);

    await viewModel.load();
    expect(viewModel.loadFailed, isTrue);
    expect(viewModel.canSave, isFalse);

    flaky.failing = false;
    await viewModel.load();

    expect(viewModel.loadFailed, isFalse);
    expect(viewModel.errorMessage, isNull);
    expect(viewModel.canSave, isTrue);
  });

  testWidgets('Körpergewicht 64 % wird als Faktor 0,64 gespeichert', (
    tester,
  ) async {
    final harness = await _harness(tester);
    await _openEditor(tester, harness);

    await _enter(tester, const ValueKey('exercise-name'), 'Dips Variante');
    await _enter(tester, const ValueKey('exercise-bodyweight'), '64');
    await _save(tester);

    final stored = await tester.runAsync(
      () => harness.repository.readExercises().then(
        (all) => all.singleWhere((item) => item.name == 'Dips Variante'),
      ),
    );
    expect(stored!.bodyweightFactor, 0.64);
    expect(stored.weightFactor, isNull);
  });

  testWidgets('ungültige Faktoren und Namen zeigen Feldfehler', (tester) async {
    final harness = await _harness(tester);
    await _openEditor(tester, harness);

    await _enter(tester, const ValueKey('exercise-name'), 'Testübung');
    await _enter(tester, const ValueKey('exercise-bodyweight'), 'abc');
    await _save(tester);
    expect(find.text('Bitte eine Zahl eingeben.'), findsOneWidget);

    await _enter(tester, const ValueKey('exercise-bodyweight'), '150');
    await _save(tester);
    expect(
      find.text('Der Körpergewichtsfaktor muss zwischen 0 und 100 % liegen.'),
      findsOneWidget,
    );

    await _enter(tester, const ValueKey('exercise-bodyweight'), '');
    await _enter(tester, const ValueKey('exercise-weight-factor'), '0');
    await _save(tester);
    expect(
      find.text(
        'Der Zusatzgewichtsfaktor muss größer 0 und höchstens 10 sein.',
      ),
      findsOneWidget,
    );

    await _enter(tester, const ValueKey('exercise-weight-factor'), '11');
    await _save(tester);
    expect(
      find.text(
        'Der Zusatzgewichtsfaktor muss größer 0 und höchstens 10 sein.',
      ),
      findsOneWidget,
    );

    await _enter(tester, const ValueKey('exercise-weight-factor'), '2,5');
    await _enter(tester, const ValueKey('exercise-name'), '');
    await _save(tester);
    expect(
      find.text('Der Name muss zwischen 1 und 160 Zeichen lang sein.'),
      findsOneWidget,
    );

    final all = await tester.runAsync(harness.repository.readExercises);
    expect(all!.where((item) => !item.isBase), isEmpty);
  });

  testWidgets('Archivieren verbirgt die Übung, Historie behält den Namen', (
    tester,
  ) async {
    final harness = await _harness(tester);
    final exercise = await tester.runAsync(() async {
      final own = await seedOwnExercise(harness, name: 'Schrägbank Flys');
      await seedFinishedWorkout(
        harness,
        exerciseId: own.id,
        exerciseName: own.name,
      );
      return own;
    });
    await _openEditor(tester, harness, exercise: exercise);

    await scrollIntoView(
      tester,
      find.byKey(const ValueKey('exercise-archive')),
    );
    await tester.tap(find.byKey(const ValueKey('exercise-archive')));
    await settle(tester);
    expect(find.text('Übung archivieren?'), findsOneWidget);
    await tester.tap(find.text('Archivieren').last);
    await settle(tester);

    final state = await tester.runAsync(() async {
      final active = await harness.repository.readExercises();
      final everything = await harness.repository.readExercises(
        includeArchived: true,
      );
      final diary = await harness.repository.readDiary();
      return (active, everything, diary);
    });
    final (active, everything, diary) = state!;
    expect(active.any((item) => item.id == exercise!.id), isFalse);
    expect(
      everything.singleWhere((item) => item.id == exercise!.id).isArchived,
      isTrue,
    );
    final block = diary.single.exercises.single;
    expect(block.exerciseNameSnapshot, 'Schrägbank Flys');
    expect(block.sourceExerciseId, exercise!.id);
  });
}
