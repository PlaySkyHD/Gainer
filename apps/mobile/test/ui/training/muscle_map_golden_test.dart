import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/features/training/muscle_map_screen.dart';

import 'muscle_map_test_support.dart';
import 'training_plans_test_support.dart';
import 'training_test_support.dart';

/// Kantenglättung der Körperkarte weicht zwischen arm64 und x64 um einzelne
/// Pixel ab; mehr als ein winziger Anteil bleibt ein Fehler.
class _TolerantComparator extends LocalFileComparator {
  _TolerantComparator(super.testFile);

  static const _maxDiffPercent = 0.01;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent * 100 <= _maxDiffPercent) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}

void main() {
  setUpAll(() {
    final current = goldenFileComparator;
    if (current is LocalFileComparator) {
      goldenFileComparator = _TolerantComparator(
        current.basedir.resolve('muscle_map_golden_test.dart'),
      );
    }
  });

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
    }, tags: ['golden']);
  }
}
