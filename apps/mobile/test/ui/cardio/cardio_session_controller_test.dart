import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/cardio/cardio_preferences.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/repositories/training/training_preferences.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_draft.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_session.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_template.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_session_controller.dart';

import 'cardio_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalDatabase database;
  late LocalSyncStore store;
  late FlakyCardioRepository repository;
  late FakeHeartRate platform;
  late FakeNotifications notifications;
  late TrainingPreferences trainingPreferences;
  final t0 = DateTime.utc(2026, 10, 18, 10);
  late DateTime now;
  var nextId = 100;
  final controllers = <CardioSessionController>[];

  CardioSessionController newController() {
    final controller = CardioSessionController(
      repository: repository,
      platform: platform,
      notifications: notifications,
      trainingPreferences: trainingPreferences,
      autoPoll: false,
      clock: () => now,
    );
    controllers.add(controller);
    return controller;
  }

  CardioSample sample(int seq, int seconds, int bpm, [List<int>? rr]) =>
      CardioSample(
        sequence: seq,
        atUtc: t0.add(Duration(seconds: seconds)),
        bpm: bpm,
        rrIntervalsMs: rr ?? const [],
      );

  setUp(() {
    database = LocalDatabase(NativeDatabase.memory());
    store = LocalSyncStore(database: database, accountId: accountId);
    nextId = 100;
    now = t0;
    repository = FlakyCardioRepository(
      store: store,
      ids: () => testId(nextId++),
      clock: () => now,
    );
    platform = FakeHeartRate();
    notifications = FakeNotifications();
    trainingPreferences = TrainingPreferences(store: store);
  });

  tearDown(() async {
    for (final controller in controllers) {
      controller.dispose();
    }
    controllers.clear();
    await database.close();
  });

  test('start, samples become buckets, finish saves the session', () async {
    final controller = newController();
    const zone = CardioTargetZone(lowBpm: 120, highBpm: 140);
    final draft = await controller.start(zone: zone, warmupSeconds: 60);
    expect(controller.isRunning, isTrue);
    expect(notifications.requests, 1);
    final config = platform.started.single;
    expect(config.sessionId, draft.sessionId);
    expect(config.title, 'Rad-Ergometer');
    expect(config.graceSeconds, 15);
    expect(config.repeatSeconds, 60);
    expect(config.warmupSeconds, 60);
    expect(config.zoneLowBpm, 120);
    // Ohne Gurt keine Alarme, sonst käme nach 30 s „Kein Pulssignal“.
    expect(config.alertsEnabled, isFalse);
    expect(config.soundId, trainingPreferences.timerSoundId.value);
    expect(await repository.readDraft(), isNotNull);
    // Nur eine laufende Einheit.
    expect((await controller.start()).sessionId, draft.sessionId);
    expect(platform.started, hasLength(1));

    platform.samples.addAll([
      sample(1, 1, 100, [800, 810]),
      sample(2, 3, 111),
      sample(3, 6, 130),
      sample(4, 16, 140),
    ]);
    platform.latestBpm = 145;
    platform.latestAt = t0.add(const Duration(seconds: 16));
    now = t0.add(const Duration(seconds: 20));
    await controller.poll();
    expect(controller.active!.buckets, [106, 130, 0, 140]);
    expect(controller.liveBpm, 145);
    expect(controller.zoneState, HeartRateZoneState.above);
    expect(controller.elapsed, const Duration(seconds: 20));
    expect(controller.sensorName, 'Polar H10');
    expect(controller.batteryPercent, 80);
    final analysis = controller.currentAnalysis!;
    expect(analysis.maxBpm, 140);
    expect(analysis.timeInZone, const Duration(seconds: 10));
    // Spätestens alle 5 s gesichert; hier wurde nach dem Start gesichert.
    now = t0.add(const Duration(seconds: 23));
    final session = await controller.finish();
    expect(controller.isRunning, isFalse);
    expect(session.heartRateBpm, [106, 130, 0, 140]);
    expect(session.rrIntervalsMs, [800, 810]);
    expect(session.targetZone, zone);
    expect(session.sensorName, 'Polar H10');
    expect(session.endedAtUtc, t0.add(const Duration(seconds: 23)));
    // Mit Pulssignal läuft die Erholung weiter; erst „Überspringen“ stoppt.
    expect(controller.isRecovering, isTrue);
    expect(platform.stopped, isEmpty);
    await controller.skipRecovery();
    expect(platform.stopped, [draft.sessionId]);
    expect(await repository.readDraft(), isNull);
    expect((await repository.readSessions()).single.sessionId, draft.sessionId);
    final prefs = await repository.preferences.read();
    expect((prefs.lastZoneLow, prefs.lastZoneHigh), (120, 140));
    expect(prefs.warmupSeconds, 60);
  });

  test('two starts at the same time share one session', () async {
    final controller = newController();
    const zone = CardioTargetZone(lowBpm: 120, highBpm: 140);
    final drafts = await Future.wait([
      controller.start(zone: zone),
      controller.start(zone: zone),
    ]);

    expect(drafts.first.sessionId, drafts.last.sessionId);
    expect(platform.started, hasLength(1));
  });

  test('signal timeout hides live bpm', () async {
    final controller = newController();
    await controller.start();
    platform.latestBpm = 130;
    platform.latestAt = t0;
    now = t0.add(const Duration(seconds: 30));
    await controller.poll();
    expect(controller.liveBpm, isNull);
    expect(controller.zoneState, HeartRateZoneState.noSignal);
  });

  test('resume restarts native monitoring and reconnects the sensor', () async {
    final first = newController();
    final draft = await first.start(
      zone: const CardioTargetZone(lowBpm: 120, highBpm: 140),
      sensor: const HeartRateSensor(
        id: 'sensor-1',
        name: 'Polar H10',
        isConnected: false,
      ),
    );
    platform.samples.add(sample(1, 2, 120));
    now = t0.add(const Duration(seconds: 6));
    await first.poll();
    await first.close();
    first.dispose();
    // App neu gestartet: native Überwachung weg, Sequenzen leer.
    platform.monitoring = null;
    platform.samples.clear();
    platform.connection = HeartRateConnectionState.idle;
    platform.started.clear();
    platform.connected.clear();
    final second = newController();
    await second.load();
    expect(second.active!.sessionId, draft.sessionId);
    expect(second.active!.buckets, [120]);
    expect(platform.started.single.sessionId, draft.sessionId);
    expect(platform.started.single.startedAtUtc, draft.startedAtUtc);
    expect(platform.connected, contains('sensor-1'));
    // Neue Sequenzen ab 1 werden wieder aufgenommen.
    platform.samples.add(sample(1, 7, 100));
    now = t0.add(const Duration(seconds: 17));
    await second.poll();
    expect(second.active!.buckets, [120, 100, 0]);
  });

  test('zone update pushes config and persists the zone', () async {
    final controller = newController();
    await controller.start(
      zone: const CardioTargetZone(lowBpm: 125, highBpm: 140),
    );
    await controller.updateZone(
      const CardioTargetZone(lowBpm: 130, highBpm: 145),
    );
    expect(platform.updated.single.zoneLowBpm, 130);
    expect(platform.updated.single.zoneHighBpm, 145);
    expect((await repository.readDraft())!.targetZone!.highBpm, 145);
    expect(
      () => controller.updateZone(
        const CardioTargetZone(lowBpm: 150, highBpm: 140),
      ),
      throwsArgumentError,
    );
    final session = await controller.finish();
    expect(session.targetZone!.lowBpm, 130);
  });

  test('discard drops the draft without saving', () async {
    final controller = newController();
    final draft = await controller.start();
    await controller.discard();
    expect(controller.isRunning, isFalse);
    expect(await repository.readDraft(), isNull);
    expect(await repository.readSessions(), isEmpty);
    expect(platform.stopped, [draft.sessionId]);
  });

  test('scan reports bluetooth problems without throwing', () async {
    final controller = newController();
    expect(await controller.scan(), hasLength(1));
    platform.problem = BluetoothProblem.poweredOff;
    expect(await controller.scan(), isEmpty);
    expect(controller.bluetoothProblem, BluetoothProblem.poweredOff);
    expect(await controller.connect('sensor-1'), isFalse);
  });

  test('forget disconnects the stored sensor', () async {
    final controller = newController();
    await controller.forget();
    expect(platform.disconnects, 1);
  });

  group('Beenden nach Teilfehler', () {
    test('scheitert das Löschen des Entwurfs, ist die Einheit trotzdem '
        'beendet und der nächste Start verwirft den Rest', () async {
      final controller = newController();
      final draft = await controller.start();
      now = t0.add(const Duration(minutes: 5));
      repository.clearDraftFailures = 1;

      final session = await controller.finish();

      expect(session.sessionId, draft.sessionId);
      expect(controller.isRunning, isFalse);
      expect(platform.stopped, [draft.sessionId]);
      // Der Entwurf blieb liegen; der nächste Start verwirft ihn.
      expect(await repository.readDraft(), isNotNull);
      final next = newController();
      await next.load();
      expect(next.isRunning, isFalse);
      expect(await repository.readDraft(), isNull);
      expect(
        (await repository.readSessions()).single.sessionId,
        draft.sessionId,
      );
    });

    test('eine schon gespeicherte Einheit gilt beim Beenden als '
        'gespeichert', () async {
      final controller = newController();
      final draft = await controller.start();
      now = t0.add(const Duration(minutes: 5));
      // Ein früherer Versuch hat gespeichert, aber den Entwurf nicht gelöscht.
      await repository.saveFinished(
        CardioSession(
          sessionId: draft.sessionId,
          startedAtUtc: draft.startedAtUtc,
          endedAtUtc: now,
          heartRateBpm: const [],
          rrIntervalsMs: const [],
          createdAtUtc: now,
          updatedAtUtc: now,
        ),
      );

      final session = await controller.finish();

      expect(session.sessionId, draft.sessionId);
      expect(controller.isRunning, isFalse);
      expect(await repository.readDraft(), isNull);
      expect(await repository.readSessions(), hasLength(1));
    });

    test('eine gespeicherte und danach gelöschte Einheit wird nicht '
        'wiederbelebt', () async {
      final controller = newController();
      final draft = await controller.start();
      // Mit Puls vor dem Beenden gäbe es sonst eine Erholung.
      platform.samples.add(sample(1, 295, 150));
      platform.latestBpm = 150;
      platform.latestAt = t0.add(const Duration(seconds: 295));
      now = t0.add(const Duration(minutes: 5));
      await saveSyncedThenDelete(
        repository,
        CardioSession(
          sessionId: draft.sessionId,
          startedAtUtc: draft.startedAtUtc,
          endedAtUtc: now,
          heartRateBpm: const [],
          rrIntervalsMs: const [],
          createdAtUtc: now,
          updatedAtUtc: now,
        ),
      );

      await expectLater(
        controller.finish(),
        throwsA(isA<CardioSessionDeletedException>()),
      );

      expect(controller.isRunning, isFalse);
      expect(controller.isRecovering, isFalse);
      expect(await repository.readDraft(), isNull);
      expect(await repository.readSessions(), isEmpty);
      expect(platform.stopped, [draft.sessionId]);
    });

    test('Rückkehr in die App während des Beendens lässt keinen Timer '
        'zurück', () async {
      final controller = CardioSessionController(
        repository: repository,
        platform: platform,
        notifications: notifications,
        trainingPreferences: trainingPreferences,
        pollInterval: const Duration(milliseconds: 10),
        clock: () => now,
      );
      controllers.add(controller);
      final binding = TestWidgetsFlutterBinding.instance;
      await controller.start();
      expect(controller.hasPollTimer, isTrue);
      now = t0.add(const Duration(minutes: 5));
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(controller.hasPollTimer, isFalse);

      // Beenden hängt in der letzten Abfrage, die App kommt zurück.
      final gate = platform.statusGate = Completer<void>();
      final finishing = controller.finish();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(controller.hasPollTimer, isTrue);
      platform.statusGate = null;
      gate.complete();
      await finishing;

      expect(controller.isRunning, isFalse);
      expect(controller.isRecovering, isFalse);
      expect(controller.hasPollTimer, isFalse);
    });

    test('Beenden wartet auf eine laufende Abfrage', () async {
      final controller = newController();
      final draft = await controller.start();
      now = t0.add(const Duration(minutes: 2));
      platform.samples.add(sample(1, 100, 130));
      final gate = platform.statusGate = Completer<void>();
      final polling = controller.poll();
      var finished = false;
      final finishing = controller.finish().whenComplete(() => finished = true);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(finished, isFalse);

      platform.statusGate = null;
      gate.complete();
      await polling;
      final session = await finishing;
      expect(session.sessionId, draft.sessionId);
      expect(session.heartRateBpm, contains(130));
      expect(controller.isRunning, isFalse);
      expect(await repository.readDraft(), isNull);
    });

    test('Verwerfen wartet auf eine laufende Abfrage', () async {
      final controller = newController();
      final draft = await controller.start();
      final gate = platform.statusGate = Completer<void>();
      final polling = controller.poll();
      var discarded = false;
      final discarding = controller.discard().whenComplete(
        () => discarded = true,
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(discarded, isFalse);
      // Schon während des Wartens gilt die Einheit als beendet.
      expect(controller.isRunning, isFalse);

      platform.statusGate = null;
      gate.complete();
      await polling;
      await discarding;
      expect(await repository.readDraft(), isNull);
      expect(platform.stopped, [draft.sessionId]);
    });
  });

  test(
    'ein zweiter Beobachter stoppt beim Schließen nicht den ersten',
    () async {
      final controller = CardioSessionController(
        repository: repository,
        platform: platform,
        notifications: notifications,
        trainingPreferences: trainingPreferences,
        pollInterval: const Duration(milliseconds: 10),
        clock: () => now,
      );
      controllers.add(controller);
      await controller.watch(); // Start-Sheet
      await controller.watch(); // HRV-Messung darüber
      controller.stopWatching(); // HRV-Messung geschlossen

      final before = platform.statusReads;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(platform.statusReads, greaterThan(before));

      controller.stopWatching(); // Start-Sheet geschlossen
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final stopped = platform.statusReads;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(platform.statusReads, stopped);
    },
  );

  test(
    'Live Activity aus: Zustand melden und nach Rückkehr neu starten',
    () async {
      final controller = newController();
      platform.liveActivity = CardioLiveActivityState.disabled;
      final draft = await controller.start();
      await controller.poll();
      expect(controller.liveActivitiesOff, isTrue);
      expect(platform.updated, isEmpty);

      // Live Activities in den Einstellungen eingeschaltet, zurück in die App.
      platform.liveActivity = CardioLiveActivityState.missing;
      final binding = TestWidgetsFlutterBinding.instance;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await controller.poll();

      expect(controller.liveActivitiesOff, isFalse);
      final retry = platform.updated.single;
      expect(retry.sessionId, draft.sessionId);
      expect(retry.liveActivityEnabled, isTrue);
      expect(retry.startedAtUtc, draft.startedAtUtc);

      // Nur einmal je Rückkehr, nicht bei jeder Abfrage.
      await controller.poll();
      expect(platform.updated, hasLength(1));
    },
  );

  test('eine weggewischte Live Activity startet nicht erneut', () async {
    await newController().start();
    platform.liveActivity = CardioLiveActivityState.dismissed;

    // Wiederherstellen prüft die Live Activity wie die Rückkehr in die App.
    final controller = newController();
    await controller.load();

    expect(controller.isRunning, isTrue);
    expect(platform.updated, isEmpty);
    expect(controller.liveActivitiesOff, isFalse);
  });

  test(
    'Kaltstart: restored ist fertig, sobald der Entwurf gelesen ist',
    () async {
      final first = newController();
      final draft = await first.start();
      await first.close();
      platform.monitoring = null;

      final second = newController();
      final gate = platform.statusGate = Completer<void>();
      final loading = second.load();
      await second.restored;
      // Die Abfrage hängt noch, die Einheit ist aber schon bekannt.
      expect(second.isRunning, isTrue);
      expect(second.active!.sessionId, draft.sessionId);
      platform.statusGate = null;
      gate.complete();
      await loading;
    },
  );

  group('Vorlage mit Zone 5', () {
    const template = CardioTemplate(
      id: 'tpl-z5',
      name: 'Spitze',
      phases: [
        CardioTemplatePhase(
          name: 'Hart',
          durationSeconds: 60,
          target: CardioZoneTarget(5),
        ),
      ],
    );

    test('startet auch mit einem Maximalpuls über 230', () async {
      // Ältere Versionen erlaubten bis 250.
      await repository.preferences.write(
        const CardioPreferenceValues(maxHeartRate: 250),
      );
      final controller = newController();
      final draft = await controller.start(template: template);
      expect(draft.phases.single.highBpm, 230);
    });

    test('ungültige Zonen nennen den Grund', () async {
      // Ruhepuls über dem Maximalpuls ergibt fallende Zonengrenzen.
      await repository.preferences.write(
        const CardioPreferenceValues(maxHeartRate: 100, restingHeartRate: 120),
      );
      final controller = newController();
      await expectLater(
        controller.start(template: template),
        throwsA(
          isA<CardioTemplateResolutionException>().having(
            (e) => e.message,
            'message',
            contains('40 bis 230 bpm'),
          ),
        ),
      );
      expect(controller.isRunning, isFalse);
    });
  });

  group('Erholung', () {
    Future<CardioSession> runUntilFinished(
      CardioSessionController controller,
    ) async {
      await controller.start();
      platform.samples.addAll([
        sample(1, 12, 150),
        sample(2, 18, 154),
        // Älter als 10 s vor dem Beenden: zählt nicht zum Startwert.
        sample(3, 5, 90),
      ]);
      platform.latestBpm = 154;
      platform.latestAt = t0.add(const Duration(seconds: 18));
      now = t0.add(const Duration(seconds: 20));
      return controller.finish();
    }

    test('misst 60 s weiter und speichert den Pulsabfall', () async {
      final controller = newController();
      final session = await runUntilFinished(controller);
      expect(session.endedAtUtc, t0.add(const Duration(seconds: 20)));
      expect(controller.isRecovering, isTrue);
      expect(controller.isRunning, isFalse);
      expect(controller.recovery!.startBpm, 152);
      expect(controller.recoveryRemaining, const Duration(seconds: 60));
      // Ohne Alarm, Zone und Live Activity weiter überwachen.
      final config = platform.updated.single;
      expect(config.sessionId, session.sessionId);
      expect(config.alertsEnabled, isFalse);
      expect(config.zoneLowBpm, isNull);
      expect(config.liveActivityEnabled, isFalse);
      expect(platform.stopped, isEmpty);

      platform.samples.addAll([
        sample(4, 40, 140),
        sample(5, 75, 126),
        sample(6, 80, 122),
        sample(7, 84, 124),
        // Nach dem Fenster 55–65 s.
        sample(8, 95, 100),
      ]);
      now = t0.add(const Duration(seconds: 50));
      await controller.poll();
      expect(controller.isRecovering, isTrue);
      expect(controller.recoveryRemaining, const Duration(seconds: 30));

      now = t0.add(const Duration(seconds: 86));
      await controller.poll();
      expect(controller.isRecovering, isFalse);
      expect(platform.stopped, [session.sessionId]);
      final saved = (await repository.readSession(session.sessionId))!;
      expect(saved.recoveryStartBpm, 152);
      expect(saved.recoveryEndBpm, 124);
      expect(saved.recoveryDropBpm, -28);
      // Die Dauer der Einheit endet beim Beenden.
      expect(saved.endedAtUtc, t0.add(const Duration(seconds: 20)));
    });

    test('Überspringen speichert keine Erholungswerte', () async {
      final controller = newController();
      final session = await runUntilFinished(controller);
      await controller.skipRecovery();
      expect(controller.isRecovering, isFalse);
      expect(platform.stopped, [session.sessionId]);
      final saved = (await repository.readSession(session.sessionId))!;
      expect(saved.recoveryStartBpm, isNull);
      expect(saved.recoveryEndBpm, isNull);
    });

    test(
      'ohne Messwerte im Endfenster bleibt die Einheit ohne Erholung',
      () async {
        final controller = newController();
        final session = await runUntilFinished(controller);
        platform.samples.add(sample(4, 40, 140));
        // App kam erst nach 120 s zurück; im Fenster 55–65 s gibt es nichts.
        now = t0.add(const Duration(seconds: 140));
        await controller.poll();
        expect(controller.isRecovering, isFalse);
        expect(platform.stopped, [session.sessionId]);
        expect(
          (await repository.readSession(session.sessionId))!.recoveryEndBpm,
          isNull,
        );
      },
    );

    test(
      'nach Rückkehr in die App zählen gepufferte Werte im Fenster',
      () async {
        final controller = newController();
        final session = await runUntilFinished(controller);
        platform.samples.addAll([sample(4, 78, 130), sample(5, 82, 128)]);
        now = t0.add(const Duration(seconds: 200));
        await controller.poll();
        final saved = (await repository.readSession(session.sessionId))!;
        expect(saved.recoveryDropBpm, 129 - 152);
      },
    );

    test('ohne Puls vor dem Beenden gibt es keine Erholung', () async {
      final controller = newController();
      final draft = await controller.start();
      now = t0.add(const Duration(seconds: 20));
      await controller.finish();
      expect(controller.isRecovering, isFalse);
      expect(platform.stopped, [draft.sessionId]);
    });

    test('eine neue Einheit beendet die Erholung zuerst', () async {
      final controller = newController();
      final first = await runUntilFinished(controller);
      final second = await controller.start();
      expect(controller.isRecovering, isFalse);
      expect(platform.stopped, [first.sessionId]);
      expect(controller.active!.sessionId, second.sessionId);
    });
  });
}
