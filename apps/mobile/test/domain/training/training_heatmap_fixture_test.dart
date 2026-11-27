import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/training_heatmap.dart';
import 'package:gainer_mobile/domain/models/training/training_schedule.dart';

import '../../support/contract_fixture.dart';

/// Die Heatmap rechnet wie der Server (`get_training_heatmap`).
void main() {
  for (final testCase in loadFixtureCases('training-heatmap.json')) {
    test('Fall ${testCase['name']}', () => _verify(testCase));
  }
}

void _verify(Map<String, Object?> testCase) {
  final heatmap = buildTrainingHeatmap(
    [
      for (final item in fixtureList(testCase['sessions']))
        _interval(item! as Map<String, Object?>),
    ],
    today: LocalDay.parse(testCase['today']! as String),
    dayOf: berlinDayOf,
  );
  final expected = testCase['expected']! as Map<String, Object?>;
  final trainingDays = heatmap.days.where((day) => day.hasTraining).toList();

  expect(heatmap.start.toIso(), expected['start']);
  expect(heatmap.weeks, hasLength(expected['weekCount']! as int));
  expect(heatmap.trainingDays, expected['trainingDays']);
  final bounds = heatmapBounds(trainingDays.map((day) => day.minutes));
  final wantBounds = fixtureList(expected['bounds']);
  expect(bounds, hasLength(wantBounds.length));
  for (var i = 0; i < wantBounds.length; i++) {
    expectFixtureNumber(bounds[i], wantBounds[i], 'bounds[$i]');
  }
  expect([
    for (final day in trainingDays)
      {'date': day.date.toIso(), 'minutes': day.minutes, 'level': day.level},
  ], expected['days']);
}

TrainingInterval _interval(Map<String, Object?> json) => (
  startedAtUtc: DateTime.parse(json['startedAtUtc']! as String),
  endedAtUtc: DateTime.parse(json['endedAtUtc']! as String),
);
