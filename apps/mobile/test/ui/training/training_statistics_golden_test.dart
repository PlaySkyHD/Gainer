import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/features/training/exercise_statistics_screen.dart';
import 'package:gainer_mobile/ui/features/training/training_statistics_section.dart';

import 'training_statistics_test_support.dart';
import 'training_test_support.dart';

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    final name = brightness.name;

    testWidgets('Statistikliste $name', (tester) async {
      _phoneSize(tester);
      final harness = await tester.runAsync(TrainingHarness.create);
      if (harness == null) throw StateError('Harness nicht erstellt.');
      addTearDown(() => tester.runAsync(harness.dispose));
      await tester.runAsync(() => seedSquatScenario(harness));

      await tester.pumpWidget(
        trainingTestApp(
          brightness: brightness,
          home: CupertinoPageScaffold(
            child: SingleChildScrollView(
              child: TrainingStatisticsSection(repository: harness.repository),
            ),
          ),
        ),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(TrainingStatisticsSection),
        matchesGoldenFile('goldens/statistics_list_$name.png'),
      );
    });

    testWidgets('Übungsstatistik Graph $name', (tester) async {
      _phoneSize(tester);
      final harness = await tester.runAsync(TrainingHarness.create);
      if (harness == null) throw StateError('Harness nicht erstellt.');
      addTearDown(() => tester.runAsync(harness.dispose));
      await tester.runAsync(() => seedSquatScenario(harness));

      await tester.pumpWidget(
        trainingTestApp(
          brightness: brightness,
          home: ExerciseStatisticsScreen(
            repository: harness.repository,
            exerciseId: kneeExerciseId,
          ),
        ),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(ExerciseStatisticsScreen),
        matchesGoldenFile('goldens/exercise_statistics_chart_$name.png'),
      );
    });

    testWidgets('Übungsstatistik Rekorde $name', (tester) async {
      _phoneSize(tester);
      final harness = await tester.runAsync(TrainingHarness.create);
      if (harness == null) throw StateError('Harness nicht erstellt.');
      addTearDown(() => tester.runAsync(harness.dispose));
      await tester.runAsync(() => seedSquatScenario(harness));

      await tester.pumpWidget(
        trainingTestApp(
          brightness: brightness,
          home: ExerciseStatisticsScreen(
            repository: harness.repository,
            exerciseId: kneeExerciseId,
            initialTab: ExerciseStatisticsTab.records,
          ),
        ),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(ExerciseStatisticsScreen),
        matchesGoldenFile('goldens/exercise_statistics_records_$name.png'),
      );
    });
  }
}

void _phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
