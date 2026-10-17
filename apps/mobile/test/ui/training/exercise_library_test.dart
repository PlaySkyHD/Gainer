import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';
import 'package:gainer_mobile/ui/features/training/active_workout_controller.dart';
import 'package:gainer_mobile/ui/features/training/exercise_library_screen.dart';
import 'package:gainer_mobile/ui/features/training/exercise_library_view_model.dart';
import 'package:gainer_mobile/ui/features/training/training_plans_section.dart';

import 'exercise_catalog_test_support.dart';
import 'training_plans_test_support.dart';
import 'training_test_support.dart';

void main() {
  group('Suche und Filter', () {
    late CatalogHarness harness;
    late ExerciseLibraryViewModel viewModel;

    setUp(() async {
      harness = await CatalogHarness.create();
      viewModel = ExerciseLibraryViewModel(repository: harness.repository);
    });

    tearDown(() async {
      viewModel.dispose();
      await harness.dispose();
    });

    List<String> visibleNames() => [
      for (final exercise in viewModel.visibleExercises) exercise.name,
    ];

    test('findet Namen unabhängig von Groß-/Kleinschreibung', () async {
      await viewModel.load();

      viewModel.setQuery('BANKDRÜCK');
      expect(visibleNames(), ['Bankdrücken']);

      viewModel.setQuery('bankdrück');
      expect(visibleNames(), ['Bankdrücken']);
    });

    test('findet Umlaute mit und ohne Umlautzeichen', () async {
      await seedOwnExercise(harness, name: 'Übungsvariante');
      await viewModel.load();

      viewModel.setQuery('uebung');
      expect(visibleNames(), ['Übungsvariante']);

      viewModel.setQuery('ÜBUNG');
      expect(visibleNames(), ['Übungsvariante']);
    });

    test('Teiltreffer finden beide Kniebeugen', () async {
      await viewModel.load();

      viewModel.setQuery('kniebeu');

      expect(visibleNames(), ['Bulgarische Kniebeuge', 'Kniebeuge']);
    });

    test('Kategorie-Filter und Archiv-Schalter blenden Übungen aus', () async {
      final archived = await seedOwnExercise(
        harness,
        name: 'Reha Band',
        categoryIds: const ['base-chest'],
      );
      await harness.repository.archiveCustomExercise(archived.id);
      await viewModel.load();

      viewModel.setCategory('base-chest');
      expect(visibleNames(), ['Bankdrücken', 'Liegestütz']);

      viewModel.setShowArchived(true);
      expect(visibleNames(), ['Bankdrücken', 'Liegestütz', 'Reha Band']);

      viewModel.setCategory(null);
      viewModel.setShowArchived(false);
      expect(visibleNames(), contains('Kniebeuge'));
      expect(visibleNames(), isNot(contains('Reha Band')));
    });
  });

  testWidgets('Basisübung ist als Katalog gekennzeichnet', (tester) async {
    usePhoneSize(tester);
    final harness = await tester.runAsync(CatalogHarness.create);
    if (harness == null) throw StateError('Harness nicht erstellt.');
    addTearDown(() => tester.runAsync(harness.dispose));
    await tester.pumpWidget(
      trainingTestApp(
        home: ExerciseLibraryScreen(repository: harness.repository),
      ),
    );
    await settle(tester);

    expect(find.text('Bankdrücken'), findsOneWidget);
    expect(find.text('Katalog · Kraft'), findsWidgets);
  });

  testWidgets('Archivierte eigene Übung erscheint erst mit Schalter', (
    tester,
  ) async {
    usePhoneSize(tester);
    final harness = await tester.runAsync(CatalogHarness.create);
    if (harness == null) throw StateError('Harness nicht erstellt.');
    addTearDown(() => tester.runAsync(harness.dispose));
    await tester.runAsync(() async {
      final exercise = await seedOwnExercise(harness, name: 'Alte Übung');
      await harness.repository.archiveCustomExercise(exercise.id);
    });
    await tester.pumpWidget(
      trainingTestApp(
        home: ExerciseLibraryScreen(repository: harness.repository),
      ),
    );
    await settle(tester);
    expect(find.text('Alte Übung'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('exercise-library-archived')));
    await settle(tester);

    expect(find.text('Alte Übung'), findsOneWidget);
    expect(find.text('Eigene · Kraft · Archiviert'), findsOneWidget);
  });

  testWidgets('Pläne-Segment bietet Einstieg in den Katalog', (tester) async {
    usePhoneSize(tester);
    final harness = await tester.runAsync(CatalogHarness.create);
    if (harness == null) throw StateError('Harness nicht erstellt.');
    addTearDown(() => tester.runAsync(harness.dispose));
    final active = ActiveWorkoutController(harness.repository);
    addTearDown(active.dispose);
    await tester.pumpWidget(
      trainingTestApp(
        home: GainerScaffold(
          title: 'Training',
          children: [
            TrainingPlansSection(
              repository: harness.repository,
              activeWorkout: active,
            ),
          ],
        ),
      ),
    );
    await settle(tester);

    expect(find.text('Katalog'), findsOneWidget);
    expect(find.text('Kategorien verwalten'), findsOneWidget);

    await tester.tap(find.text('Übungen verwalten'));
    await settle(tester);

    expect(find.text('Übungen'), findsWidgets);
    expect(find.text('Bankdrücken'), findsOneWidget);
  });
}
