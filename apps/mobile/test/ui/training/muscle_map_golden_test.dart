import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/features/training/muscle_map_screen.dart';

import 'muscle_map_test_support.dart';
import 'training_plans_test_support.dart';
import 'training_test_support.dart';

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('Muskelübersicht ${brightness.name}', (tester) async {
      usePhoneSize(tester);
      final harness = await tester.runAsync(
        () => TrainingHarness.create(now: DateTime.utc(2026, 10, 20, 9)),
      );
      if (harness == null) throw StateError('Harness nicht erstellt.');
      addTearDown(() => tester.runAsync(harness.dispose));
      await tester.runAsync(() => seedMuscleScenario(harness));

      await tester.pumpWidget(
        trainingTestApp(
          brightness: brightness,
          home: MuscleMapScreen(repository: harness.repository),
        ),
      );
      await settle(tester);

      await expectLater(
        find.byType(MuscleMapScreen),
        matchesGoldenFile('goldens/muscle_map_${brightness.name}.png'),
      );
    });
  }
}
