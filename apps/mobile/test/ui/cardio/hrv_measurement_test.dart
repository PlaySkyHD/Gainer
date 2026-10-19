import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/body/body_repository.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_draft.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_feature.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_hrv_measurement_screen.dart';
import 'package:gainer_mobile/ui/features/cardio/hrv_measurement_controller.dart';

import '../training/training_test_support.dart' hide testId;
import 'cardio_test_support.dart';

void main() {
  late CardioHarness harness;
  late BodyRepository body;
  late HrvMeasurementController controller;
  final t0 = DateTime(2026, 10, 19, 6, 30);

  setUp(() async {
    harness = await CardioHarness.create(now: t0.toUtc());
    var id = 500;
    body = BodyRepository(
      store: harness.store,
      ids: () => testId(id++),
      clock: () => harness.now,
    );
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
  });

  tearDown(() async {
    controller.dispose();
    await harness.dispose();
  });

  CardioFeature feature() => CardioFeature(
    repository: harness.repository,
    session: harness.controller,
    health: harness.feature.health,
    body: body,
  );

  /// Ein Messwert je Sekunde mit einem RR-Wert; [noisyEvery] setzt Ausreißer.
  List<CardioSample> samples({
    required int seconds,
    int from = 1,
    int? noisyEvery,
  }) => [
    for (var i = from; i <= seconds; i++)
      CardioSample(
        sequence: i,
        atUtc: t0.toUtc().add(Duration(seconds: i)),
        bpm: 57 + (i % 3),
        rrIntervalsMs: [
          noisyEvery != null && i % noisyEvery == 0
              ? 1500
              : (i.isEven ? 800 : 820),
        ],
      ),
  ];

  Future<void> advance(Duration to) async {
    harness.now = t0.toUtc().add(to);
    await controller.poll();
  }

  group('Controller', () {
    test(
      'ohne Gurt oder bei laufender Einheit ist die Messung gesperrt',
      () async {
        harness.platform.connection = HeartRateConnectionState.idle;
        await harness.controller.refreshStatus();
        expect(controller.canStart, isFalse);
        expect(
          controller.blockedReason,
          'Für die Messung brauchst du einen verbundenen Pulsgurt.',
        );

        harness.platform.connection = HeartRateConnectionState.connected;
        await harness.controller.refreshStatus();
        expect(controller.canStart, isTrue);

        await harness.controller.start();
        expect(controller.canStart, isFalse);
        expect(controller.blockedReason, contains('Cardio-Einheit'));
        await controller.start();
        // Nur die Cardio-Einheit hat die Überwachung gestartet.
        expect(harness.platform.started, hasLength(1));
      },
    );

    test(
      'Messung: 30 s einschwingen, 2 min messen, speichern wartet',
      () async {
        await harness.controller.refreshStatus();
        await controller.start();
        final config = harness.platform.started.single;
        expect(config.sessionId, 'hrv-1');
        expect(config.alertsEnabled, isFalse);
        expect(config.liveActivityEnabled, isFalse);
        expect(config.zoneLowBpm, isNull);
        expect(controller.phase, HrvPhase.settling);
        expect(controller.duration, const Duration(minutes: 2));
        expect(controller.remaining, const Duration(seconds: 30));

        harness.platform.samples.addAll(samples(seconds: 20));
        harness.platform.latestBpm = 58;
        harness.platform.latestAt = t0.toUtc().add(const Duration(seconds: 20));
        await advance(const Duration(seconds: 20));
        expect(controller.phase, HrvPhase.settling);
        expect(controller.liveBpm, 58);
        // Das Einschwingen zählt nicht.
        expect(controller.validRrCount, 0);

        harness.platform.samples.addAll(samples(seconds: 70, from: 21));
        await advance(const Duration(seconds: 70));
        expect(controller.phase, HrvPhase.measuring);
        expect(controller.remaining, const Duration(seconds: 80));
        // Nur Werte ab Sekunde 30 zählen.
        expect(controller.validRrCount, 41);

        harness.platform.samples.addAll(samples(seconds: 160, from: 71));
        await advance(const Duration(seconds: 151));
        expect(controller.phase, HrvPhase.result);
        expect(harness.platform.stopped, ['hrv-1']);
        final result = controller.result!;
        expect(result.rmssdMs, 20);
        expect(result.restingHeartRateBpm, 58);
        expect(result.isNoisy, isFalse);
        expect(result.isStorable, isTrue);

        // Ohne Check-in des Tages wartet der Wert.
        expect(await controller.save(), isTrue);
        expect(controller.saved, RestingMeasurementStatus.pending);
        final snapshot = await body.read();
        expect(snapshot.pendingResting.single.localDate, '2026-10-19');
        expect(snapshot.pendingResting.single.restingHrvMs, 20);
      },
    );

    test('mit heutigem Check-in wird dieser korrigiert', () async {
      await body.saveCheckIn(
        localDate: '2026-10-19',
        weightKg: 71,
        caloriesKcal: null,
        proteinGrams: null,
        carbohydrateGrams: null,
        fatGrams: null,
        steps: null,
        sleepMinutes: null,
      );
      await harness.controller.refreshStatus();
      await controller.start();
      harness.platform.samples.addAll(samples(seconds: 160));
      await advance(const Duration(seconds: 160));
      expect(await controller.save(), isTrue);
      expect(controller.saved, RestingMeasurementStatus.savedToCheckIn);
      final value = (await body.read()).checkIns.single.value;
      expect((value.restingHeartRateBpm, value.restingHrvMs), (58, 20));
      expect(value.weightKg, 71);
      // Zweimal speichern ist nicht möglich.
      expect(await controller.save(), isFalse);
    });

    test(
      'unruhige Messung ist erkennbar, Abbrechen speichert nichts',
      () async {
        await harness.controller.refreshStatus();
        await controller.start();
        harness.platform.samples.addAll(samples(seconds: 160, noisyEvery: 4));
        await advance(const Duration(seconds: 160));
        expect(controller.result!.isNoisy, isTrue);

        await controller.repeat();
        expect(controller.phase, HrvPhase.settling);
        await controller.cancel();
        expect(controller.phase, HrvPhase.idle);
        expect(harness.platform.stopped, ['hrv-1', 'hrv-1']);
        expect((await body.read()).pendingResting, isEmpty);
      },
    );

    test('zu wenige Werte ergeben ein nicht speicherbares Ergebnis', () async {
      await harness.controller.refreshStatus();
      await controller.start();
      harness.platform.samples.addAll(samples(seconds: 50));
      await advance(const Duration(seconds: 160));
      expect(controller.result!.isStorable, isFalse);
      expect(await controller.save(), isFalse);
    });

    test('Messdauer wird gemerkt und begrenzt', () async {
      await controller.setMinutes(5);
      expect(controller.duration, const Duration(minutes: 5));
      await controller.setMinutes(9);
      expect(controller.duration, const Duration(minutes: 5));
      final stored = await harness.repository.preferences.read();
      expect(stored.hrvMinutes, 5);
    });

    test('Als Ruhepuls übernehmen: Median der letzten 7 Messungen', () async {
      // Acht Tage; der älteste (90) zählt nicht, Median der übrigen sieben: 58.
      final rates = [90, 55, 56, 57, 58, 59, 60, 61];
      for (var i = 0; i < rates.length; i++) {
        final date = '2026-10-${(10 + i).toString().padLeft(2, '0')}';
        await body.saveCheckIn(
          localDate: date,
          weightKg: 70,
          caloriesKcal: null,
          proteinGrams: null,
          carbohydrateGrams: null,
          fatGrams: null,
          steps: null,
          sleepMinutes: null,
          restingHeartRateBpm: rates[i],
          restingHrvMs: 50,
        );
      }
      await controller.load();
      expect(controller.medianSampleCount, 7);
      expect(controller.medianRestingHeartRate, 58);
      expect(controller.canAdopt, isTrue);
      expect(await controller.adoptRestingHeartRate(), isTrue);
      final prefs = await harness.repository.preferences.read();
      expect(prefs.restingHeartRate, 58);
      // Die Zonen rechnen nach Karvonen mit Ruhepuls 58.
      expect(prefs.copyWith(maxHeartRate: () => 180).zones.first.lowBpm, 119);
    });
  });

  group('Screen', () {
    Future<void> open(
      WidgetTester tester, {
      double textScale = 1,
      Brightness brightness = Brightness.light,
    }) async {
      phoneSize(tester, height: 1400);
      await tester.pumpWidget(
        trainingTestApp(
          textScale: textScale,
          brightness: brightness,
          home: HrvMeasurementScreen(
            feature: feature(),
            controller: controller,
          ),
        ),
      );
      await settle(tester);
    }

    testWidgets('ohne Gurt ist „Messung starten“ deaktiviert und erklärt', (
      tester,
    ) async {
      harness.platform.connection = HeartRateConnectionState.idle;
      await open(tester);

      expect(find.text('Messung starten'), findsOneWidget);
      expect(
        find.text('Für die Messung brauchst du einen verbundenen Pulsgurt.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('hrv-start')));
      await pumpUi(tester);
      expect(harness.platform.started, isEmpty);
      // Weg zum Verbinden: Gurt suchen.
      expect(find.byKey(const ValueKey('cardio-scan')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('bei laufender Cardio-Einheit gesperrt mit Begründung', (
      tester,
    ) async {
      await tester.runAsync(harness.controller.start);
      await open(tester);
      expect(find.byKey(const ValueKey('hrv-blocked')), findsOneWidget);
      expect(
        find.textContaining('Während einer Cardio-Einheit'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('hrv-start')));
      await pumpUi(tester);
      expect(harness.platform.started, hasLength(1));
      expect(find.byKey(const ValueKey('cardio-scan')), findsNothing);
    });

    testWidgets('Messung läuft mit Countdown, Puls und RR-Zähler', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('2 min'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('hrv-start')));
      await pumpUi(tester);

      expect(find.text('Einschwingen'), findsOneWidget);
      expect(find.text('0:30'), findsOneWidget);
      harness.platform.samples.addAll(samples(seconds: 60));
      harness.platform.latestBpm = 58;
      harness.platform.latestAt = t0.toUtc().add(const Duration(seconds: 60));
      harness.now = t0.toUtc().add(const Duration(seconds: 60));
      await tester.runAsync(controller.poll);
      await tester.pump();
      expect(find.text('Messung läuft'), findsOneWidget);
      expect(find.text('1:30'), findsOneWidget);
      expect(find.text('58 bpm'), findsOneWidget);
      expect(find.text('Gültige RR-Werte: 31'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('hrv-cancel')));
      await pumpUi(tester);
      expect(find.text('Messung starten'), findsOneWidget);
      expect(harness.platform.stopped, ['hrv-1']);
    });

    testWidgets('Ergebnis speichern zeigt „wartet auf Check-in“', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('hrv-start')));
      await pumpUi(tester);
      harness.platform.samples.addAll(samples(seconds: 160));
      harness.now = t0.toUtc().add(const Duration(seconds: 160));
      await tester.runAsync(controller.poll);
      await tester.pump();

      expect(find.text('Ergebnis'), findsOneWidget);
      expect(find.text('58 bpm'), findsOneWidget);
      expect(find.text('20 ms'), findsOneWidget);
      expect(find.text('0 %'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('hrv-save')));
      await pumpUi(tester);
      expect(find.byKey(const ValueKey('hrv-saved')), findsOneWidget);
      expect(find.textContaining('wartet auf deinen Check-in'), findsOneWidget);
    });

    testWidgets('unruhige Messung fragt nach: Trotzdem speichern', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('hrv-start')));
      await pumpUi(tester);
      harness.platform.samples.addAll(samples(seconds: 160, noisyEvery: 4));
      harness.now = t0.toUtc().add(const Duration(seconds: 160));
      await tester.runAsync(controller.poll);
      await pumpUi(tester);

      expect(find.text('Messung unruhig – wiederholen?'), findsOneWidget);
      expect(inDialog('Wiederholen'), findsOneWidget);
      await tester.tap(inDialog('Trotzdem speichern'));
      await pumpUi(tester);
      expect(controller.saved, isNotNull);
      expect(find.byKey(const ValueKey('hrv-saved')), findsOneWidget);
    });

    testWidgets('unruhige Messung: Wiederholen startet neu', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('hrv-start')));
      await pumpUi(tester);
      harness.platform.samples.addAll(samples(seconds: 160, noisyEvery: 4));
      harness.now = t0.toUtc().add(const Duration(seconds: 160));
      await tester.runAsync(controller.poll);
      await pumpUi(tester);

      await tester.tap(inDialog('Wiederholen'));
      await pumpUi(tester);
      expect(controller.phase, HrvPhase.settling);
      expect(harness.platform.started, hasLength(2));
      expect(await tester.runAsync(body.read), isNotNull);
      expect((await tester.runAsync(body.read))!.pendingResting, isEmpty);
    });

    testWidgets('Ruhepuls übernehmen setzt den Wert für die Zonen', (
      tester,
    ) async {
      await tester.runAsync(() async {
        for (var i = 0; i < 3; i++) {
          await body.saveCheckIn(
            localDate: '2026-10-1${i + 1}',
            weightKg: 70,
            caloriesKcal: null,
            proteinGrams: null,
            carbohydrateGrams: null,
            fatGrams: null,
            steps: null,
            sleepMinutes: null,
            restingHeartRateBpm: 56 + i * 2,
            restingHrvMs: 50,
          );
        }
        await controller.load();
      });
      await open(tester);
      expect(find.text('Median Ruhepuls'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('hrv-adopt')));
      await pumpUi(tester);
      expect(
        find.text('Ruhepuls 58 bpm für die Zonen übernommen.'),
        findsOneWidget,
      );
      final prefs = await tester.runAsync(harness.repository.preferences.read);
      expect(prefs!.restingHeartRate, 58);
    });

    testWidgets('ohne Messungen ist „Als Ruhepuls übernehmen“ deaktiviert', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('hrv-adopt')));
      await pumpUi(tester);
      expect(find.textContaining('übernommen.'), findsNothing);
      expect(
        find.textContaining('Nach der ersten gespeicherten Messung'),
        findsOneWidget,
      );
    });

    testWidgets('Textgröße 2 läuft nicht über', (tester) async {
      await open(tester, textScale: 2);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('hrv-start')));
      await pumpUi(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
