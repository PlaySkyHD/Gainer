import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/features/training/training_analysis_screen.dart';

import 'training_analysis_test_support.dart';
import 'training_plans_test_support.dart' show usePhoneSize;
import 'training_test_support.dart';

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    final name = brightness.name;

    testWidgets('Trainingsanalyse $name', (tester) async {
      usePhoneSize(tester);
      final harness = await tester.runAsync(
        () => TrainingHarness.create(now: analysisNow),
      );
      if (harness == null) throw StateError('Harness nicht erstellt.');
      addTearDown(() => tester.runAsync(harness.dispose));
      await tester.runAsync(() => seedAnalysisScenario(harness));

      await tester.pumpWidget(
        trainingTestApp(
          brightness: brightness,
          home: TrainingAnalysisScreen(repository: harness.repository),
        ),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(TrainingAnalysisScreen),
        matchesGoldenFile('goldens/training_analysis_$name.png'),
      );

      await tester.tap(
        find.byKey(const ValueKey('analysis-exercise-$analysisDeadliftId')),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(TrainingAnalysisExerciseScreen),
        matchesGoldenFile('goldens/training_analysis_exercise_$name.png'),
      );
    }, tags: ['golden']);
  }
}
