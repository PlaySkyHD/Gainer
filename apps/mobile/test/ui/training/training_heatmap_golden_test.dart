import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/training_heatmap.dart';
import 'package:gainer_mobile/domain/models/training/training_schedule.dart';
import 'package:gainer_mobile/ui/core/theme.dart';
import 'package:gainer_mobile/ui/features/training/training_heatmap_card.dart';

import 'training_test_support.dart';

final _today = LocalDay(2026, 10, 22);

/// Ein Jahr mit wechselnden Trainingstagen und -längen, ohne Zufall.
TrainingHeatmap _yearOfTraining() => buildTrainingHeatmap(
  [
    for (var i = 0; i < 365; i++)
      if ((i * 7 + i ~/ 3) % 5 < 3 && i % 41 > 6)
        (
          startedAtUtc: DateTime.utc(
            _today.year,
            _today.month,
            _today.day - i,
            10,
          ),
          endedAtUtc: DateTime.utc(
            _today.year,
            _today.month,
            _today.day - i,
            10,
            20 + (i * 37) % 70,
          ),
        ),
  ],
  today: _today,
  // Fester Tag unabhängig von der Zeitzone des Testrechners.
  dayOf: (utc) => LocalDay.of(utc),
);

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    final name = brightness.name;

    testWidgets('Heatmap der Trainingstage $name', (tester) async {
      tester.view.physicalSize = const Size(390, 320);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final heatmap = _yearOfTraining();

      await tester.pumpWidget(
        trainingTestApp(
          brightness: brightness,
          home: CupertinoPageScaffold(
            child: Padding(
              padding: const EdgeInsets.all(GainerSpacing.m),
              child: Align(
                alignment: Alignment.topCenter,
                child: TrainingHeatmapCard(heatmap: heatmap, onOpenDay: (_) {}),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Dienstag, 13. Oktober wählen.
      final grid = tester.getRect(
        find.byKey(const ValueKey('training-heatmap-grid')),
      );
      final step = grid.width / heatmap.weeks.length;
      final cell = heatmap.cellOf(LocalDay(2026, 10, 13))!;
      await tester.tapAt(
        grid.topLeft +
            Offset((cell.week + 0.5) * step, (cell.weekday + 0.5) * step),
      );
      await tester.pumpAndSettle();
      expect(find.text('Di, 13. Okt. · 73 min'), findsOneWidget);

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(CupertinoPageScaffold),
        matchesGoldenFile('goldens/training_heatmap_$name.png'),
      );
    }, tags: ['golden']);
  }
}
