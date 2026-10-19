import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gainer_mobile/data/repositories/body/body_repository.dart';
import 'package:gainer_mobile/data/repositories/cardio/cardio_preferences.dart';
import 'package:gainer_mobile/domain/models/body/body_tracking.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_draft.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_session.dart';
import 'package:gainer_mobile/ui/features/body/resting_history_card.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_feature.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_hrv_measurement_screen.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_live_screen.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_statistics_area.dart';
import 'package:gainer_mobile/ui/features/cardio/hrv_measurement_controller.dart';

import '../training/training_test_support.dart' hide testId;
import 'cardio_test_support.dart';

/// Mittwoch, 21.10.2026, lokal.
final _now = DateTime(2026, 10, 21, 12);

/// Wochenminuten im Zielbereich der letzten Wochen (älteste zuerst) und die
/// Leistung je Einheit, damit Balken, Ziellinie und Form-Verlauf Daten haben.
Future<void> _seedProgress(CardioHarness harness) async {
  await harness.repository.preferences.write(
    const CardioPreferenceValues(maxHeartRate: 180, restingHeartRate: 58),
  );
  final weeks = <(int, List<int>)>[
    (7, [60]),
    (6, [90, 40]),
    (5, [120]),
    (4, [150, 30]),
    (3, [100, 45]),
    (2, [130, 30]),
    (1, [110, 40, 20]),
    (0, [30, 35, 30]),
  ];
  var n = 0;
  for (final (back, lengths) in weeks) {
    final monday = DateTime(2026, 10, 19 - back * 7);
    for (final (i, minutes) in lengths.indexed) {
      final start = monday.add(Duration(days: i * 2, hours: 8));
      final bpm = 140 - (n * 11 % 9);
      final session = await harness.seedSession(
        start: start.toUtc(),
        length: Duration(minutes: minutes + 2),
        heartRate: [
          for (var s = 0; s < (minutes + 2) * 12 + 1; s++)
            s < minutes * 12 ? bpm - (s % 7) : 100,
        ],
      );
      if (n % 2 == 0) {
        await harness.repository.updateDetails(
          session.sessionId,
          averagePowerWatts: 150.0 + (n % 3) - 1,
        );
        await harness.repository.saveRecovery(
          session.sessionId,
          startBpm: 150,
          endBpm: 124 + (n % 4),
        );
      }
      n++;
    }
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  for (final brightness in [Brightness.light, Brightness.dark]) {
    final name = brightness.name;

    testWidgets('Statistik Cardio-Bereich $name', (tester) async {
      phoneSize(tester, height: 1000);
      final harness = await tester.runAsync(CardioHarness.create);
      addTearDown(() => tester.runAsync(harness!.dispose));
      await tester.runAsync(() => _seedProgress(harness!));
      await tester.pumpWidget(
        trainingTestApp(
          brightness: brightness,
          home: CupertinoPageScaffold(
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: CardioStatisticsArea(
                  repository: harness!.repository,
                  clock: () => _now,
                ),
              ),
            ),
          ),
        ),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(CupertinoApp),
        matchesGoldenFile('goldens/cardio_stats_$name.png'),
      );
    }, tags: ['golden']);
  }

  testWidgets('Statistik Cardio-Bereich Textgröße 2', (tester) async {
    phoneSize(tester, height: 1400);
    final harness = await tester.runAsync(CardioHarness.create);
    addTearDown(() => tester.runAsync(harness!.dispose));
    await tester.runAsync(() => _seedProgress(harness!));
    await tester.pumpWidget(
      trainingTestApp(
        textScale: 2,
        home: CupertinoPageScaffold(
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: CardioStatisticsArea(
                repository: harness!.repository,
                clock: () => _now,
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);

    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(CupertinoApp),
      matchesGoldenFile('goldens/cardio_stats_scale2_light.png'),
    );
  }, tags: ['golden']);

  testWidgets('Statistik Cardio-Bereich leer', (tester) async {
    phoneSize(tester, height: 500);
    final harness = await tester.runAsync(CardioHarness.create);
    addTearDown(() => tester.runAsync(harness!.dispose));
    await tester.pumpWidget(
      trainingTestApp(
        home: CupertinoPageScaffold(
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: CardioStatisticsArea(
                repository: harness!.repository,
                clock: () => _now,
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);

    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(CupertinoApp),
      matchesGoldenFile('goldens/cardio_stats_empty_light.png'),
    );
  }, tags: ['golden']);

  testWidgets('Live-Ansicht Erholung', (tester) async {
    phoneSize(tester);
    final start = DateTime.utc(2026, 10, 18, 10);
    final harness = await tester.runAsync(
      () => CardioHarness.create(now: start),
    );
    addTearDown(() => tester.runAsync(harness!.dispose));
    await tester.runAsync(() async {
      await harness!.controller.start(
        zone: const CardioTargetZone(lowBpm: 125, highBpm: 140),
      );
      final end = start.add(const Duration(minutes: 30));
      harness
        ..now = end
        ..platform.samples.add(
          CardioSample(
            sequence: 1,
            atUtc: end.subtract(const Duration(seconds: 2)),
            bpm: 152,
          ),
        );
      await harness.controller.poll();
      await harness.controller.finish();
      harness
        ..now = end.add(const Duration(seconds: 18))
        ..platform.latestBpm = 139
        ..platform.latestAt = harness.now;
      await harness.controller.poll();
    });
    await tester.pumpWidget(
      trainingTestApp(home: CardioLiveScreen(feature: harness!.feature)),
    );
    await pumpUi(tester);
    // Die Ansicht gehört zu einer gerade beendeten Einheit.
    expect(find.text('0:42'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(CardioLiveScreen),
      matchesGoldenFile('goldens/cardio_recovery_light.png'),
    );
  }, tags: ['golden']);

  group('HRV-Messung', () {
    late CardioHarness harness;
    late BodyRepository body;
    late HrvMeasurementController controller;
    final t0 = DateTime.utc(2026, 10, 21, 6, 30);

    Future<void> openScreen(
      WidgetTester tester, {
      Brightness brightness = Brightness.light,
      double textScale = 1,
      double height = 1500,
    }) async {
      phoneSize(tester, height: height);
      await tester.pumpWidget(
        trainingTestApp(
          brightness: brightness,
          textScale: textScale,
          home: HrvMeasurementScreen(
            feature: CardioFeature(
              repository: harness.repository,
              session: harness.controller,
              health: harness.feature.health,
              body: body,
            ),
            controller: controller,
          ),
        ),
      );
      await settle(tester);
    }

    Future<void> prepare(WidgetTester tester) async {
      harness = (await tester.runAsync(() => CardioHarness.create(now: t0)))!;
      var id = 600;
      body = BodyRepository(store: harness.store, ids: () => testId(id++));
      controller = HrvMeasurementController(
        platform: harness.platform,
        session: harness.controller,
        body: body,
        preferences: harness.repository.preferences,
        trainingPreferences: harness.controller.trainingPreferences,
        autoPoll: false,
        newId: () => 'hrv-1',
        clock: () => harness.now,
      );
      addTearDown(() async {
        controller.dispose();
        await tester.runAsync(harness.dispose);
      });
      await tester.runAsync(() async {
        for (var i = 0; i < 8; i++) {
          await body.saveCheckIn(
            localDate: '2026-10-${(12 + i).toString().padLeft(2, '0')}',
            weightKg: 70,
            caloriesKcal: null,
            proteinGrams: null,
            carbohydrateGrams: null,
            fatGrams: null,
            steps: null,
            sleepMinutes: null,
            restingHeartRateBpm: 62 - i % 4,
            restingHrvMs: 44 + (i * 3) % 11,
          );
        }
        await harness.repository.preferences.write(
          const CardioPreferenceValues(maxHeartRate: 180, hrvMinutes: 2),
        );
        await controller.load();
      });
    }

    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('Start ${brightness.name}', (tester) async {
        await prepare(tester);
        await openScreen(tester, brightness: brightness);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(HrvMeasurementScreen),
          matchesGoldenFile('goldens/hrv_idle_${brightness.name}.png'),
        );
      }, tags: ['golden']);
    }

    testWidgets('Start Textgröße 2', (tester) async {
      await prepare(tester);
      await openScreen(tester, textScale: 2, height: 2400);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(HrvMeasurementScreen),
        matchesGoldenFile('goldens/hrv_idle_scale2_light.png'),
      );
    }, tags: ['golden']);

    testWidgets('Messung läuft Textgröße 2', (tester) async {
      await prepare(tester);
      await openScreen(tester, textScale: 2, height: 900);
      await tester.runAsync(controller.start);
      harness.platform.samples.addAll([
        for (var i = 1; i <= 70; i++)
          CardioSample(
            sequence: i,
            atUtc: t0.add(Duration(seconds: i)),
            bpm: 57 + i % 3,
            rrIntervalsMs: [i.isEven ? 800 : 820],
          ),
      ]);
      harness.platform.latestBpm = 58;
      harness.platform.latestAt = t0.add(const Duration(seconds: 70));
      harness.now = t0.add(const Duration(seconds: 70));
      await tester.runAsync(controller.poll);
      await settle(tester);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(HrvMeasurementScreen),
        matchesGoldenFile('goldens/hrv_running_scale2_light.png'),
      );
    }, tags: ['golden']);

    testWidgets('Ergebnis dark', (tester) async {
      await prepare(tester);
      await openScreen(tester, brightness: Brightness.dark, height: 900);
      await tester.runAsync(controller.start);
      harness.platform.samples.addAll([
        for (var i = 1; i <= 160; i++)
          CardioSample(
            sequence: i,
            atUtc: t0.add(Duration(seconds: i)),
            bpm: 57 + i % 3,
            rrIntervalsMs: [i.isEven ? 800 : 820],
          ),
      ]);
      harness.now = t0.add(const Duration(seconds: 160));
      await tester.runAsync(controller.poll);
      await settle(tester);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(HrvMeasurementScreen),
        matchesGoldenFile('goldens/hrv_result_dark.png'),
      );
    }, tags: ['golden']);
  });

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('Ruhepuls und HRV im Körper-Tab ${brightness.name}', (
      tester,
    ) async {
      phoneSize(tester, height: 420);
      await tester.pumpWidget(
        trainingTestApp(
          brightness: brightness,
          home: CupertinoPageScaffold(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: RestingHistoryCard(
                  today: DateTime(2026, 10, 21),
                  onMeasure: () {},
                  entries: [
                    for (var i = 0; i < 14; i++)
                      RestingEntry(
                        localDate:
                            '2026-10-${(8 + i).toString().padLeft(2, '0')}',
                        restingHeartRateBpm: 62 - i % 5,
                        restingHrvMs: 40 + (i * 7) % 17,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(CupertinoApp),
        matchesGoldenFile('goldens/resting_history_${brightness.name}.png'),
      );
    }, tags: ['golden']);
  }
}
