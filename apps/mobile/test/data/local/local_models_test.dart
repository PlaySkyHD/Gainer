import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/local/local_aggregate.dart';
import 'package:gainer_mobile/data/models/local/local_mutation.dart';

void main() {
  test('envelope deep-copies and freezes server snapshot separately from working copy', () {
    final source = <String, Object?>{
      'metrics': <String, Object?>{'weightKg': 80},
      'tags': <Object?>['baseline'],
    };
    final envelope = serverEnvelope(
      aggregateId: 'b1234567-1234-4234-8234-123456789abc',
      snapshot: source,
      version: 3,
    );
    source['metrics'] = {'weightKg': 100};
    expect(envelope.serverSnapshot, {
      'metrics': {'weightKg': 80},
      'tags': ['baseline'],
    });
    expect(envelope.workingCopy, envelope.serverSnapshot);
    expect(identical(envelope.serverSnapshot, envelope.workingCopy), isFalse);
    expect(
      () => (envelope.workingCopy as Map<String, Object?>)['metrics'] = {
        'weightKg': 99,
      },
      throwsUnsupportedError,
    );
    expect(
      () =>
          ((envelope.serverSnapshot as Map<String, Object?>)['tags']
                  as List<Object?>)
              .add('later'),
      throwsUnsupportedError,
    );
  });

  test(
    'mutation payload snapshots nested input and rejects invalid versions',
    () {
      final body = <String, Object?>{
        'items': <Object?>[
          {'value': 1},
        ],
      };
      final mutation = LocalMutation(
        mutationId: 'c1234567-1234-4234-8234-123456789abc',
        accountId: 'a1234567-1234-4234-8234-123456789abc',
        aggregateType: 'daily-check-in',
        aggregateId: 'b1234567-1234-4234-8234-123456789abc',
        sequence: 1,
        status: LocalMutationStatus.pending,
        createdAtUtc: DateTime.utc(2026),
        operation: LocalMutationOperation.create,
        baseVersion: null,
        body: body,
      );
      body['items'] = [];
      expect(mutation.body, {
        'items': [
          {'value': 1},
        ],
      });
      expect(
        () =>
            ((mutation.body as Map<String, Object?>)['items'] as List<Object?>)
                .clear(),
        throwsUnsupportedError,
      );
      expect(
        () => LocalAggregateEnvelope<Object?>(
          aggregateId: 'b1234567-1234-4234-8234-123456789abc',
          serverSnapshot: null,
          workingCopy: {},
          serverVersion: -1,
          optimisticVersion: 0,
          syncState: LocalSyncState.clean,
        ),
        throwsArgumentError,
      );
    },
  );
}
