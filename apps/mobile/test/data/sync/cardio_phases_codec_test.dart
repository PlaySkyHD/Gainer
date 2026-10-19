import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/local/local_mutation.dart';
import 'package:gainer_mobile/data/repositories/sync/sync_payload_codec.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_session.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_template.dart';

const _id = '22222222-2222-4222-8222-222222222222';

LocalMutation _mutation(Object? body) => LocalMutation(
  mutationId: '33333333-3333-4333-8333-333333333333',
  accountId: '11111111-1111-4111-8111-111111111111',
  aggregateType: 'cardio-session',
  aggregateId: _id,
  sequence: 1,
  status: LocalMutationStatus.pending,
  createdAtUtc: DateTime.utc(2026),
  operation: LocalMutationOperation.create,
  baseVersion: 0,
  body: body,
);

void main() {
  CardioSession build({String? name, List<CardioPhase> phases = const []}) =>
      CardioSession(
        sessionId: _id,
        startedAtUtc: DateTime.utc(2026, 10, 18, 10),
        endedAtUtc: DateTime.utc(2026, 10, 18, 10, 10),
        heartRateBpm: const [120, 130],
        rrIntervalsMs: const [],
        templateName: name,
        phases: phases,
        createdAtUtc: DateTime.utc(2026, 10, 18, 10, 11),
        updatedAtUtc: DateTime.utc(2026, 10, 18, 10, 11),
      );

  test('save payload carries templateName and phases', () {
    final body = build(
      name: '4×4',
      phases: const [
        CardioPhase(
          startOffsetSeconds: 0,
          durationSeconds: 600,
          name: 'Aufwärmen',
          lowBpm: 114,
          highBpm: 133,
        ),
        CardioPhase(startOffsetSeconds: 600, durationSeconds: 60, name: 'Frei'),
      ],
    ).toJson();
    final payload = SyncPayloadCodec.serverPayload(
      _mutation(body),
      body,
      0,
    ) as Map<String, Object?>;
    final session = payload['session'] as Map<String, Object?>;
    expect(session['templateName'], '4×4');
    final phases = session['phases'] as List;
    expect(phases, hasLength(2));
    expect(phases.first, {
      'startOffsetSeconds': 0,
      'durationSeconds': 600,
      'name': 'Aufwärmen',
      'lowBpm': 114,
      'highBpm': 133,
    });
    expect((phases.last as Map).containsKey('lowBpm'), isFalse);
  });

  test('free sessions send neither field', () {
    final body = build().toJson();
    final payload = SyncPayloadCodec.serverPayload(
      _mutation(body),
      body,
      0,
    ) as Map<String, Object?>;
    final session = payload['session'] as Map<String, Object?>;
    expect(session.containsKey('templateName'), isFalse);
    expect(session.containsKey('phases'), isFalse);
  });

  test('server snapshot with phases parses back into a session', () {
    final snapshot =
        SyncPayloadCodec.normalizeSnapshot('CardioSession', {
              'sessionId': _id,
              'version': 1,
              'activityType': 'IndoorCycling',
              'startedAtUtc': '2026-10-18T10:00:00Z',
              'endedAtUtc': '2026-10-18T10:30:00Z',
              'sampleIntervalSeconds': 5,
              'heartRateBpm': [100, 130],
              'templateName': 'Zone 2 – 30 min',
              'phases': [
                {
                  'startOffsetSeconds': 0,
                  'durationSeconds': 1800,
                  'name': 'Zone 2',
                  'lowBpm': 114,
                  'highBpm': 133,
                },
              ],
              'createdAtUtc': '2026-10-18T10:31:00Z',
              'updatedAtUtc': '2026-10-18T10:31:00Z',
            })!
            as Map<String, dynamic>;
    final session = CardioSession.fromJson(snapshot);
    expect(session.templateName, 'Zone 2 – 30 min');
    expect(session.phases.single.zone, isNotNull);
  });
}
