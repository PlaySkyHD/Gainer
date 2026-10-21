import 'package:flutter/foundation.dart';

import '../../../data/repositories/cardio/cardio_repository.dart';
import '../../../data/repositories/nutrition/nutrition_repository.dart';
import '../../../data/repositories/training/training_log_repository.dart';
import '../../../domain/models/body/body_tracking.dart';
import '../../../domain/models/cardio/cardio_session.dart';
import '../../../domain/models/nutrition/nutrition.dart';
import '../../../domain/models/training/training_schedule.dart';
import '../../../domain/models/training/training_statistics.dart';
import '../../../domain/models/training/workout_model.dart';

/// Markierungen eines Tages im Monatsraster, in fester Reihenfolge.
enum CalendarMarker {
  /// Krafttraining beendet.
  strength('Krafttraining'),

  /// Cardio-Einheit beendet.
  cardio('Cardio'),

  /// Check-in vorhanden.
  checkIn('Check-in'),

  /// Training geplant (heute oder künftig, noch offen).
  planned('Training geplant'),

  /// Geplantes Training verpasst.
  missed('Training verpasst');

  const CalendarMarker(this.label);

  /// Beschriftung für VoiceOver.
  final String label;
}

LocalDay? _tryParseDay(String value) {
  try {
    return LocalDay.parse(value);
  } on FormatException {
    return null;
  }
}

/// Ein beendetes Krafttraining mit Kennzahlen für die Tagesansicht.
class CalendarWorkout {
  const CalendarWorkout({required this.workout, required this.volumeKg});

  final Workout workout;

  /// Volumen der gezählten Sätze in kg, ohne Aufwärmsätze.
  final double volumeKg;

  Duration get duration => workout.endedAtUtc!.difference(workout.startedAtUtc);
}

/// Ernährung eines Tages mit Ziel, sofern eine Zielphase gilt.
class CalendarNutrition {
  const CalendarNutrition({
    required this.kilocalories,
    this.proteinGrams,
    this.targetKilocalories,
    this.targetProteinGrams,
  });

  final double kilocalories;
  final double? proteinGrams;
  final double? targetKilocalories;
  final double? targetProteinGrams;
}

/// Alles, was an einem Tag passiert ist oder geplant war.
class CalendarDay {
  const CalendarDay({
    required this.date,
    required this.schedule,
    this.workouts = const [],
    this.cardio = const [],
    this.nutrition,
    this.checkIn,
  });

  final LocalDay date;
  final ScheduleDay schedule;
  final List<CalendarWorkout> workouts;
  final List<CardioSession> cardio;

  /// Null, wenn an dem Tag nichts gegessen erfasst wurde.
  final CalendarNutrition? nutrition;
  final DailyCheckIn? checkIn;

  /// Gibt es erfasste Einträge (Training, Cardio, Ernährung, Check-in)?
  bool get hasEntries =>
      workouts.isNotEmpty ||
      cardio.isNotEmpty ||
      nutrition != null ||
      checkIn != null;

  /// Markierungen in fester Reihenfolge; Ernährung erzeugt keine.
  List<CalendarMarker> markersFor(LocalDay today) => [
    if (workouts.isNotEmpty) CalendarMarker.strength,
    if (cardio.isNotEmpty) CalendarMarker.cardio,
    if (checkIn != null) CalendarMarker.checkIn,
    if (!date.isBefore(today) && schedule.effective.any((t) => t.isOpen))
      CalendarMarker.planned,
    if (schedule.trainings.any(
      (t) => t.status == ScheduledTrainingStatus.missed,
    ))
      CalendarMarker.missed,
  ];
}

/// Lädt den sichtbaren Monat (volle Wochen Mo–So) in einem Durchlauf aus den
/// lokalen Repositories. Braucht keine Verbindung.
class CalendarViewModel extends ChangeNotifier {
  CalendarViewModel({required this.training, this.cardio, this.nutrition})
    : _today = training.schedule.today() {
    _month = LocalDay(_today.year, _today.month, 1);
    _selected = _today;
  }

  final TrainingLogRepository training;
  final CardioRepository? cardio;
  final NutritionRepository? nutrition;

  LocalDay _today;
  late LocalDay _month;
  late LocalDay _selected;
  Map<LocalDay, CalendarDay> _days = const {};
  TrainingScheduleProjection? _projection;
  bool _isLoading = false;
  String? _errorMessage;
  bool _disposed = false;
  int _generation = 0;
  Future<void>? _running;
  bool _rerun = false;

  /// Heutiger lokaler Tag, beim Laden neu bestimmt.
  LocalDay get today => _today;

  /// Erster Tag des angezeigten Monats.
  LocalDay get month => _month;
  LocalDay get selected => _selected;
  TrainingScheduleProjection? get projection => _projection;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// True, sobald ein Monat geladen wurde.
  bool get isLoaded => _projection != null;

  bool get isCurrentMonth =>
      _month.year == _today.year && _month.month == _today.month;

  /// Sichtbare Tage: volle Wochen von Montag bis Sonntag.
  List<LocalDay> get visibleDays => visibleDaysOf(_month);

  static List<LocalDay> visibleDaysOf(LocalDay month) {
    final first = LocalDay(month.year, month.month, 1);
    final last = LocalDay(month.year, month.month + 1, 0);
    final start = first.addDays(1 - first.weekday);
    final end = last.addDays(7 - last.weekday);
    return [for (var day = start; !day.isAfter(end); day = day.addDays(1)) day];
  }

  /// Daten eines sichtbaren Tages; null außerhalb des geladenen Bereichs.
  CalendarDay? day(LocalDay date) => _days[date];

  CalendarDay? get selectedDay => _days[_selected];

  bool isInMonth(LocalDay date) =>
      date.year == _month.year && date.month == _month.month;

  void select(LocalDay date) {
    if (date == _selected) return;
    _selected = date;
    if (!isInMonth(date)) {
      _month = LocalDay(date.year, date.month, 1);
      _notify();
      load();
      return;
    }
    _notify();
  }

  /// Wechselt um [delta] Monate. Gewählt ist danach heute, falls er im Monat
  /// liegt, sonst der Erste.
  Future<void> changeMonth(int delta) {
    final next = LocalDay(_month.year, _month.month + delta, 1);
    _month = next;
    _selected = isInMonth(_today) ? _today : next;
    _notify();
    return load();
  }

  /// Springt zum aktuellen Monat und wählt heute.
  Future<void> goToToday() {
    _today = training.schedule.today();
    _month = LocalDay(_today.year, _today.month, 1);
    _selected = _today;
    _notify();
    return load();
  }

  /// Lädt den angezeigten Monat neu. Laufende Ladevorgänge werden nicht
  /// doppelt gestartet; ein Aufruf währenddessen lädt danach noch einmal.
  Future<void> load() {
    final running = _running;
    if (running != null) {
      _rerun = true;
      return running;
    }
    final run = _loadLoop();
    _running = run;
    return run.whenComplete(() => _running = null);
  }

  Future<void> _loadLoop() async {
    do {
      _rerun = false;
      await _loadOnce();
    } while (_rerun && !_disposed);
  }

  Future<void> _loadOnce() async {
    if (_disposed) return;
    final generation = ++_generation;
    final previousToday = _today;
    _today = training.schedule.today();
    // Nach Mitternacht wandert die Auswahl von gestern auf den neuen Tag.
    if (_selected == previousToday && _today != previousToday) {
      _selected = _today;
      _month = LocalDay(_today.year, _today.month, 1);
    }
    final month = _month;
    _isLoading = true;
    _notify();
    try {
      final days = visibleDaysOf(month);
      final result = await _read(days.first, days.last, _today);
      if (_disposed || generation != _generation) return;
      _days = result.days;
      _projection = result.projection;
      _errorMessage = null;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      _errorMessage = 'Der Kalender konnte nicht geladen werden.';
    } finally {
      if (!_disposed && generation == _generation) {
        _isLoading = false;
        _notify();
      }
    }
  }

  Future<
    ({Map<LocalDay, CalendarDay> days, TrainingScheduleProjection projection})
  >
  _read(LocalDay from, LocalDay to, LocalDay today) async {
    final workouts = await training.readDiary();
    final plans = await training.readPlans(includeArchived: true);
    final schedule = await training.schedule.read();
    final checkIns = await training.readCheckIns();
    final ownExercises = await training.readOwnExercises();
    final sessions = await cardio?.readSessions() ?? const <CardioSession>[];
    final food = await nutrition?.readDays(from.toIso(), to.toIso());

    final projection = TrainingScheduleProjection(
      schedule: schedule,
      plans: plans,
      workouts: workouts,
      today: today,
    );

    bool inRange(LocalDay day) => !day.isBefore(from) && !day.isAfter(to);

    final workoutsByDay = <LocalDay, List<CalendarWorkout>>{};
    for (final workout in workouts.reversed) {
      if (!isCountedWorkout(workout)) continue;
      final day = localDayOfUtc(workout.startedAtUtc);
      if (!inRange(day)) continue;
      final stats = workoutExerciseStats(
        workout,
        checkIns: checkIns,
        catalog: ownExercises,
      );
      workoutsByDay
          .putIfAbsent(day, () => [])
          .add(
            CalendarWorkout(
              workout: workout,
              volumeKg: stats.fold<double>(0, (sum, s) => sum + s.volumeKg),
            ),
          );
    }

    final cardioByDay = <LocalDay, List<CardioSession>>{};
    for (final session in sessions.reversed) {
      final day = localDayOfUtc(session.startedAtUtc);
      if (!inRange(day)) continue;
      cardioByDay.putIfAbsent(day, () => []).add(session);
    }

    final checkInByDay = <LocalDay, DailyCheckIn>{
      for (final checkIn in checkIns)
        if (_tryParseDay(checkIn.localDate) case final day? when inRange(day))
          day: checkIn,
    };

    final nutritionByDay = <LocalDay, CalendarNutrition>{};
    for (final entry in food?.days ?? const <NutritionDay>[]) {
      if (entry.entries.isEmpty) continue;
      final day = _tryParseDay(entry.localDate);
      if (day == null) continue;
      final target = food?.targets?.targetOn(entry.localDate);
      nutritionByDay[day] = CalendarNutrition(
        kilocalories: entry.totals.kilocalories,
        proteinGrams: entry.totals.proteinGrams,
        targetKilocalories: target?.kilocalories,
        targetProteinGrams: target?.proteinGrams,
      );
    }

    return (
      days: {
        for (final day in projection.days(from, to))
          day.date: CalendarDay(
            date: day.date,
            schedule: day,
            workouts: workoutsByDay[day.date] ?? const [],
            cardio: cardioByDay[day.date] ?? const [],
            nutrition: nutritionByDay[day.date],
            checkIn: checkInByDay[day.date],
          ),
      },
      projection: projection,
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
