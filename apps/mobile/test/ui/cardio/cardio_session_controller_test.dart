import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/cardio/cardio_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/repositories/training/training_preferences.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_draft.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_session.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_session_controller.dart';

const accountId = '00000000-0000-4000-8000-000000000001';
String testId(int value) =>
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';

class FakeHeartRate implements HeartRatePlatform {
  HeartRateMonitoringConfig? monitoring;
  final started = <HeartRateMonitoringConfig>[];
  final updated = <HeartRateMonitoringConfig>[];
  final stopped = <String>[];
  final connected = <String>[];
  final samples = <CardioSample>[];
  var scans = 0;
  var disconnects = 0;
  BluetoothProblem? problem;
  HeartRateConnectionState connection = HeartRateConnectionState.connected;
  int? latestBpm;
  DateTime? latestAt;

  @override
  Future<HeartRateStatus> readStatus(int afterSequence) async {
    if (problem != null) throw BluetoothUnavailableException(problem!);
    return HeartRateStatus(
      bluetoothState: HeartRateBluetoothState.poweredOn,
      connectionState: connection,
      sensorId: 'sensor-1',
      sensorName: 'Polar H10',
      batteryPercent: 80,
      latestBpm: latestBpm,
      latestAtUtc: latestAt,
      monitoringSessionId: monitoring?.sessionId,
      lastSequence: samples.isEmpty ? 0 : samples.last.sequence,
      samples: [
        for (final sample in samples)
          if (sample.sequence > afterSequence) sample,
      ],
    );
  }

  @override
  Future<List<HeartRateSensor>> scan(Duration duration) async {
    if (problem != null) throw BluetoothUnavailableException(problem!);
    scans++;
    return const [
      HeartRateSensor(id: 'sensor-1', name: 'Polar H10', isConnected: false),
    ];
  }

  @override
  Future<bool> connect(String sensorId) async {
    if (problem != null) throw BluetoothUnavailableException(problem!);
    connected.add(sensorId);
    return true;
  }

  @override
  Future<void> disconnect() async => disconnects++;

  @override
  Future<void> startMonitoring(HeartRateMonitoringConfig config) async {
    monitoring = config;
    started.add(config);
  }

  @override
  Future<void> updateMonitoring(HeartRateMonitoringConfig config) async {
    monitoring = config;
    updated.add(config);
  }

  @override
  Future<void> stopMonitoring(String sessionId) async {
    stopped.add(sessionId);
    monitoring = null;
  }
}

class FakeNotifications implements TimerNotificationPlatform {
  var requests = 0;

  @override
  Future<bool> requestPermission() async {
    requests++;
    return true;
  }

  @override
  Future<void> schedule({
    required String workoutId,
    required int generation,
    required DateTime targetAtUtc,
    required String soundId,
  }) async {}

  @override
  Future<void> cancel(String workoutId) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalDatabase database;
  late LocalSyncStore store;
  late CardioRepository repository;
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
    repository = CardioRepository(
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
    expect(platform.stopped, [draft.sessionId]);
    expect(await repository.readDraft(), isNull);
    expect((await repository.readSessions()).single.sessionId, draft.sessionId);
    final prefs = await repository.preferences.read();
    expect((prefs.lastZoneLow, prefs.lastZoneHigh), (120, 140));
    expect(prefs.warmupSeconds, 60);
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
}
