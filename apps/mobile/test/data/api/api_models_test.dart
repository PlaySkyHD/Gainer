import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/api/api_models.dart';
import 'package:gainer_mobile/data/models/api/sync_api_models.dart';

void main() {
  test('invitation response matches the current backend DTO exactly', () {
    final invitation = ApiInvitation.fromJson({
      'activationPath': '/accept-invitation?token=one-time-token',
      'expiresAt': '2026-10-12T12:30:00+02:00',
    });

    expect(
      invitation.activationPath,
      '/accept-invitation?token=one-time-token',
    );
    expect(invitation.expiresAt, DateTime.utc(2026, 10, 12, 10, 30));
  });

  test('session response maps existing user and operator fields', () {
    final session = ApiSession.fromJson({
      'userId': '11111111-1111-4111-8111-111111111111',
      'email': 'member@example.test',
      'isAccountOperator': true,
    });

    expect(session.userId, '11111111-1111-4111-8111-111111111111');
    expect(session.email, 'member@example.test');
    expect(session.isAccountOperator, isTrue);
  });

  test('sync response accepts OpenAPI numeric int or string encodings and UTC dates', () {
    final client = SyncClientRegistrationResponse.fromJson({
      'clientId': '22222222-2222-4222-8222-222222222222',
      'displayName': 'iPhone',
      'protocolVersion': '2',
      'isActiveWriter': true,
      'registeredAtUtc': '2026-10-12T10:00:00Z',
      'lastSeenAtUtc': '2026-10-12T12:00:00+02:00',
    });
    final pull = SyncPullResponse.fromJson({
      'protocolVersion': 2,
      'nextCursor': '922337',
      'hasMore': false,
      'batches': [
        {
          'batchId': '33333333-3333-4333-8333-333333333333',
          'revision': 922337,
          'originMutationId': null,
          'changes': [],
        },
      ],
    });

    expect(client.protocolVersion, 2);
    expect(client.registeredAtUtc, DateTime.utc(2026, 10, 12, 10));
    expect(client.lastSeenAtUtc, DateTime.utc(2026, 10, 12, 10));
    expect(pull.nextCursor, 922337);
    expect(pull.batches.single.changes, isEmpty);
  });

  test(
    'planned handover request preserves the current OpenSpec field names',
    () {
      expect(
        const BeginSyncHandoverRequest(
          requestId: '11111111-1111-4111-8111-111111111111',
          sourceClientId: '22222222-2222-4222-8222-222222222222',
          expectedRevision: 19,
        ).toJson(),
        {
          'requestId': '11111111-1111-4111-8111-111111111111',
          'sourceClientId': '22222222-2222-4222-8222-222222222222',
          'expectedRevision': 19,
        },
      );
      expect(
        const CompleteSyncHandoverRequest(
          oneTimeCode: 'opaque-one-time-code',
          targetClientId: '33333333-3333-4333-8333-333333333333',
          caughtUpRevision: 19,
        ).toJson(),
        {
          'oneTimeCode': 'opaque-one-time-code',
          'targetClientId': '33333333-3333-4333-8333-333333333333',
          'caughtUpRevision': 19,
        },
      );
    },
  );
}
