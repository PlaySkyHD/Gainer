import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/body/body_repository.dart';
import 'package:gainer_mobile/data/repositories/health/check_in_health_coordinator.dart';
import 'package:gainer_mobile/data/repositories/health/health_steps_sync.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';

import '../../support/fake_health_platform.dart';

const _account = '00000000-0000-4000-8000-000000000001';

void main() {
  late LocalDatabase database;
  late LocalSyncStore store;
  late BodyRepository body;
  late FakeHealthPlatform platform;
  late HealthStepsSync sync;
  // Samstag, 24. Oktober, mittags.
  final now = DateTime(2026, 10, 24, 12, 30);
  var id = 10;

  setUp(() {
    database = LocalDatabase(NativeDatabase.memory());
    store = LocalSyncStore(database: database, accountId: _account);
    body = BodyRepository(
      store: store,
      ids: () =>
          '00000000-0000-4000-8000-${(id++).toString().padLeft(12, '0')}',
      clock: () => now.toUtc(),
    );
    platform = FakeHealthPlatform();
    sync = HealthStepsSync(
      health: CheckInHealthCoordinator(
        platform: platform,
        accountId: _account,
        clock: () => now,
      ),
      body: body,
      clock: () => now,
    );
  });

  tearDown(() => database.close());

  Future<void> checkIn(String date, {int? steps, int? sleepMinutes}) =>
      body.saveCheckIn(
        localDate: date,
        weightKg: 82.4,
        caloriesKcal: null,
        proteinGrams: null,
        carbohydrateGrams: null,
        fatGrams: null,
        steps: steps,
        sleepMinutes: sleepMinutes,
      );

  Future<int?> storedSteps(String date) async => (await body.read()).checkIns
      .singleWhere((item) => item.value.localDate == date)
      .value
      .steps;

  test('today reads up to now without asking for access', () async {
    platform.steps = 8450;

    expect(await sync.today(), 8450);
    expect(platform.checkInAuthorizations, 0);
    expect(platform.stepReads.single.from, DateTime(2026, 10, 24).toUtc());
    expect(platform.stepReads.single.to, now.toUtc());
  });

  test('today is null without data, access or Health', () async {
    expect(await sync.today(), isNull);
    platform.steps = 0;
    expect(await sync.today(), isNull);
    platform.readError = StateError('kein Zugriff');
    expect(await sync.today(), isNull);
    platform
      ..readError = null
      ..available = false
      ..steps = 500;
    expect(await sync.today(), isNull);
  });

  test('past check-ins take the full day total; other values stay', () async {
    await checkIn('2026-10-23', steps: 1200, sleepMinutes: 420);
    await checkIn('2026-10-22', steps: 9000);
    await checkIn('2026-10-24', steps: 900);
    await checkIn('2026-10-10', steps: 100);
    platform.stepsFor = (from) => switch (from) {
      _ when from == DateTime(2026, 10, 23).toUtc() => 11800,
      _ when from == DateTime(2026, 10, 22).toUtc() => 9000,
      _ => 4000,
    };

    expect(await sync.syncRecent(), 1);

    expect(await storedSteps('2026-10-23'), 11800);
    final yesterday = (await body.read()).checkIns
        .singleWhere((item) => item.value.localDate == '2026-10-23')
        .value;
    expect(yesterday.weightKg, 82.4);
    expect(yesterday.sleepMinutes, 420);
    // Unverändert: gleicher Wert, heute (live) und älter als 7 Tage.
    expect(await storedSteps('2026-10-22'), 9000);
    expect(await storedSteps('2026-10-24'), 900);
    expect(await storedSteps('2026-10-10'), 100);
    expect(platform.checkInAuthorizations, 0);
    // Die Änderung ist für den Sync vorgemerkt.
    final outbox = await store.readOutbox(aggregateType: 'daily-check-in');
    expect(
      outbox.any(
        (mutation) =>
            mutation.body is Map &&
            (mutation.body! as Map)['localDate'] == '2026-10-23' &&
            (mutation.body! as Map)['steps'] == 11800,
      ),
      isTrue,
    );
  });

  test('without Health data nothing changes', () async {
    await checkIn('2026-10-23', steps: 1200);
    expect(await sync.syncRecent(), 0);
    expect(await storedSteps('2026-10-23'), 1200);
  });

  test(
    'updateSteps only touches existing check-ins with other values',
    () async {
      expect(
        await body.updateSteps(localDate: '2026-10-20', steps: 5000),
        isFalse,
      );
      await checkIn('2026-10-20', steps: 5000);
      expect(
        await body.updateSteps(localDate: '2026-10-20', steps: 5000),
        isFalse,
      );
      expect(
        await body.updateSteps(localDate: '2026-10-20', steps: 6100),
        isTrue,
      );
      expect(await storedSteps('2026-10-20'), 6100);
    },
  );
}
