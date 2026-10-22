import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/training_plan_model.dart';
import 'package:gainer_mobile/domain/models/training/training_schedule.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';

// Mittwoch, 21. Oktober 2026.
final _today = LocalDay(2026, 10, 21);

TrainingPlanModel _plan(String id, {bool archived = false}) =>
    TrainingPlanModel(
      planId: id,
      name: id,
      previousValueSource: PreviousValueSource.exercise,
      isArchived: archived,
    );

final _plans = [
  _plan('Push'),
  _plan('Pull'),
  _plan('Beine'),
  _plan('Oberkörper'),
  _plan('Unterkörper'),
];

const _push = TrainingScheduleSlot(planId: 'Push');
const _pull = TrainingScheduleSlot(planId: 'Pull');
const _legs = TrainingScheduleSlot(planId: 'Beine');
const _rest = TrainingScheduleSlot.rest();

var _workoutCounter = 0;

/// Beendetes Training, lokal gestartet am [day] um [hour] Uhr.
Workout _workout(
  LocalDay day, {
  String? planId,
  String? title,
  int hour = 18,
  int minute = 0,
  bool finished = true,
  bool deleted = false,
}) {
  final start = DateTime(day.year, day.month, day.day, hour, minute).toUtc();
  return Workout(
    workoutId: 'w${_workoutCounter++}',
    title: title ?? planId ?? 'Training',
    startedAtUtc: start,
    endedAtUtc: finished ? start.add(const Duration(hours: 1)) : null,
    previousValueSource: PreviousValueSource.exercise,
    sourcePlanId: planId,
    deletedAtUtc: deleted ? start.add(const Duration(hours: 2)) : null,
  );
}

TrainingSchedule _cycle(
  List<TrainingScheduleSlot> slots, {
  LocalDay? today,
  int todaySlotIndex = 0,
}) => TrainingSchedule.create(
  scheduleId: 'schedule',
  mode: TrainingScheduleMode.cycle,
  slots: slots,
  today: today ?? _today,
  todaySlotIndex: todaySlotIndex,
);

TrainingSchedule _weekly(List<String?> planIds, {LocalDay? validFrom}) =>
    TrainingSchedule.create(
      scheduleId: 'schedule',
      mode: TrainingScheduleMode.weekly,
      slots: [for (final id in planIds) TrainingScheduleSlot(planId: id)],
      today: validFrom ?? _today,
    );

TrainingScheduleProjection _project(
  TrainingSchedule? schedule, {
  LocalDay? today,
  List<Workout> workouts = const [],
  List<TrainingPlanModel>? plans,
}) => TrainingScheduleProjection(
  schedule: schedule,
  plans: plans ?? _plans,
  workouts: workouts,
  today: today ?? _today,
);

/// Pläne, die an [date] tatsächlich anstehen (ohne verschobene/übersprungene).
List<String> _effective(TrainingScheduleProjection projection, LocalDay date) =>
    [for (final t in projection.day(date).effective) t.planId];

ScheduledTraining _single(
  TrainingScheduleProjection projection,
  LocalDay date,
) => projection.day(date).trainings.single;

void main() {
  group('LocalDay', () {
    test('parses and prints YYYY-MM-DD', () {
      final day = LocalDay.parse('2026-02-28');
      expect(day, LocalDay(2026, 2, 28));
      expect(day.toIso(), '2026-02-28');
      expect(day.addDays(1).toIso(), '2026-03-01');
      expect(() => LocalDay.parse('2026-02-30'), throwsFormatException);
      expect(() => LocalDay.parse('26-2-3'), throwsFormatException);
    });

    test('day arithmetic ignores daylight saving changes', () {
      // Europe/Berlin stellt am 25.10.2026 und am 28.03.2027 um.
      final before = LocalDay(2026, 10, 24);
      expect(before.addDays(1), LocalDay(2026, 10, 25));
      expect(before.addDays(2), LocalDay(2026, 10, 26));
      expect(before.daysUntil(LocalDay(2026, 10, 26)), 2);
      expect(LocalDay(2027, 3, 27).daysUntil(LocalDay(2027, 3, 29)), 2);
      expect(LocalDay(2026, 10, 26).daysUntil(before), -2);
      expect(LocalDay(2026, 10, 26).weekday, DateTime.monday);
    });

    test('local day of a moment uses the local calendar day', () {
      final lateEvening = DateTime(2026, 10, 25, 23, 30);
      expect(localDayOfUtc(lateEvening.toUtc()), LocalDay(2026, 10, 25));
      final earlyMorning = DateTime(2026, 10, 26, 0, 15);
      expect(localDayOfUtc(earlyMorning.toUtc()), LocalDay(2026, 10, 26));
    });
  });

  group('JSON', () {
    test('cycle round-trips in the D3a snapshot shape', () {
      final json = {
        'scheduleId': 'schedule',
        'mode': 'cycle',
        'anchorDate': '2026-10-20',
        'validFrom': '2026-10-21',
        'slots': [
          {'planId': 'Push'},
          {'planId': null},
        ],
        'shifts': [
          {'fromDate': '2026-10-23', 'days': 1},
        ],
        'exceptions': [
          {'date': '2026-10-22', 'planId': 'Push', 'movedToDate': '2026-10-23'},
          {'date': '2026-10-24', 'planId': 'Push', 'movedToDate': null},
        ],
        'updatedAtUtc': '2026-10-21T08:00:00.000Z',
      };
      final schedule = TrainingSchedule.fromJson(json);
      expect(schedule.mode, TrainingScheduleMode.cycle);
      expect(schedule.anchorDate, LocalDay(2026, 10, 20));
      expect(schedule.slots, const [_push, _rest]);
      expect(schedule.exceptions.last.isSkip, isTrue);
      expect(schedule.toJson(), json);
    });

    test('weekly has no anchor date', () {
      final schedule = _weekly(['Push', null, null, null, null, null, null]);
      final json = schedule.toJson();
      expect(json['mode'], 'weekly');
      expect(json.containsKey('anchorDate'), isTrue);
      expect(json['anchorDate'], isNull);
      expect(json.containsKey('deletedAtUtc'), isFalse);
      expect(TrainingSchedule.fromJson(json).slots, hasLength(7));
    });

    test('unknown mode is rejected', () {
      expect(
        () => TrainingSchedule.fromJson({
          'scheduleId': 's',
          'mode': 'monthly',
          'validFrom': '2026-10-21',
          'slots': <Object?>[],
        }),
        throwsFormatException,
      );
    });
  });

  group('Slot-Regeln', () {
    final active = {'Push', 'Pull'};

    test('a cycle of rest days only cannot be saved', () {
      expect(
        validateScheduleSlots(TrainingScheduleMode.cycle, const [
          _rest,
          _rest,
        ], active),
        'Mindestens ein Tag braucht einen Plan.',
      );
    });

    test('an archived plan does not count as a plan', () {
      expect(
        validateScheduleSlots(TrainingScheduleMode.cycle, const [
          _legs,
          _rest,
        ], active),
        isNotNull,
      );
    });

    test('cycle has 1 to 28 slots, weekly exactly 7', () {
      expect(
        validateScheduleSlots(TrainingScheduleMode.cycle, const [
          _push,
        ], active),
        isNull,
      );
      expect(
        validateScheduleSlots(TrainingScheduleMode.cycle, const [], active),
        isNotNull,
      );
      expect(
        validateScheduleSlots(
          TrainingScheduleMode.cycle,
          List.filled(29, _push),
          active,
        ),
        isNotNull,
      );
      expect(
        validateScheduleSlots(
          TrainingScheduleMode.weekly,
          List.filled(6, _push),
          active,
        ),
        isNotNull,
      );
      expect(
        validateScheduleSlots(
          TrainingScheduleMode.weekly,
          List.filled(7, _push),
          active,
        ),
        isNull,
      );
    });
  });

  group('Vorschau', () {
    test('Zyklus anlegen: Push heute, dann Pull, Beine, Ruhe, Push', () {
      final projection = _project(_cycle(const [_push, _pull, _legs, _rest]));
      final days = projection.days(_today, _today.addDays(4));
      expect(
        [for (final day in days) day.effective.firstOrNull?.planId],
        ['Push', 'Pull', 'Beine', null, 'Push'],
      );
      expect(days[3].baseKind, ScheduleBaseKind.rest);
      expect(days[0].trainings.single.status, ScheduledTrainingStatus.planned);
    });

    test('Heute ist ein anderer Slot: Anker liegt davor', () {
      final schedule = _cycle(const [
        _push,
        _pull,
        _legs,
        _rest,
      ], todaySlotIndex: 2);
      expect(schedule.anchorDate, _today.addDays(-2));
      final projection = _project(schedule);
      expect(_effective(projection, _today), ['Beine']);
      expect(_effective(projection, _today.addDays(2)), ['Push']);
      expect(schedule.cycleSlotIndexOn(_today), 2);
    });

    test('Feste Tage: heute Mittwoch Beine, kommender Montag Push', () {
      final projection = _project(
        _weekly([
          'Push',
          'Pull',
          'Beine',
          null,
          'Oberkörper',
          'Unterkörper',
          null,
        ]),
      );
      expect(_effective(projection, _today), ['Beine']);
      expect(_effective(projection, LocalDay(2026, 10, 26)), ['Push']);
      expect(_effective(projection, LocalDay(2026, 10, 25)), isEmpty);
      expect(
        projection.day(LocalDay(2026, 10, 25)).baseKind,
        ScheduleBaseKind.rest,
      );
    });

    test('Zyklus von 8 Tagen wandert über Wochengrenzen', () {
      final monday = LocalDay(2026, 10, 19);
      final projection = _project(
        _cycle(const [
          _push,
          _pull,
          _legs,
          _rest,
          _push,
          _pull,
          _legs,
          _rest,
        ], today: monday),
        today: monday,
      );
      expect(_effective(projection, monday), ['Push']);
      // Montag der Folgewoche ist Ruhetag, Dienstag Push.
      expect(_effective(projection, monday.addDays(7)), isEmpty);
      expect(_effective(projection, monday.addDays(8)), ['Push']);
    });

    test('Archivierter Plan ist ein Ruhetag und wird markiert', () {
      final plans = [
        _plan('Push'),
        _plan('Pull'),
        _plan('Beine', archived: true),
      ];
      final projection = _project(
        _cycle(const [_push, _pull, _legs]),
        plans: plans,
      );
      final legsDay = projection.day(_today.addDays(2));
      expect(legsDay.baseKind, ScheduleBaseKind.rest);
      expect(legsDay.trainings, isEmpty);
      expect(legsDay.archivedPlanId, 'Beine');
      expect(legsDay.slotIndex, 2);
    });

    test('Unbekannter Plan zählt wie ein archivierter als Ruhetag', () {
      final projection = _project(
        _cycle(const [_push, TrainingScheduleSlot(planId: 'Fremd')]),
      );
      expect(projection.day(_today.addDays(1)).baseKind, ScheduleBaseKind.rest);
    });

    test('Vor dem Gültig-ab-Datum gibt es nichts Geplantes', () {
      final projection = _project(_cycle(const [_push]));
      final yesterday = projection.day(_today.addDays(-1));
      expect(yesterday.baseKind, ScheduleBaseKind.none);
      expect(yesterday.trainings, isEmpty);
    });

    test('Ohne Rhythmus ist jeder Tag leer', () {
      final projection = _project(null);
      expect(projection.day(_today).baseKind, ScheduleBaseKind.none);
      expect(projection.nextPlannedAfter(_today), isNull);
      expect(
        projection.actionsFor(
          ScheduledTraining(
            planId: 'Push',
            planName: 'Push',
            date: _today,
            originDate: _today,
            status: ScheduledTrainingStatus.planned,
          ),
        ),
        isEmpty,
      );
    });

    test('Negativer Index vor dem Anker bleibt im Zyklus', () {
      // Ein Server-Stand darf den Anker nach dem Gültig-ab-Datum haben.
      final schedule = TrainingSchedule(
        scheduleId: 's',
        mode: TrainingScheduleMode.cycle,
        anchorDate: LocalDay(2026, 10, 25),
        validFrom: LocalDay(2026, 10, 20),
        slots: const [_push, _pull, _legs, _rest],
      );
      final projection = _project(schedule, today: LocalDay(2026, 10, 20));
      expect(projection.day(LocalDay(2026, 10, 24)).slotIndex, 3);
      expect(_effective(projection, LocalDay(2026, 10, 23)), ['Beine']);
      expect(_effective(projection, LocalDay(2026, 10, 21)), ['Push']);
      expect(schedule.cycleSlotIndexOn(LocalDay(2026, 10, 20)), 3);
    });

    test('Sommerzeitwechsel verschiebt keinen Tag', () {
      // Anker vor dem Wechsel am 25.10.2026 (Europe/Berlin).
      final anchor = LocalDay(2026, 10, 23);
      final schedule = _cycle(const [_push, _pull, _rest], today: anchor);
      final projection = _project(
        schedule,
        today: LocalDay(2026, 10, 28),
        workouts: [
          // Spät am Abend des Umstellungstags, nach dem Wechsel.
          _workout(
            LocalDay(2026, 10, 25),
            planId: 'Pull',
            hour: 23,
            minute: 30,
          ),
          // Kurz nach Mitternacht zählt für den Folgetag.
          _workout(LocalDay(2026, 10, 26), planId: 'Push', hour: 0, minute: 30),
        ],
      );
      expect(_effective(projection, LocalDay(2026, 10, 25)), isEmpty);
      expect(_effective(projection, LocalDay(2026, 10, 26)), ['Push']);
      expect(_effective(projection, LocalDay(2026, 10, 27)), ['Pull']);
      expect(
        _single(projection, LocalDay(2026, 10, 26)).status,
        ScheduledTrainingStatus.done,
      );
      expect(
        _single(projection, LocalDay(2026, 10, 24)).status,
        ScheduledTrainingStatus.missed,
      );
      // Auch über den Frühjahrswechsel hinweg bleibt der Takt.
      final march = LocalDay(2027, 3, 29);
      expect(projection.day(march).slotIndex, anchor.daysUntil(march) % 3);
    });
  });

  group('Erfüllung und Status', () {
    test('Beine statt Push ändert den Rhythmus nicht', () {
      final projection = _project(
        _cycle(const [_push, _pull, _legs, _rest]),
        workouts: [_workout(_today, planId: 'Beine')],
      );
      expect(
        _single(projection, _today).status,
        ScheduledTrainingStatus.planned,
      );
      expect(_effective(projection, _today.addDays(1)), ['Pull']);
    });

    test('Anderes Training statt Plan: gestern „Stattdessen: Beine“', () {
      final yesterday = _today.addDays(-1);
      final schedule = _cycle(const [
        _push,
        _pull,
        _legs,
        _rest,
      ], today: yesterday);
      final projection = _project(
        schedule,
        workouts: [_workout(yesterday, planId: 'Beine', title: 'Beine')],
      );
      final training = _single(projection, yesterday);
      expect(training.status, ScheduledTrainingStatus.insteadOf);
      expect(training.instead.single.title, 'Beine');
    });

    test('Ein freies Training ohne Plan zählt ebenfalls als stattdessen', () {
      final yesterday = _today.addDays(-1);
      final projection = _project(
        _cycle(const [_push], today: yesterday),
        workouts: [_workout(yesterday, title: 'Freies Training')],
      );
      expect(
        _single(projection, yesterday).status,
        ScheduledTrainingStatus.insteadOf,
      );
    });

    test('Erledigt: beendetes Training aus dem Plan am selben Tag', () {
      final yesterday = _today.addDays(-1);
      final projection = _project(
        _cycle(const [_pull, _push], today: yesterday),
        workouts: [_workout(yesterday, planId: 'Pull')],
      );
      final training = _single(projection, yesterday);
      expect(training.status, ScheduledTrainingStatus.done);
      expect(training.completedBy, hasLength(1));
    });

    test('Training gelöscht: Pull gilt gestern als verpasst', () {
      final yesterday = _today.addDays(-1);
      final projection = _project(
        _cycle(const [_pull, _push], today: yesterday),
        workouts: [_workout(yesterday, planId: 'Pull', deleted: true)],
      );
      expect(
        _single(projection, yesterday).status,
        ScheduledTrainingStatus.missed,
      );
    });

    test('Laufendes Training erfüllt nichts', () {
      final projection = _project(
        _cycle(const [_push]),
        workouts: [_workout(_today, planId: 'Push', finished: false)],
      );
      expect(
        _single(projection, _today).status,
        ScheduledTrainingStatus.planned,
      );
    });

    test('Training am Vortag erfüllt den Plan heute nicht', () {
      final projection = _project(
        _cycle(const [_push]),
        workouts: [_workout(_today.addDays(-1), planId: 'Push')],
      );
      expect(
        _single(projection, _today).status,
        ScheduledTrainingStatus.planned,
      );
    });

    test('Heute erledigt', () {
      final projection = _project(
        _cycle(const [_push, _rest]),
        workouts: [_workout(_today, planId: 'Push', hour: 7)],
      );
      expect(_single(projection, _today).status, ScheduledTrainingStatus.done);
    });

    test(
      'Zwei Trainings am Tag: das erledigte zählt nicht als stattdessen',
      () {
        final monday = LocalDay(2026, 10, 19);
        var schedule = _weekly([
          'Push',
          'Pull',
          null,
          null,
          null,
          null,
          null,
        ], validFrom: monday);
        schedule = schedule.moveSingle(monday, 'Push', monday.addDays(1));
        final projection = _project(
          schedule,
          workouts: [_workout(monday.addDays(1), planId: 'Push')],
        );
        final tuesday = projection.day(monday.addDays(1));
        expect(
          {for (final t in tuesday.trainings) t.planId: t.status},
          {
            'Pull': ScheduledTrainingStatus.missed,
            'Push': ScheduledTrainingStatus.done,
          },
        );
      },
    );
  });

  group('Rhythmus verschieben', () {
    test('Um einen Tag: heute pausiert, dann Push, Pull, Beine, Ruhe', () {
      final schedule = _cycle(const [_push, _pull, _legs, _rest]);
      final projection = _project(schedule);
      final shifted = projection.apply(
        _single(projection, _today),
        const ScheduleAction.shiftRhythm(1),
      );
      expect(shifted.shifts.single.fromDate, _today);
      final after = _project(shifted);
      expect(after.day(_today).baseKind, ScheduleBaseKind.paused);
      expect(after.day(_today).isFree, isTrue);
      expect(
        [
          for (var i = 1; i <= 4; i++)
            after.day(_today.addDays(i)).effective.firstOrNull?.planId,
        ],
        ['Push', 'Pull', 'Beine', null],
      );
    });

    test('Um zwei Tage ab einem künftigen Tag', () {
      final schedule = _cycle(const [_push, _pull, _legs, _rest]);
      final projection = _project(schedule);
      final pullDay = _today.addDays(1);
      final after = _project(
        projection.apply(
          _single(projection, pullDay),
          const ScheduleAction.shiftRhythm(2),
        ),
      );
      expect(_effective(after, _today), ['Push']);
      expect(after.day(pullDay).baseKind, ScheduleBaseKind.paused);
      expect(after.day(pullDay.addDays(1)).baseKind, ScheduleBaseKind.paused);
      expect(_effective(after, pullDay.addDays(2)), ['Pull']);
      expect(_effective(after, pullDay.addDays(3)), ['Beine']);
    });

    test('Mehrfache Verschiebungen addieren sich', () {
      var schedule = _cycle(const [_push, _pull, _legs, _rest]);
      schedule = schedule.shiftRhythm(_today, 1);
      schedule = schedule.shiftRhythm(_today.addDays(1), 1);
      final projection = _project(schedule);
      expect(
        projection.day(_today.addDays(1)).baseKind,
        ScheduleBaseKind.paused,
      );
      expect(_effective(projection, _today.addDays(2)), ['Push']);
      // Gleicher Starttag wächst statt doppelt zu zählen.
      final same = _cycle(const [_push, _pull])
          .shiftRhythm(_today, 1)
          .shiftRhythm(_today, 1);
      expect(same.shifts.single.days, 2);
    });

    test('Feste Tage bieten kein Rhythmus verschieben an', () {
      final projection = _project(
        _weekly(['Push', 'Pull', 'Beine', null, null, null, null]),
      );
      final actions = projection.actionsFor(_single(projection, _today));
      expect(
        actions.where((a) => a.kind == ScheduleActionKind.shiftRhythm),
        isEmpty,
      );
      expect(
        () =>
            _weekly(['Push', null, null, null, null, null, null])
                .shiftRhythm(_today, 1),
        throwsStateError,
      );
    });

    test('Spätere Ausnahme wird durch Verschieben wirkungslos', () {
      var schedule = _cycle(const [_push, _pull, _legs, _rest]);
      schedule = schedule.skip(_today.addDays(2), 'Beine');
      final projection = _project(schedule);
      expect(projection.exceptionsVoidedByShift(_today, 1), 1);
      final after = _project(schedule.shiftRhythm(_today, 1));
      // An Tag +2 steht jetzt Pull; das Überspringen von Beine gilt nicht mehr.
      expect(_effective(after, _today.addDays(2)), ['Pull']);
      expect(_effective(after, _today.addDays(3)), ['Beine']);
    });
  });

  group('Einzelnes Training', () {
    test(
      'Nur dieses auf morgen: Montag verschoben, Dienstag Push und Pull',
      () {
        final monday = LocalDay(2026, 10, 19);
        final schedule = _weekly([
          'Push',
          'Pull',
          null,
          null,
          null,
          null,
          null,
        ], validFrom: monday);
        final projection = _project(schedule, today: monday);
        final push = _single(projection, monday);
        final moved = projection.apply(
          push,
          ScheduleAction.moveSingle(monday.addDays(1)),
        );
        final after = _project(moved, today: monday);
        final mondayTraining = _single(after, monday);
        expect(mondayTraining.status, ScheduledTrainingStatus.moved);
        expect(mondayTraining.movedToDate, monday.addDays(1));
        expect(after.day(monday).isFree, isTrue);
        expect(_effective(after, monday.addDays(1)), ['Pull', 'Push']);
        final movedIn = after.day(monday.addDays(1)).trainings.last;
        expect(movedIn.isMovedIn, isTrue);
        expect(movedIn.originDate, monday);
        // Andere Tage bleiben unverändert.
        expect(_effective(after, monday.addDays(7)), ['Push']);
      },
    );

    test('Überspringen: heute übersprungen, morgen bleibt Beine', () {
      final schedule = _cycle(const [
        _push,
        _pull,
        _legs,
        _rest,
      ], todaySlotIndex: 1);
      final projection = _project(schedule);
      final after = _project(
        projection.apply(
          _single(projection, _today),
          const ScheduleAction.skip(),
        ),
      );
      expect(_single(after, _today).status, ScheduledTrainingStatus.skipped);
      expect(_effective(after, _today.addDays(1)), ['Beine']);
    });

    test('Überspringen aufheben: heute wieder Pull', () {
      final schedule = _cycle(const [_pull, _legs]).skip(_today, 'Pull');
      final projection = _project(schedule);
      final skipped = _single(projection, _today);
      expect(projection.actionsFor(skipped), [const ScheduleAction.undo()]);
      final after = _project(
        projection.apply(skipped, const ScheduleAction.undo()),
      );
      expect(_single(after, _today).status, ScheduledTrainingStatus.planned);
      expect(after.schedule!.exceptions, isEmpty);
    });

    test('Verschiebung aufheben geht auch vom Zieltag aus', () {
      final schedule = _cycle(const [_push, _pull])
          .moveSingle(_today, 'Push', _today.addDays(2));
      final projection = _project(schedule);
      final movedIn = projection
          .day(_today.addDays(2))
          .trainings
          .firstWhere((t) => t.isMovedIn);
      expect(
        projection.actionsFor(movedIn),
        contains(const ScheduleAction.undo()),
      );
      final after = _project(
        projection.apply(movedIn, const ScheduleAction.undo()),
      );
      expect(_effective(after, _today), ['Push']);
      expect(_effective(after, _today.addDays(2)), ['Push']);
    });

    test('Ausnahme gilt nur, solange der Plan noch vorgesehen ist', () {
      // Ausnahme für einen Plan, der an dem Tag gar nicht vorgesehen ist.
      final schedule = _cycle(const [_push, _pull])
          .moveSingle(_today, 'Pull', _today.addDays(1));
      final projection = _project(schedule);
      expect(_effective(projection, _today), ['Push']);
      expect(_effective(projection, _today.addDays(1)), ['Pull']);
    });

    test('Erneut verschieben ersetzt die Ausnahme', () {
      var schedule = _cycle(const [_push, _rest, _rest, _rest]);
      schedule = schedule.moveSingle(_today, 'Push', _today.addDays(1));
      final projection = _project(schedule);
      final movedIn = _single(projection, _today.addDays(1));
      final again = projection.apply(
        movedIn,
        ScheduleAction.moveSingle(_today.addDays(2)),
      );
      expect(again.exceptions, hasLength(1));
      final after = _project(again);
      expect(_effective(after, _today.addDays(1)), isEmpty);
      expect(_effective(after, _today.addDays(2)), ['Push']);
    });
  });

  group('Verpasstes nachholen', () {
    test('Nachholen bei festen Tagen: Montag verschoben auf Mittwoch', () {
      final monday = LocalDay(2026, 10, 19);
      final schedule = _weekly([
        'Push',
        null,
        null,
        null,
        null,
        null,
        null,
      ], validFrom: monday);
      final projection = _project(schedule);
      final missed = _single(projection, monday);
      expect(missed.status, ScheduledTrainingStatus.missed);
      expect(projection.actionsFor(missed), [
        const ScheduleAction.catchUpToday(),
      ]);
      final after = _project(
        projection.apply(missed, const ScheduleAction.catchUpToday()),
      );
      final mondayAfter = _single(after, monday);
      expect(mondayAfter.status, ScheduledTrainingStatus.moved);
      expect(mondayAfter.movedToDate, _today);
      expect(_effective(after, _today), ['Push']);
      expect(_single(after, _today).isOpen, isTrue);
    });

    test(
      'Ab heute weiter im Zyklus: heute Push, morgen Pull, davor pausiert',
      () {
        final dayBefore = _today.addDays(-2);
        final schedule = _cycle(const [
          _push,
          _pull,
          _legs,
          _rest,
        ], today: dayBefore);
        final projection = _project(schedule);
        final missed = _single(projection, dayBefore);
        expect(missed.status, ScheduledTrainingStatus.missed);
        expect(
          projection.actionsFor(missed),
          containsAll([
            const ScheduleAction.catchUpToday(),
            const ScheduleAction.continueFromToday(),
          ]),
        );
        final after = _project(
          projection.apply(missed, const ScheduleAction.continueFromToday()),
        );
        expect(after.day(dayBefore).baseKind, ScheduleBaseKind.paused);
        expect(after.day(_today.addDays(-1)).baseKind, ScheduleBaseKind.paused);
        expect(_effective(after, _today), ['Push']);
        expect(_effective(after, _today.addDays(1)), ['Pull']);
      },
    );

    test('Genau 7 Tage alt lässt sich noch nachholen', () {
      final weekAgo = _today.addDays(-7);
      final projection = _project(_cycle(const [_push, _rest], today: weekAgo));
      expect(projection.actionsFor(_single(projection, weekAgo)), isNotEmpty);
    });

    test('Zu alt zum Nachholen: verpasst, aber ohne Aktion', () {
      final nineDaysAgo = _today.addDays(-9);
      final projection = _project(
        _cycle(const [_push, _rest, _rest], today: nineDaysAgo),
      );
      final missed = _single(projection, nineDaysAgo);
      expect(missed.status, ScheduledTrainingStatus.missed);
      expect(projection.actionsFor(missed), isEmpty);
      expect(
        () => projection.apply(missed, const ScheduleAction.catchUpToday()),
        throwsStateError,
      );
    });
  });

  group('Gültig ab', () {
    test(
      'Rhythmus geändert: gestern nicht verpasst, morgen ohne Überspringen',
      () {
        final yesterday = _today.addDays(-1);
        var schedule = _cycle(const [_push, _pull, _legs], today: yesterday);
        schedule = schedule.skip(_today.addDays(1), 'Beine');
        expect(
          _single(_project(schedule), yesterday).status,
          ScheduledTrainingStatus.missed,
        );
        final changed = schedule.withRhythm(
          mode: TrainingScheduleMode.cycle,
          slots: const [_legs, _push, _pull],
          today: _today,
        );
        expect(changed.validFrom, _today);
        expect(changed.shifts, isEmpty);
        expect(changed.exceptions, isEmpty);
        final after = _project(changed);
        expect(after.day(yesterday).trainings, isEmpty);
        expect(_effective(after, _today.addDays(1)), ['Push']);
      },
    );

    test('Wechsel zu festen Tagen entfernt den Anker', () {
      final changed = _cycle(const [_push]).withRhythm(
        mode: TrainingScheduleMode.weekly,
        slots: List.filled(7, _push),
        today: _today,
      );
      expect(changed.anchorDate, isNull);
      expect(changed.toJson()['anchorDate'], isNull);
    });
  });

  group('Aktionen', () {
    test(
      'Künftiges Training im Zyklus: verschieben, nur dieses, überspringen',
      () {
        final projection = _project(_cycle(const [_push, _pull, _legs, _rest]));
        final friday = _today.addDays(2);
        expect(projection.actionsFor(_single(projection, friday)), [
          const ScheduleAction.shiftRhythm(1),
          const ScheduleAction.shiftRhythm(2),
          ScheduleAction.moveSingle(friday.addDays(1)),
          ScheduleAction.moveSingle(friday.addDays(2)),
          const ScheduleAction.skip(),
        ]);
      },
    );

    test('Erledigt und stattdessen haben keine Aktionen', () {
      final yesterday = _today.addDays(-1);
      final projection = _project(
        _cycle(const [_push, _pull], today: yesterday),
        workouts: [
          _workout(yesterday, planId: 'Beine'),
          _workout(_today, planId: 'Pull'),
        ],
      );
      expect(projection.actionsFor(_single(projection, yesterday)), isEmpty);
      expect(projection.actionsFor(_single(projection, _today)), isEmpty);
    });

    test('Vergangenes Überspringen lässt sich nicht aufheben', () {
      final yesterday = _today.addDays(-1);
      final schedule = _cycle(const [
        _push,
      ], today: yesterday).skip(yesterday, 'Push');
      final projection = _project(schedule);
      expect(projection.actionsFor(_single(projection, yesterday)), isEmpty);
    });

    test('Verschiebung in die Vergangenheit lässt sich nicht aufheben', () {
      final dayBefore = _today.addDays(-2);
      final schedule = _cycle(const [
        _push,
        _rest,
        _rest,
      ], today: dayBefore).moveSingle(dayBefore, 'Push', dayBefore.addDays(1));
      final projection = _project(schedule);
      expect(projection.actionsFor(_single(projection, dayBefore)), isEmpty);
    });
  });

  group('Nächstes Training', () {
    test('Ruhetag: Nächstes Pull am Donnerstag', () {
      final projection = _project(
        _weekly([null, null, null, 'Pull', null, null, null]),
      );
      expect(projection.day(_today).isFree, isTrue);
      final next = projection.nextPlannedAfter(_today);
      expect(next?.planId, 'Pull');
      expect(next?.date.weekday, DateTime.thursday);
    });

    test('Pausierte Tage werden übersprungen', () {
      final schedule = _cycle(const [_push, _pull]).shiftRhythm(_today, 2);
      final next = _project(schedule).nextPlannedAfter(_today);
      expect(next?.date, _today.addDays(2));
      expect(next?.planId, 'Push');
    });
  });

  group('Verdichten', () {
    /// Vergleichbarer Abdruck eines Tages der Vorschau.
    List<Object?> fingerprint(ScheduleDay day) => [
      day.baseKind,
      day.slotIndex,
      for (final t in day.trainings)
        (t.planId, t.status, t.originDate, t.movedToDate, t.isMovedIn),
    ];

    test('Vorschau der letzten 400 Tage und der nächsten 60 bleibt gleich', () {
      // Zyklus seit gut zwei Jahren mit Verschiebungen und Ausnahmen über die
      // ganze Zeit, auch über die Grenze hinweg.
      final start = _today.addDays(-800);
      var schedule = _cycle(const [_push, _pull, _legs, _rest], today: start);
      final projection0 = _project(schedule, today: start);
      expect(projection0.day(start).effective.single.planId, 'Push');
      for (var offset = 0; offset < 860; offset += 9) {
        final date = start.addDays(offset);
        final plan = _project(schedule).basePlanOn(date);
        if (plan == null) continue;
        schedule = switch (offset % 4) {
          0 => schedule.shiftRhythm(date, 1 + offset % 2),
          1 => schedule.skip(date, plan),
          _ => schedule.moveSingle(date, plan, date.addDays(2)),
        };
      }
      // Ausnahme kurz vor der Grenze, deren Ziel dahinter liegt.
      final cutoff = _today.addDays(-400);
      final before = cutoff.addDays(-1);
      final planBefore = _project(schedule).basePlanOn(before);
      if (planBefore != null) {
        schedule = schedule.moveSingle(before, planBefore, cutoff.addDays(1));
      }
      final workouts = [
        _workout(cutoff.addDays(3), planId: 'Push'),
        _workout(_today.addDays(-2), title: 'Frei'),
      ];

      final compacted = schedule.compacted(_today);
      expect(compacted.shifts.length, lessThan(schedule.shifts.length));
      expect(compacted.exceptions.length, lessThan(schedule.exceptions.length));
      expect(compacted.validFrom.isAfter(schedule.validFrom), isTrue);

      final original = _project(schedule, workouts: workouts);
      final after = _project(compacted, workouts: workouts);
      for (
        var date = cutoff;
        !date.isAfter(_today.addDays(60));
        date = date.addDays(1)
      ) {
        expect(
          fingerprint(after.day(date)),
          fingerprint(original.day(date)),
          reason: date.toIso(),
        );
      }
      // Erneutes Verdichten ändert nichts mehr.
      expect(compacted.compacted(_today).toJson(), compacted.toJson());
    });

    test('Ein junger Rhythmus bleibt unverändert', () {
      final schedule = _cycle(const [_push, _pull]).skip(_today, 'Push');
      expect(identical(schedule.compacted(_today), schedule), isTrue);
    });
  });

  group('Effektiv gleicher Rhythmus', () {
    test('Ein verschobener Zyklus mit gleichen Slots ist unverändert', () {
      final schedule = _cycle(const [
        _push,
        _pull,
        _legs,
      ], today: _today.addDays(-3)).shiftRhythm(_today.addDays(-1), 1);
      final index = schedule.effectiveCycleIndex(_today)!;
      expect(
        schedule.hasSameRhythm(
          mode: TrainingScheduleMode.cycle,
          slots: const [_push, _pull, _legs],
          today: _today,
          todaySlotIndex: index,
        ),
        isTrue,
      );
      expect(
        schedule.hasSameRhythm(
          mode: TrainingScheduleMode.cycle,
          slots: const [_push, _pull, _legs],
          today: _today,
          todaySlotIndex: (index + 1) % 3,
        ),
        isFalse,
      );
      expect(
        schedule.hasSameRhythm(
          mode: TrainingScheduleMode.cycle,
          slots: const [_push, _legs, _pull],
          today: _today,
          todaySlotIndex: index,
        ),
        isFalse,
      );
    });

    test('An einem pausierten Tag gilt der Slot vor dem nächsten Training', () {
      final schedule = _cycle(const [_push, _pull, _legs])
          .shiftRhythm(_today, 2);
      // Heute und morgen pausiert, übermorgen Push (Slot 0).
      expect(schedule.cycleSlotIndexOn(_today), isNull);
      expect(schedule.effectiveCycleIndex(_today), 1);
    });
  });
}
