import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/nutrition/day_target.dart';
import 'package:gainer_mobile/domain/models/training/training_plan_model.dart';
import 'package:gainer_mobile/domain/models/training/training_schedule.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';

import '../../support/contract_fixture.dart';

/// Die Rhythmus-Vorschau rechnet wie der Server (`get_training_schedule`,
/// `get_training_today` und die Tagesart in `get_nutrition_days`).
void main() {
  for (final testCase in loadFixtureCases('training-schedule.json')) {
    test('Fall ${testCase['name']}', () {
      expect(
        projectFixtureCase(testCase),
        testCase['expected'],
        reason: '${testCase['name']}',
      );
    });
  }
}

/// Rechnet einen Fall der Fixture in derselben Form wie `expected`.
Map<String, Object?> projectFixtureCase(Map<String, Object?> testCase) {
  final today = LocalDay.parse(testCase['today']! as String);
  final projection = TrainingScheduleProjection(
    schedule: _schedule(testCase['schedule'] as Map<String, Object?>?),
    plans: [
      for (final item in fixtureList(testCase['plans']))
        _plan(item! as Map<String, Object?>),
    ],
    workouts: [
      for (final item in fixtureList(testCase['workouts']))
        _workout(item! as Map<String, Object?>),
    ],
    today: today,
    localDayOf: berlinDayOf,
  );
  final next = projection.nextPlannedAfter(today);
  return {
    'effectiveCycleIndex': projection.schedule?.effectiveCycleIndex(today),
    'nextPlanned': next == null
        ? null
        : {'planId': next.planId, 'date': next.date.toIso()},
    'days': [
      for (final day in projection.days(
        LocalDay.parse(testCase['from']! as String),
        LocalDay.parse(testCase['through']! as String),
      ))
        {
          'date': day.date.toIso(),
          'baseKind': day.baseKind.name,
          'slotIndex': day.slotIndex,
          'archivedPlanId': day.archivedPlanId,
          'isFree': day.isFree,
          'hasFinished': projection.hasFinishedOn(day.date),
          'automaticDayKind': automaticDayKind(
            day.date,
            projection,
          ).name.toLowerCase(),
          'trainings': [
            for (final training in day.trainings)
              {
                'planId': training.planId,
                'planName': training.planName,
                'date': training.date.toIso(),
                'originDate': training.originDate.toIso(),
                'status': training.status.name,
                'movedToDate': training.movedToDate?.toIso(),
                'completedBy': [
                  for (final workout in training.completedBy) workout.workoutId,
                ],
                'instead': [
                  for (final workout in training.instead) workout.workoutId,
                ],
              },
          ],
        },
    ],
  };
}

TrainingSchedule? _schedule(Map<String, Object?>? json) {
  if (json == null) return null;
  final anchor = json['anchorDate'] as String?;
  return TrainingSchedule(
    scheduleId: 'schedule',
    mode: TrainingScheduleMode.fromWire(json['mode']),
    anchorDate: anchor == null ? null : LocalDay.parse(anchor),
    validFrom: LocalDay.parse(json['validFrom']! as String),
    slots: [
      for (final planId in fixtureList(json['slots']))
        TrainingScheduleSlot(planId: planId as String?),
    ],
    shifts: [
      for (final item in fixtureList(json['shifts']))
        TrainingScheduleShift.fromJson(item! as Map<String, Object?>),
    ],
    exceptions: [
      for (final item in fixtureList(json['exceptions']))
        TrainingScheduleException.fromJson(item! as Map<String, Object?>),
    ],
  );
}

TrainingPlanModel _plan(Map<String, Object?> json) => TrainingPlanModel(
  planId: json['planId']! as String,
  name: json['name']! as String,
  previousValueSource: PreviousValueSource.exercise,
  isArchived: json['isArchived']! as bool,
);

Workout _workout(Map<String, Object?> json) {
  DateTime? optional(String key) =>
      json[key] == null ? null : DateTime.parse(json[key]! as String);
  return Workout(
    workoutId: json['workoutId']! as String,
    title: 'Training',
    startedAtUtc: DateTime.parse(json['startedAtUtc']! as String),
    endedAtUtc: optional('endedAtUtc'),
    deletedAtUtc: optional('deletedAtUtc'),
    previousValueSource: PreviousValueSource.exercise,
    sourcePlanId: json['sourcePlanId'] as String?,
  );
}
