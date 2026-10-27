import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/local/local_aggregate.dart';
import 'package:gainer_mobile/data/repositories/body/body_repository.dart';
import 'package:gainer_mobile/data/repositories/health/health_review_coordinator.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/data/services/platform/generated/mobile_platform_api.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';
import 'package:gainer_mobile/domain/models/body/body_tracking.dart';
import 'package:gainer_mobile/ui/features/body/health/health_review_view_model.dart';

import '../../support/fake_health_platform.dart';

const accountId = '00000000-0000-4000-8000-000000000001';
String testId(int value) =>
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';

class _HealthFake extends FakeHealthPlatform {
  List<BodyMassSample> samples = const [];
  int requestReads = 0;
  int readQueries = 0;
  DateTime? lastToUtc;
  int requestWrites = 0;
  int exports = 0;
  void Function()? onReadRequest;
  void Function()? onWriteRequest;
  CompletedWorkoutHealthExport? lastExport;
  Completer<void>? readBarrier;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<PlatformAuthorizationRequestResult>
  requestBodyMassReadAuthorization() async {
    requestReads++;
    onReadRequest?.call();
    return PlatformAuthorizationRequestResult.requestCompleted;
  }

  @override
  Future<List<BodyMassSample>> readBodyMassSamples({
    required DateTime fromUtc,
    required DateTime toUtc,
  }) async {
    readQueries++;
    lastToUtc = toUtc;
    await readBarrier?.future;
    return samples;
  }

  @override
  Future<PlatformAuthorizationRequestResult>
  requestWorkoutWriteAuthorization() async {
    requestWrites++;
    onWriteRequest?.call();
    return PlatformAuthorizationRequestResult.requestCompleted;
  }

  @override
  Future<WorkoutExportReceipt> exportCompletedWorkout(
    CompletedWorkoutHealthExport workout,
  ) async {
    exports++;
    lastExport = workout;
    return const WorkoutExportReceipt(
      status: HealthExportStatus.saved,
      syncIdentifier: 'opaque-health-id',
      syncVersion: 3,
    );
  }
}

void main() {
  late LocalDatabase database;
  late LocalSyncStore store;
  late BodyRepository body;
  late _HealthFake health;
  late HealthSessionIdentity identity;
  var id = 10;
  final now = DateTime.utc(2026, 10, 12, 10);

  HealthReviewCoordinator coordinator() => HealthReviewCoordinator(
    store: store,
    bodyRepository: body,
    platform: health,
    accountId: accountId,
    currentSessionIdentity: () => identity,
  );

  setUp(() {
    database = LocalDatabase(NativeDatabase.memory());
    store = LocalSyncStore(database: database, accountId: accountId);
    body = BodyRepository(
      store: store,
      ids: () => testId(id++),
      clock: () => now,
    );
    health = _HealthFake();
    identity = const HealthSessionIdentity(accountId: accountId, generation: 7);
  });

  tearDown(() async => database.close());

  BodyMassSample sample(String uuid, {DateTime? at}) => BodyMassSample(
    uuid: uuid,
    measuredAtUtc: at ?? DateTime.utc(2026, 10, 12, 8),
    weightKilograms: 71.25,
    sourceName: 'Apple Watch',
  );

  test(
    'a range ending today stops the query now instead of at midnight',
    () async {
      final now = DateTime(2026, 10, 18, 10, 30);
      final review =
          await HealthReviewCoordinator(
            store: store,
            bodyRepository: body,
            platform: health,
            accountId: accountId,
            currentSessionIdentity: () => identity,
            clock: () => now,
          ).prepareWeightReview(
            fromLocalDate: '2026-10-12',
            toLocalDate: '2026-10-18',
          );
      expect(review, isNotNull);
      expect(health.lastToUtc, now.toUtc());
    },
  );

  test('a past range still ends at the following local midnight', () async {
    await coordinator().prepareWeightReview(
      fromLocalDate: '2026-10-10',
      toLocalDate: '2026-10-12',
    );
    expect(health.lastToUtc, DateTime(2026, 10, 13).toUtc());
  });

  test(
    'the 90-day limit counts calendar days across the spring DST switch',
    () async {
      // 2027-01-01 bis 2027-04-02 sind 91 Tage. Über die Frühlingsumstellung
      // fehlt eine Stunde; „inDays“ zählte unter TZ=Europe/Berlin nur 90.
      await expectLater(
        coordinator().prepareWeightReview(
          fromLocalDate: '2027-01-01',
          toLocalDate: '2027-04-02',
        ),
        throwsArgumentError,
      );
      await HealthReviewCoordinator(
        store: store,
        bodyRepository: body,
        platform: health,
        accountId: accountId,
        currentSessionIdentity: () => identity,
        clock: () => DateTime(2027, 6),
      ).prepareWeightReview(
        fromLocalDate: '2027-01-01',
        toLocalDate: '2027-04-01',
      );
      expect(health.lastToUtc, DateTime(2027, 4, 2).toUtc());
    },
  );

  // Der Tag der Zeitumstellung hat 25 bzw. 23 Stunden; „+24 h“ landete unter
  // TZ=Europe/Berlin im Herbst wieder am selben Tag und lieferte keine Proben.
  for (final (day, next) in [
    ('2026-10-25', DateTime(2026, 10, 26)),
    ('2027-03-28', DateTime(2027, 3, 29)),
  ]) {
    test(
      'a range ending on the DST day $day ends at the next midnight',
      () async {
        await HealthReviewCoordinator(
          store: store,
          bodyRepository: body,
          platform: health,
          accountId: accountId,
          currentSessionIdentity: () => identity,
          clock: () => DateTime(2027, 6),
        ).prepareWeightReview(fromLocalDate: day, toLocalDate: day);
        expect(health.lastToUtc, next.toUtc());
      },
    );
  }

  test(
    'empty query results remain an empty review and do not imply denial',
    () async {
      final review = await coordinator().prepareWeightReview(
        fromLocalDate: '2026-10-10',
        toLocalDate: '2026-10-12',
      );
      expect(review!.samples, isEmpty);
      expect(health.requestReads, 1);
      expect(health.readQueries, 1);
    },
  );

  test('explicit confirmation atomically writes a normal check-in and local-only probe ledger', () async {
    health.samples = [sample('health-private-uuid-1')];
    final review = (await coordinator().prepareWeightReview(
      fromLocalDate: '2026-10-12',
      toLocalDate: '2026-10-12',
    ))!;
    final result = await coordinator().confirmWeightReview(
      review: review,
      selectedProbeIds: {review.samples.single.uuid},
      acceptedServerSyncNotice: true,
    );
    expect(result.single.status, HealthImportReviewStatus.imported);
    final outbox = await store.readOutbox(aggregateType: 'daily-check-in');
    expect(outbox, hasLength(1));
    expect(outbox.single.body, isNot(contains('health-private-uuid-1')));
    final ledger = await store.readSyncMetadata(
      'health-ledger:body-mass',
    ) as Map<String, dynamic>;
    expect(
      (ledger['probes'] as Map<String, dynamic>).containsKey(
        'health-private-uuid-1',
      ),
      isTrue,
    );
    expect((await body.read()).checkIns.single.value.weightKg, 71.25);
  });

  test('same probe is idempotent under concurrent imports and never creates a second outbox item', () async {
    final outcomes = await Future.wait([
      body.importHealthWeight(
        probeId: 'health-private-uuid-2',
        localDate: '2026-10-12',
        weightKg: 71.2,
        replaceExistingCheckIn: false,
        sessionGuard: () => true,
      ),
      body.importHealthWeight(
        probeId: 'health-private-uuid-2',
        localDate: '2026-10-12',
        weightKg: 71.2,
        replaceExistingCheckIn: false,
        sessionGuard: () => true,
      ),
    ]);
    expect(
      outcomes.map((item) => item.status),
      containsAll([
        HealthCheckInCommitStatus.imported,
        HealthCheckInCommitStatus.duplicate,
      ]),
    );
    expect(
      await store.readOutbox(aggregateType: 'daily-check-in'),
      hasLength(1),
    );
  });

  test('day collision asks for a decision; replacement preserves other check-in fields', () async {
    await body.saveCheckIn(
      DailyCheckInInput(
        localDate: '2026-10-12',
        weightKg: 70,
        caloriesKcal: 2100,
        proteinGrams: 125,
        carbohydrateGrams: null,
        fatGrams: null,
        steps: 9000,
        sleepMinutes: null,
      ),
    );
    health.samples = [sample('health-private-uuid-3')];
    final review = (await coordinator().prepareWeightReview(
      fromLocalDate: '2026-10-12',
      toLocalDate: '2026-10-12',
    ))!;
    final conflict = await coordinator().confirmWeightReview(
      review: review,
      selectedProbeIds: {review.samples.single.uuid},
      acceptedServerSyncNotice: true,
    );
    expect(conflict.single.status, HealthImportReviewStatus.dayConflict);
    expect(
      (await store.readOutbox(aggregateType: 'daily-check-in')),
      hasLength(1),
    );
    final replaced = await coordinator().confirmWeightReview(
      review: review,
      selectedProbeIds: {review.samples.single.uuid},
      acceptedServerSyncNotice: true,
      replaceCheckInProbeIds: {review.samples.single.uuid},
    );
    expect(replaced.single.status, HealthImportReviewStatus.imported);
    final checkIn = (await body.read()).checkIns.single.value;
    expect(checkIn.weightKg, 71.25);
    expect(checkIn.caloriesKcal, 2100);
    expect(checkIn.steps, 9000);
  });

  test(
    'a changed session generation during the Health prompt prevents the query',
    () async {
      health.onReadRequest = () => identity = const HealthSessionIdentity(
        accountId: accountId,
        generation: 8,
      );
      await expectLater(
        coordinator().prepareWeightReview(
          fromLocalDate: '2026-10-12',
          toLocalDate: '2026-10-12',
        ),
        throwsStateError,
      );
      expect(health.readQueries, 0);
    },
  );

  test('only server snapshot completion is exportable, even if working copy says completed', () async {
    final id = testId(900);
    final running = _workout(status: 'running', completedAt: null);
    final localCompleted = _workout(
      status: 'completed',
      completedAt: '2026-10-12T09:00:00Z',
    );
    await database
        .into(database.localResources)
        .insert(
          LocalResourcesCompanion.insert(
            aggregateType: 'workout',
            aggregateId: id,
            envelopeJson: LocalAggregateEnvelope<Object?>(
              aggregateId: id,
              serverSnapshot: running,
              workingCopy: localCompleted,
              serverVersion: 2,
              optimisticVersion: 3,
              syncState: LocalSyncState.pending,
            ).encode(),
            updatedAtEpochMs: now.millisecondsSinceEpoch,
          ),
        );
    expect(await coordinator().completedWorkoutsForExport(), isEmpty);
    await expectLater(
      coordinator().exportWorkout(workoutId: id, userConfirmed: true),
      throwsStateError,
    );
    expect(health.exports, 0);
  });

  test('confirmed server workout exports idempotency receipt only after user action', () async {
    final id = testId(901);
    final completed = _workout(
      status: 'completed',
      completedAt: '2026-10-12T09:00:00Z',
    );
    await database
        .into(database.localResources)
        .insert(
          LocalResourcesCompanion.insert(
            aggregateType: 'workout',
            aggregateId: id,
            envelopeJson: LocalAggregateEnvelope<Object?>(
              aggregateId: id,
              serverSnapshot: completed,
              workingCopy: completed,
              serverVersion: 2,
              optimisticVersion: 2,
              syncState: LocalSyncState.clean,
            ).encode(),
            updatedAtEpochMs: now.millisecondsSinceEpoch,
          ),
        );
    expect((await coordinator().completedWorkoutsForExport()).single.id, id);
    await expectLater(
      coordinator().exportWorkout(workoutId: id, userConfirmed: false),
      throwsStateError,
    );
    expect(health.exports, 0);
    final receipt = await coordinator().exportWorkout(
      workoutId: id,
      userConfirmed: true,
    );
    expect(receipt.status, HealthExportStatus.saved);
    expect(health.lastExport?.accountId, accountId);
    expect(health.lastExport?.serverVersion, 2);
    expect(
      await store.readSyncMetadata('health-ledger:workout-export:$id'),
      containsPair('syncIdentifier', 'opaque-health-id'),
    );
  });

  test(
    'logout or generation change while write permission is open blocks export',
    () async {
      final id = testId(902);
      final completed = _workout(
        status: 'completed',
        completedAt: '2026-10-12T09:00:00Z',
      );
      await database
          .into(database.localResources)
          .insert(
            LocalResourcesCompanion.insert(
              aggregateType: 'workout',
              aggregateId: id,
              envelopeJson: LocalAggregateEnvelope<Object?>(
                aggregateId: id,
                serverSnapshot: completed,
                workingCopy: completed,
                serverVersion: 2,
                optimisticVersion: 2,
                syncState: LocalSyncState.clean,
              ).encode(),
              updatedAtEpochMs: now.millisecondsSinceEpoch,
            ),
          );
      health.onWriteRequest = () => identity = const HealthSessionIdentity(
        accountId: accountId,
        generation: 8,
      );
      await expectLater(
        coordinator().exportWorkout(workoutId: id, userConfirmed: true),
        throwsStateError,
      );
      expect(health.exports, 0);
    },
  );

  test(
    'disposed Health ViewModel does not notify after a pending query',
    () async {
      health.samples = [sample('health-pending-query')];
      health.readBarrier = Completer<void>();
      final model = HealthReviewViewModel(coordinator());
      var disposed = false;
      var notificationsAfterDispose = 0;
      model.addListener(() {
        if (disposed) notificationsAfterDispose++;
      });

      final operation = model.prepareReview(
        fromLocalDate: '2026-10-12',
        toLocalDate: '2026-10-12',
      );
      for (
        var attempt = 0;
        attempt < 10 && health.readQueries == 0;
        attempt++
      ) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(health.readQueries, 1);
      model.dispose();
      disposed = true;
      health.readBarrier!.complete();
      await operation;
      expect(notificationsAfterDispose, 0);
    },
  );
}

Map<String, Object?> _workout({
  required String status,
  required String? completedAt,
}) => {
  'workoutId': 'workout-fixture',
  'title': 'Krafttraining',
  'notes': null,
  'startedAtUtc': '2026-10-12T08:00:00Z',
  'endedAtUtc': status == 'completed' ? completedAt : null,
  'previousValueSource': 'exercise',
  'sourcePlanId': null,
  'sourceWorkoutId': null,
  'exercises': <Object?>[],
  'deletedAtUtc': null,
};
