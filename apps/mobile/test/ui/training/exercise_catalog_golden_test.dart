import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/exercise_catalog_model.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/ui/features/training/category_library_screen.dart';
import 'package:gainer_mobile/ui/features/training/exercise_editor_screen.dart';
import 'package:gainer_mobile/ui/features/training/exercise_library_screen.dart';

import 'exercise_catalog_test_support.dart';
import 'training_plans_test_support.dart';
import 'training_test_support.dart';

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    final name = brightness.name;

    testWidgets('Übungsliste $name', (tester) async {
      usePhoneSize(tester);
      final harness = await tester.runAsync(CatalogHarness.create);
      if (harness == null) throw StateError('Harness nicht erstellt.');
      addTearDown(() => tester.runAsync(harness.dispose));
      await tester.runAsync(() async {
        await seedOwnExercise(
          harness,
          name: 'Landmine Press',
          categoryIds: const ['base-chest'],
          bodyweightFactor: 0.5,
        );
        await seedOwnExercise(
          harness,
          name: 'Ausfallschritt',
          kind: ExerciseKind.bodyweightOnly,
          categoryIds: const ['base-legs'],
        );
      });
      await tester.pumpWidget(
        trainingTestApp(
          brightness: brightness,
          home: ExerciseLibraryScreen(repository: harness.repository),
        ),
      );
      await settle(tester);

      await expectLater(
        find.byType(CupertinoPageScaffold),
        matchesGoldenFile('goldens/exercise_library_$name.png'),
      );
    });

    testWidgets('Übungseditor $name', (tester) async {
      usePhoneSize(tester);
      final harness = await tester.runAsync(CatalogHarness.create);
      if (harness == null) throw StateError('Harness nicht erstellt.');
      addTearDown(() => tester.runAsync(harness.dispose));
      final exercise = await tester.runAsync(
        () => seedOwnExercise(
          harness,
          name: 'Landmine Press',
          categoryIds: const ['base-chest'],
          notes: 'Einarmig, neutraler Griff',
          bodyweightFactor: 0.5,
          weightFactor: 1.5,
        ),
      );
      await tester.pumpWidget(
        trainingTestApp(
          brightness: brightness,
          home: ExerciseEditorScreen(
            repository: harness.repository,
            exercise: exercise,
          ),
        ),
      );
      await settle(tester);

      await expectLater(
        find.byType(CupertinoPageScaffold),
        matchesGoldenFile('goldens/exercise_editor_$name.png'),
      );
    });

    testWidgets('Kategorien $name', (tester) async {
      usePhoneSize(tester);
      final harness = await tester.runAsync(CatalogHarness.create);
      if (harness == null) throw StateError('Harness nicht erstellt.');
      addTearDown(() => tester.runAsync(harness.dispose));
      await tester.runAsync(() async {
        await harness.repository.createCategory(
          const CatalogCategory(
            id: '00000000-0000-4000-8000-0000000000c1',
            name: 'Reha',
            isBase: false,
          ),
        );
      });
      await tester.pumpWidget(
        trainingTestApp(
          brightness: brightness,
          home: CategoryLibraryScreen(repository: harness.repository),
        ),
      );
      await settle(tester);

      await expectLater(
        find.byType(CupertinoPageScaffold),
        matchesGoldenFile('goldens/category_library_$name.png'),
      );
    });
  }
}
