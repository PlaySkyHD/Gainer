import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/cardio/cardio_repository.dart';
import 'package:gainer_mobile/data/repositories/nutrition/nutrition_repository.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_session.dart';
import 'package:gainer_mobile/domain/models/nutrition/nutrition.dart';
import 'package:gainer_mobile/domain/models/training/training_schedule.dart';
import 'package:gainer_mobile/ui/features/calendar/calendar_view_model.dart';

import 'calendar_test_support.dart';

void main() {
  late CalendarHarness harness;
  late CalendarViewModel model;

  setUp(() async {
    harness = await CalendarHarness.create();
    model = harness.viewModel();
  });

  tearDown(() async {
    model.dispose();
    await harness.dispose();
  });

  LocalDay oct(int day) => LocalDay(2026, 10, day);

  test('starts on today in the current month', () {
    expect(model.today, calendarToday);
    expect(model.selected, calendarToday);
    expect(model.month, LocalDay(2026, 10, 1));
    expect(model.isCurrentMonth, isTrue);
  });

  test('visible days are full weeks from Monday to Sunday', () {
    final days = CalendarViewModel.visibleDaysOf(LocalDay(2026, 10, 1));
    expect(days.first, LocalDay(2026, 9, 28));
    expect(days.last, LocalDay(2026, 11, 1));
    expect(days.length, 35);
    expect(days.first.weekday, DateTime.monday);
    expect(days.last.weekday, DateTime.sunday);

    // Februar 2027 beginnt am Montag und endet am Sonntag: genau vier Wochen.
    final february = CalendarViewModel.visibleDaysOf(LocalDay(2027, 2, 1));
    expect(february.first, LocalDay(2027, 2, 1));
    expect(february.length, 28);
  });

  test('markers: done strength and check-in yesterday, planned tomorrow; '
      'nutrition makes no marker', () async {
    final push = await harness.plan('Push');
    final pull = await harness.plan('Pull');
    // Mi Push, Fr Pull, sonst Ruhetag.
    await harness.weekly([
      null,
      null,
      push.planId,
      null,
      pull.planId,
      null,
      null,
    ]);
    await harness.finishedFromPlan(push, oct(21));
    await harness.checkIn(oct(21));
    await harness.food(oct(20), kcal: 1800, protein: 120);

    await model.load();

    expect(model.day(oct(21))!.markersFor(model.today), [
      CalendarMarker.strength,
      CalendarMarker.checkIn,
    ]);
    expect(model.day(oct(23))!.markersFor(model.today), [
      CalendarMarker.planned,
    ]);
    expect(model.day(oct(20))!.markersFor(model.today), isEmpty);
    expect(model.day(oct(20))!.nutrition, isNotNull);
    expect(model.day(oct(22))!.markersFor(model.today), isEmpty);
  });

  test(
    'missed trainings get a marker, done ones the strength marker',
    () async {
      final push = await harness.plan('Push');
      final pull = await harness.plan('Pull');
      // Mo Push, Mi Pull, gültig seit Montag, 12. Oktober.
      await harness.weekly([
        push.planId,
        null,
        pull.planId,
        null,
        null,
        null,
        null,
      ], validFrom: oct(12));
      await harness.finishedFromPlan(push, oct(19));

      await model.load();

      expect(model.day(oct(12))!.markersFor(model.today), [
        CalendarMarker.missed,
      ]);
      expect(model.day(oct(19))!.markersFor(model.today), [
        CalendarMarker.strength,
      ]);
      expect(
        model.day(oct(19))!.schedule.trainings.single.status,
        ScheduledTrainingStatus.done,
      );
      expect(model.day(oct(21))!.markersFor(model.today), [
        CalendarMarker.missed,
      ]);
      // Vor Gültig-ab gibt es nichts zu verpassen.
      expect(model.day(oct(5))!.markersFor(model.today), isEmpty);
      expect(model.day(oct(26))!.markersFor(model.today), [
        CalendarMarker.planned,
      ]);
    },
  );

  test('cardio sessions mark their day in fixed order', () async {
    await harness.finishedEmpty('Ganzkörper', oct(14));
    await harness.cardioOn(oct(14));
    await harness.checkIn(oct(14));

    await model.load();

    final day = model.day(oct(14))!;
    expect(day.markersFor(model.today), [
      CalendarMarker.strength,
      CalendarMarker.cardio,
      CalendarMarker.checkIn,
    ]);
    expect(day.cardio, hasLength(1));
    expect(day.hasEntries, isTrue);
  });

  test('day data has workout duration, volume and nutrition target', () async {
    final pull = await harness.plan('Pull');
    await harness.target(from: '2026-10-01');
    await harness.finishedFromPlan(pull, oct(14));
    await harness.food(oct(14), kcal: 2350, protein: 142);

    await model.load();

    final day = model.day(oct(14))!;
    final workout = day.workouts.single;
    expect(workout.workout.title, 'Pull');
    expect(workout.duration, const Duration(minutes: 58));
    // 3 Sätze × 40 kg × 10 Wiederholungen.
    expect(workout.volumeKg, 1200);
    expect(day.nutrition!.kilocalories, 2350);
    expect(day.nutrition!.targetKilocalories, 2600);
    expect(day.nutrition!.proteinGrams, 142);
    expect(day.nutrition!.targetProteinGrams, 180);
  });

  test('without a schedule no day is planned', () async {
    await model.load();

    expect(model.projection!.schedule, isNull);
    for (final date in model.visibleDays) {
      expect(model.day(date)!.markersFor(model.today), isEmpty);
    }
    expect(model.day(oct(3))!.hasEntries, isFalse);
  });

  test('changing months and back to today', () async {
    await model.load();
    await model.changeMonth(-1);
    await model.changeMonth(-1);

    expect(model.month, LocalDay(2026, 8, 1));
    expect(model.selected, LocalDay(2026, 8, 1));
    expect(model.day(LocalDay(2026, 8, 15)), isNotNull);
    expect(model.isCurrentMonth, isFalse);

    await model.goToToday();

    expect(model.month, LocalDay(2026, 10, 1));
    expect(model.selected, calendarToday);
    expect(model.isCurrentMonth, isTrue);
  });

  test(
    'selecting a day of the neighbouring month switches the month',
    () async {
      await model.load();
      model.select(LocalDay(2026, 11, 1));
      await model.load();

      expect(model.month, LocalDay(2026, 11, 1));
      expect(model.selected, LocalDay(2026, 11, 1));
      expect(model.selectedDay, isNotNull);
    },
  );

  test('reloading shows data saved in the meantime', () async {
    await model.load();
    expect(model.day(calendarToday)!.workouts, isEmpty);

    await harness.finishedEmpty('Abends', calendarToday);
    await model.load();

    expect(model.day(calendarToday)!.workouts.single.workout.title, 'Abends');
    expect(model.day(calendarToday)!.markersFor(model.today), [
      CalendarMarker.strength,
    ]);
  });

  test('concurrent loads coalesce and end with the newest data', () async {
    final first = model.load();
    await harness.finishedEmpty('Spät', oct(20));
    final second = model.load();
    await Future.wait([first, second]);

    expect(model.day(oct(20))!.workouts, hasLength(1));
    expect(model.isLoading, isFalse);
  });

  test('deleted and running workouts do not count', () async {
    final deleted = await harness.finishedEmpty('Gelöscht', oct(15));
    await harness.repository.deleteWorkout(deleted.workoutId);
    harness.training.now = DateTime.utc(2026, 10, 22, 8);
    await harness.repository.startEmpty(title: 'Läuft');
    harness.resetClock();

    await model.load();

    expect(model.day(oct(15))!.workouts, isEmpty);
    expect(model.day(calendarToday)!.workouts, isEmpty);
  });

  test('a failing source keeps grid, plan and the other sources', () async {
    final push = await harness.plan('Push');
    await harness.cycle([push.planId, null]);
    await harness.checkIn(oct(20));
    final failing = CalendarViewModel(
      training: harness.repository,
      cardio: _FailingCardio(harness),
      nutrition: _FailingNutrition(harness),
    );
    addTearDown(failing.dispose);

    await failing.load();

    expect(failing.isLoaded, isTrue);
    expect(failing.visibleDays.every((d) => failing.day(d) != null), isTrue);
    expect(
      failing.day(calendarToday)!.schedule.trainings.single.isOpen,
      isTrue,
    );
    expect(failing.day(oct(20))!.checkIn, isNotNull);
    expect(failing.failedSources, {
      CalendarSource.cardio,
      CalendarSource.nutrition,
    });
    expect(failing.errorMessage, 'Nicht geladen: Cardio, Ernährung.');
  });

  test('month changes reuse history; load reads it again', () async {
    final cardio = _CountingCardio(harness);
    final counting = CalendarViewModel(
      training: harness.repository,
      cardio: cardio,
      nutrition: harness.nutrition,
    );
    addTearDown(counting.dispose);

    await counting.load();
    expect(cardio.reads, 1);

    await counting.changeMonth(-1);
    await counting.changeMonth(1);
    await counting.goToToday();
    expect(cardio.reads, 1);

    await counting.load();
    expect(cardio.reads, 2);
  });

  test('checkToday reloads only when the date changed', () async {
    await model.load();
    expect(model.checkToday(), isFalse);

    harness.training.now = DateTime.utc(2026, 10, 23, 10);
    expect(model.checkToday(), isTrue);
    await model.load();

    expect(model.today, oct(23));
    expect(model.selected, oct(23));
  });
}

class _FailingNutrition extends NutritionRepository {
  _FailingNutrition(CalendarHarness harness)
    : super(store: harness.training.store);

  @override
  Future<({List<NutritionDay> days, NutritionTargetSchedule? targets})>
  readDays(String from, String to) async => throw StateError('kaputt');
}

class _FailingCardio extends CardioRepository {
  _FailingCardio(CalendarHarness harness)
    : super(store: harness.training.store);

  @override
  Future<List<CardioSession>> readSessions() async =>
      throw StateError('kaputt');
}

class _CountingCardio extends CardioRepository {
  _CountingCardio(CalendarHarness harness)
    : super(store: harness.training.store);

  int reads = 0;

  @override
  Future<List<CardioSession>> readSessions() {
    reads++;
    return super.readSessions();
  }
}
