import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/local/local_mutation.dart';
import 'package:gainer_mobile/data/repositories/sync/sync_payload_codec.dart';

const _id = '22222222-2222-4222-8222-222222222222';

LocalMutation _mutation(LocalMutationOperation operation, Object? body) =>
    LocalMutation(
      mutationId: '33333333-3333-4333-8333-333333333333',
      accountId: '11111111-1111-4111-8111-111111111111',
      aggregateType: 'cardio-session',
      aggregateId: _id,
      sequence: 1,
      status: LocalMutationStatus.pending,
      createdAtUtc: DateTime.utc(2026),
      operation: operation,
      baseVersion: 2,
      body: body,
    );

void main() {
  test('maps the CardioSession resource', () {
    expect(
      SyncPayloadCodec.aggregateTypeForResource('CardioSession'),
      'cardio-session',
    );
  });

  test('server snapshot round trips into a save payload', () {
    final snapshot =
        SyncPayloadCodec.normalizeSnapshot('CardioSession', {
              'sessionId': _id,
              'version': 2,
              'activityType': 'IndoorCycling',
              'startedAtUtc': '2026-10-18T10:00:00Z',
              'endedAtUtc': '2026-10-18T10:30:00Z',
              'targetZone': {'lowBpm': 120, 'highBpm': 140},
              'sampleIntervalSeconds': 5,
              'heartRateBpm': [100, 0, 130],
              'rrIntervalsMs': [800, 810],
              'distanceKm': 14.2,
              'createdAtUtc': '2026-10-18T10:31:00Z',
              'updatedAtUtc': '2026-10-18T10:31:00Z',
            })!
            as Map<String, dynamic>;
    expect(snapshot.containsKey('version'), isFalse);
    expect(snapshot['sessionId'], _id);

    final update = _mutation(LocalMutationOperation.update, snapshot);
    expect(
      SyncPayloadCodec.serverOperation(update, snapshot),
      'saveCardioSession',
    );
    final payload = SyncPayloadCodec.serverPayload(
      update,
      snapshot,
      2,
    ) as Map<String, Object?>;
    expect(payload['baseVersion'], 2);
    final session = payload['session'] as Map<String, Object?>;
    expect(session['distanceKm'], 14.2);
    expect(session['heartRateBpm'], [100, 0, 130]);
    expect(session.containsKey('notes'), isFalse);
    expect(session.containsKey('createdAtUtc'), isFalse);
    expect(session.containsKey('updatedAtUtc'), isFalse);
  });

  test('delete sends id and base version', () {
    final delete = _mutation(LocalMutationOperation.delete, {'sessionId': _id});
    expect(SyncPayloadCodec.serverOperation(delete, {}), 'deleteCardioSession');
    expect(SyncPayloadCodec.serverPayload(delete, {}, 2), {
      'sessionId': _id,
      'baseVersion': 2,
    });
  });

  test('recovery values are sent and survive the snapshot round trip', () {
    final snapshot =
        SyncPayloadCodec.normalizeSnapshot('CardioSession', {
              'sessionId': _id,
              'version': 2,
              'activityType': 'IndoorCycling',
              'startedAtUtc': '2026-10-18T10:00:00Z',
              'endedAtUtc': '2026-10-18T10:30:00Z',
              'sampleIntervalSeconds': 5,
              'heartRateBpm': [100, 130],
              'recoveryStartBpm': 152,
              'recoveryEndBpm': 124,
              'createdAtUtc': '2026-10-18T10:31:00Z',
              'updatedAtUtc': '2026-10-18T10:31:00Z',
            })!
            as Map<String, dynamic>;
    final payload = SyncPayloadCodec.serverPayload(
      _mutation(LocalMutationOperation.update, snapshot),
      snapshot,
      2,
    ) as Map<String, Object?>;
    final session = payload['session'] as Map<String, Object?>;
    expect(session['recoveryStartBpm'], 152);
    expect(session['recoveryEndBpm'], 124);
  });

  test('check-in snapshot values keep resting heart rate and HRV', () {
    final snapshot =
        SyncPayloadCodec.normalizeSnapshot('DailyCheckIn', {
              'checkInId': _id,
              'localDate': '2026-10-12',
              'version': 3,
              'values': {
                'weightKg': 71,
                'restingHeartRateBpm': 58,
                'restingHrvMs': 52,
              },
              'createdAtUtc': '2026-10-12T07:00:00Z',
              'updatedAtUtc': '2026-10-12T07:00:00Z',
            })!
            as Map<String, dynamic>;
    expect(snapshot['restingHeartRateBpm'], 58);
    expect(snapshot['restingHrvMs'], 52);
    expect(snapshot['localDate'], '2026-10-12');
  });
}
