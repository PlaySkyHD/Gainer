import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/cardio/cardio_preferences.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_session.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_detail_screen.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_live_screen.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_settings_screen.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_start_sheet.dart';
import 'package:gainer_mobile/ui/features/training/active_workout_controller.dart';
import 'package:gainer_mobile/ui/features/training/training_home_screen.dart';

import '../training/training_test_support.dart';
import 'cardio_test_support.dart';

/// Pulsverlauf einer Einheit: Aufwärmen, Block im Zielbereich, kurze Lücke,
/// Ausreißer nach oben und Ausfahren.
List<int> _curve() {
  final values = <int>[];
  for (var i = 0; i < 360; i++) {
    final base = switch (i) {
      < 36 => 95 + i,
      < 200 => 128 + (i % 14),
      < 212 => 0,
      < 240 => 142 + (i % 6),
      _ => 132 - (i - 240) ~/ 8 + (i % 5),
    };
    values.add(base);
  }
  return values;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  for (final brightness in [Brightness.light, Brightness.dark]) {
    final name = brightness.name;

    testWidgets('Live-Ansicht im Zielbereich $name', (tester) async {
      phoneSize(tester);
      final harness = await tester.runAsync(
        () => CardioHarness.create(now: DateTime.utc(2026, 10, 18, 10)),
      );
      addTearDown(() => tester.runAsync(harness!.dispose));
      await tester.runAsync(() async {
        await harness!.controller.start(
          zone: const CardioTargetZone(lowBpm: 125, highBpm: 140),
        );
        harness
          ..now = DateTime.utc(2026, 10, 18, 10, 12, 34)
          ..platform.latestBpm = 131
          ..platform.latestAt = DateTime.utc(2026, 10, 18, 10, 12, 34);
        await harness.controller.poll();
      });
      await tester.pumpWidget(
        trainingTestApp(
          brightness: brightness,
          home: CardioLiveScreen(feature: harness!.feature),
        ),
      );
      await pumpUi(tester);

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(CardioLiveScreen),
        matchesGoldenFile('goldens/cardio_live_$name.png'),
      );
    }, tags: ['golden']);

    testWidgets('Detailansicht $name', (tester) async {
      phoneSize(tester, height: 1500);
      final harness = await tester.runAsync(CardioHarness.create);
      addTearDown(() => tester.runAsync(harness!.dispose));
      final session = await tester.runAsync(
        () => harness!.seedSession(
          start: DateTime(2026, 10, 18, 9, 30).toUtc(),
          length: const Duration(minutes: 30),
          heartRate: _curve(),
          zone: const CardioTargetZone(lowBpm: 125, highBpm: 140),
          rr: [for (var i = 0; i < 80; i++) 780 + (i % 4) * 12],
        ),
      );
      await tester.runAsync(
        () => harness!.repository.updateDetails(
          session!.sessionId,
          distanceKm: 14.2,
          averagePowerWatts: 165,
          notes: 'Locker gefahren, Gurt saß gut.',
        ),
      );
      await tester.pumpWidget(
        trainingTestApp(
          brightness: brightness,
          home: CardioDetailScreen(
            feature: harness!.feature,
            sessionId: session!.sessionId,
          ),
        ),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(CardioDetailScreen),
        matchesGoldenFile('goldens/cardio_detail_$name.png'),
      );
    }, tags: ['golden']);

    testWidgets('Tagebuch mit Cardio $name', (tester) async {
      phoneSize(tester);
      final training = await tester.runAsync(TrainingHarness.create);
      final cardio = await tester.runAsync(CardioHarness.create);
      final active = ActiveWorkoutController(training!.repository);
      addTearDown(active.dispose);
      addTearDown(() => tester.runAsync(training.dispose));
      addTearDown(() => tester.runAsync(cardio!.dispose));
      await tester.runAsync(() async {
        await training.seedWorkout(
          title: 'Push',
          start: DateTime(2026, 10, 2, 7).toUtc(),
          end: DateTime(2026, 10, 2, 8, 2).toUtc(),
          blocks: [strengthBlock('Bankdrücken', 3, id: 'push')],
        );
        await cardio!.seedSession(
          start: DateTime(2026, 10, 18, 9).toUtc(),
          length: const Duration(minutes: 30),
          heartRate: [
            ...List.filled(78, 132),
            ...List.filled(11, 100),
            ...List.filled(11, 164),
          ],
        );
        await cardio.seedSession(
          start: DateTime(2026, 10, 11, 18).toUtc(),
          length: const Duration(minutes: 45),
          heartRate: List.filled(10, 0),
        );
      });
      await tester.pumpWidget(
        trainingTestApp(
          brightness: brightness,
          home: TrainingHomeScreen(
            repository: training.repository,
            activeWorkout: active,
            cardio: cardio!.feature,
          ),
        ),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(TrainingHomeScreen),
        matchesGoldenFile('goldens/cardio_diary_$name.png'),
      );
    }, tags: ['golden']);
  }

  testWidgets('Live-Ansicht zu hoch, Textgröße 2', (tester) async {
    phoneSize(tester);
    final harness = await tester.runAsync(
      () => CardioHarness.create(now: DateTime.utc(2026, 10, 18, 10)),
    );
    addTearDown(() => tester.runAsync(harness!.dispose));
    await tester.runAsync(() async {
      await harness!.controller.start(
        zone: const CardioTargetZone(lowBpm: 125, highBpm: 140),
      );
      harness
        ..now = DateTime.utc(2026, 10, 18, 11, 5, 9)
        ..platform.latestBpm = 188
        ..platform.latestAt = DateTime.utc(2026, 10, 18, 11, 5, 9);
      await harness.controller.poll();
    });
    await tester.pumpWidget(
      trainingTestApp(
        textScale: 2,
        home: CardioLiveScreen(feature: harness!.feature),
      ),
    );
    await pumpUi(tester);

    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(CardioLiveScreen),
      matchesGoldenFile('goldens/cardio_live_scale2_light.png'),
    );
  }, tags: ['golden']);

  for (final (label, scale, brightness) in [
    ('', 1.0, Brightness.light),
    ('', 1.0, Brightness.dark),
    ('_scale2', 2.0, Brightness.light),
  ]) {
    testWidgets('Start-Sheet ${brightness.name}$label', (tester) async {
      phoneSize(tester);
      final harness = await tester.runAsync(CardioHarness.create);
      addTearDown(() => tester.runAsync(harness!.dispose));
      await tester.runAsync(
        () => harness!.repository.preferences.write(
          const CardioPreferenceValues(maxHeartRate: 190),
        ),
      );
      await tester.pumpWidget(
        trainingTestApp(
          brightness: brightness,
          textScale: scale,
          home: Builder(
            builder: (context) => CupertinoPageScaffold(
              child: Center(
                child: CupertinoButton(
                  onPressed: () =>
                      showCardioStartSheet(context, harness!.feature),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await pumpUi(tester);

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(CupertinoApp),
        matchesGoldenFile('goldens/cardio_start_${brightness.name}$label.png'),
      );
    }, tags: ['golden']);
  }

  testWidgets('Cardio-Einstellungen light', (tester) async {
    phoneSize(tester, height: 1100);
    final harness = await tester.runAsync(CardioHarness.create);
    addTearDown(() => tester.runAsync(harness!.dispose));
    await tester.runAsync(
      () => harness!.repository.preferences.write(
        const CardioPreferenceValues(age: 40, restingHeartRate: 58),
      ),
    );
    await tester.pumpWidget(
      trainingTestApp(
        home: CardioSettingsScreen(
          preferences: harness!.repository.preferences,
        ),
      ),
    );
    await settle(tester);

    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(CardioSettingsScreen),
      matchesGoldenFile('goldens/cardio_settings_light.png'),
    );
  }, tags: ['golden']);
}
