import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/cardio/cardio_repository.dart';
import 'package:gainer_mobile/data/repositories/health/cardio_health_exporter.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/repositories/training/training_preferences.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_draft.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_session.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_feature.dart';
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
  bool hasSensor = true;
  HeartRateConnectionState connection = HeartRateConnectionState.connected;
  int? latestBpm;
  DateTime? latestAt;

  @override
  Future<HeartRateStatus> readStatus(int afterSequence) async {
    if (problem != null) throw BluetoothUnavailableException(problem!);
    return HeartRateStatus(
      bluetoothState: HeartRateBluetoothState.poweredOn,
      connectionState: connection,
      sensorId: hasSensor ? 'sensor-1' : null,
      sensorName: hasSensor ? 'Polar H10' : null,
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

class FakeCardioHealth implements CardioHealthPlatform {
  var exports = 0;
  Object? failure;

  @override
  Future<void> requestWriteAuthorization() async {
    if (failure != null) throw failure!;
  }

  @override
  Future<WorkoutExportReceipt> exportCardioSession(
    CardioHealthExport export,
  ) async {
    exports++;
    return WorkoutExportReceipt(
      status: HealthExportStatus.saved,
      syncIdentifier: 'gainer.cardio.${export.accountId}.${export.sessionId}',
      syncVersion: export.syncVersion,
    );
  }
}

/// In-Memory-Datenbank mit Cardio-Repository, Fake-Gurt und steuerbarer Uhr.
class CardioHarness {
  CardioHarness._(
    this.database,
    this.store,
    this.repository,
    this.platform,
    this.health,
    this.controller,
    this._clock,
  );

  final LocalDatabase database;
  final LocalSyncStore store;
  final CardioRepository repository;
  final FakeHeartRate platform;
  final FakeCardioHealth health;
  final CardioSessionController controller;
  final _Clock _clock;

  DateTime get now => _clock.value;

  set now(DateTime value) => _clock.value = value;

  CardioFeature get feature => CardioFeature(
    repository: repository,
    session: controller,
    health: CardioHealthExporter(
      store: store,
      repository: repository,
      platform: health,
    ),
  );

  static Future<CardioHarness> create({DateTime? now}) async {
    final database = LocalDatabase(NativeDatabase.memory());
    final store = LocalSyncStore(database: database, accountId: accountId);
    final clock = _Clock(now ?? DateTime.utc(2026, 10, 18, 10));
    var id = 100;
    final repository = CardioRepository(
      store: store,
      ids: () => testId(id++),
      clock: () => clock.value,
    );
    final platform = FakeHeartRate();
    final controller = CardioSessionController(
      repository: repository,
      platform: platform,
      notifications: FakeNotifications(),
      trainingPreferences: TrainingPreferences(store: store),
      autoPoll: false,
      clock: () => clock.value,
    );
    return CardioHarness._(
      database,
      store,
      repository,
      platform,
      FakeCardioHealth(),
      controller,
      clock,
    );
  }

  /// Legt eine beendete Einheit an.
  Future<CardioSession> seedSession({
    required DateTime start,
    Duration length = const Duration(minutes: 30),
    List<int>? heartRate,
    CardioTargetZone? zone = const CardioTargetZone(lowBpm: 120, highBpm: 140),
    List<int> rr = const [],
  }) {
    final samples =
        heartRate ??
        [for (var i = 0; i < length.inSeconds ~/ 5 + 1; i++) 125 + (i % 20)];
    now = start.add(length);
    return repository.saveFinished(
      CardioSession(
        sessionId: repository.newSessionId(),
        startedAtUtc: start,
        endedAtUtc: start.add(length),
        targetZone: zone,
        heartRateBpm: samples,
        rrIntervalsMs: rr,
        sensorName: 'Polar H10',
        createdAtUtc: start.add(length),
        updatedAtUtc: start.add(length),
      ),
    );
  }

  Future<void> dispose() async {
    controller.dispose();
    await database.close();
  }
}

class _Clock {
  _Clock(this.value);
  DateTime value;
}

/// Lässt echte Datenbankantworten eintreffen und pumpt dabei Frames. Kein
/// `pumpAndSettle`: laufende Timer der Cardio-Ansichten melden sich jede Sekunde.
Future<void> pumpUi(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Schaltfläche in einem geöffneten gestapelten Dialog.
Finder inDialog(String label) => find.descendant(
  of: find.byWidgetPredicate((widget) => widget is GainerStackedDialog),
  matching: find.text(label),
);

/// Telefon-Größe für Layouts.
void phoneSize(WidgetTester tester, {double height = 844}) {
  tester.view.physicalSize = Size(390, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}
