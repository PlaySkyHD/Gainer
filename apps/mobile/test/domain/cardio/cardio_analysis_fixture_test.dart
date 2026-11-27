import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_analysis.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_session.dart';

import '../../support/contract_fixture.dart';

/// Die Kennzahlen einer Cardio-Einheit rechnen wie der Server
/// (`get_cardio_session`).
void main() {
  for (final testCase in loadFixtureCases('cardio-analysis.json')) {
    test('Fall ${testCase['name']}', () => _verify(testCase));
  }
}

void _verify(Map<String, Object?> testCase) {
  final session = CardioSession.fromJson({
    ...testCase,
    'sessionId': '00000000-0000-4000-8000-000000000001',
    'activityType': 'IndoorCycling',
    'createdAtUtc': '2026-11-20T18:00:00Z',
    'updatedAtUtc': '2026-11-20T18:00:00Z',
  });
  final analysis = CardioAnalysis.of(session);
  final expected = testCase['expected']! as Map<String, Object?>;

  expect(analysis.activeDuration.inSeconds, expected['activeDurationSeconds']);
  expectFixtureNumber(analysis.averageBpm, expected['averageBpm'], 'average');
  expect(analysis.maxBpm, expected['maxBpm']);
  expect(analysis.timeInZone.inSeconds, expected['timeInZoneSeconds']);
  final share = expected['zoneShare'] as num?;
  if (share == null) {
    expect(analysis.zoneShare, isNull);
  } else {
    expect(analysis.zoneShare, closeTo(share.toDouble(), 0.00005));
  }
  expect(analysis.rmssdMs, expected['rmssdMs']);
  expect(session.recoveryDropBpm, expected['recoveryDropBpm']);
}
