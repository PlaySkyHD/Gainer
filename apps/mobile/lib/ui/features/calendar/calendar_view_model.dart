import 'package:flutter/foundation.dart';

import '../../../data/repositories/cardio/cardio_repository.dart';
import '../../../data/repositories/nutrition/nutrition_repository.dart';
import '../../../data/repositories/training/training_log_repository.dart';
import '../../../domain/models/body/body_tracking.dart';
import '../../../domain/models/cardio/cardio_session.dart';
import '../../../domain/models/nutrition/day_target.dart';
import '../../../domain/models/nutrition/nutrition.dart';
import '../../../domain/models/training/exercise_catalog_model.dart';
import '../../../domain/models/training/training_plan_model.dart';
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

/// Tagesziel der Ernährung aus der Zielphase, die an einem Tag gilt.
class CalendarNutritionTarget {
  const CalendarNutritionTarget({
    required this.kilocalories,
    required this.proteinGrams,
    required this.carbohydrateGrams,
    required this.fatGrams,
    this.saltGrams = NutritionTargetVersion.defaultSaltGrams,
    this.kind,
    this.manual = false,
    this.automaticKind = NutritionDayKind.rest,
  });

  /// Ziel nach Tagesart; [automatic] ist die Tagesart ohne Festlegung.
  CalendarNutritionTarget.of(
    NutritionDayTargetResult result, {
    required NutritionDayKind automatic,
  }) : this(
         kilocalories: result.target.kilocalories,
         proteinGrams: result.target.proteinGrams,
         carbohydrateGrams: result.target.carbohydrateGrams,
         fatGrams: result.target.fatGrams,
         saltGrams: result.effectiveSaltGrams,
         kind: result.kind,
         manual: result.manual,
         automaticKind: automatic,
       );

  final double kilocalories;
  final double proteinGrams;
  final double carbohydrateGrams;
  final double fatGrams;

  /// Salzobergrenze des Tages.
  final double saltGrams;

  /// Tagesart; null ohne Ruhetag-Ziel (dann ohne Bedeutung).
  final NutritionDayKind? kind;

  /// Hat der Nutzer die Tagesart festgelegt?
  final bool manual;

  /// Tagesart ohne Festlegung, für „Automatisch (…)“.
  final NutritionDayKind automaticKind;
}

/// Ernährung eines Tages mit Ziel, sofern eine Zielphase gilt.
class CalendarNutrition {
  const CalendarNutrition({
    required this.kilocalories,
    this.proteinGrams,
    this.carbohydrateGrams,
    this.fatGrams,
    this.saltGrams,
    this.target,
  });

  /// Noch nichts erfasst: alles 0, Ziel wie an dem Tag gültig.
  const CalendarNutrition.empty(CalendarNutritionTarget? target)
    : this(
        kilocalories: 0,
        proteinGrams: 0,
        carbohydrateGrams: 0,
        fatGrams: 0,
        saltGrams: 0,
        target: target,
      );

  final double kilocalories;
  final double? proteinGrams;
  final double? carbohydrateGrams;
  final double? fatGrams;
  final double? saltGrams;
  final CalendarNutritionTarget? target;

  double? get targetKilocalories => target?.kilocalories;
  double? get targetProteinGrams => target?.proteinGrams;
  double? get targetCarbohydrateGrams => target?.carbohydrateGrams;
  double? get targetFatGrams => target?.fatGrams;
  double? get targetSaltGrams => target?.saltGrams;
}

/// Alles, was an einem Tag passiert ist oder geplant war.
class CalendarDay {
  const CalendarDay({
    required this.date,
    required this.schedule,
    this.workouts = const [],
    this.cardio = const [],
    this.nutrition,
    this.nutritionTarget,
    this.checkIn,
  });

  final LocalDay date;
  final ScheduleDay schedule;
  final List<CalendarWorkout> workouts;
  final List<CardioSession> cardio;

  /// Null, wenn an dem Tag nichts gegessen erfasst wurde.
  final CalendarNutrition? nutrition;

  /// Ernährungsziel des Tages, auch ohne erfasste Mahlzeiten.
  final CalendarNutritionTarget? nutritionTarget;
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

/// Lokale Bereiche, die der Kalender liest. Jeder kann unabhängig fehlen.
enum CalendarSource {
  training('Training'),
  schedule('Rhythmus'),
  checkIns('Check-ins'),
  cardio('Cardio'),
  nutrition('Ernährung');

  const CalendarSource(this.label);

  final String label;
}

/// Verlaufsdaten über alle Monate. Sie bleiben beim Monatswechsel erhalten
/// und werden nur bei einem Neuladen gelesen.
class _History {
  const _History({
    required this.workouts,
    required this.plans,
    required this.schedule,
    required this.checkIns,
    required this.exercises,
    required this.sessions,
    required this.failed,
  });

  final List<Workout> workouts;
  final List<TrainingPlanModel> plans;
  final TrainingSchedule? schedule;
  final List<DailyCheckIn> checkIns;
  final List<CatalogExercise> exercises;
  final List<CardioSession> sessions;
  final Set<CalendarSource> failed;
}

/// Lädt den sichtbaren Monat (volle Wochen Mo–So) aus den lokalen
/// Repositories. Braucht keine Verbindung. Fällt eine Quelle aus, bleiben
/// Raster und Plan aus den übrigen Quellen sichtbar.
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
  _History? _history;
  Set<CalendarSource> _failed = const {};
  bool _isLoading = false;
  bool _disposed = false;
  Future<void>? _running;
  bool _rerun = false;
  bool _refreshRequested = false;

  /// Heutiger lokaler Tag, beim Laden neu bestimmt.
  LocalDay get today => _today;

  /// Erster Tag des angezeigten Monats.
  LocalDay get month => _month;
  LocalDay get selected => _selected;
  TrainingScheduleProjection? get projection => _projection;
  bool get isLoading => _isLoading;

  /// Bereiche, die beim letzten Laden nicht gelesen werden konnten.
  Set<CalendarSource> get failedSources => _failed;

  String? get errorMessage => _failed.isEmpty
      ? null
      : 'Nicht geladen: ${[for (final source in _failed) source.label].join(', ')}.';

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
      _load(refresh: false);
      return;
    }
    _notify();
  }

  /// Wechselt um [delta] Monate. Gewählt ist danach heute, falls er im Monat
  /// liegt, sonst der Erste. Nutzt die gelesenen Verlaufsdaten weiter.
  Future<void> changeMonth(int delta) {
    final next = LocalDay(_month.year, _month.month + delta, 1);
    _month = next;
    _selected = isInMonth(_today) ? _today : next;
    _notify();
    return _load(refresh: false);
  }

  /// Springt zum aktuellen Monat und wählt heute.
  Future<void> goToToday() {
    _today = training.schedule.today();
    _month = LocalDay(_today.year, _today.month, 1);
    _selected = _today;
    _notify();
    return _load(refresh: false);
  }

  /// Prüft, ob ein neuer Tag begonnen hat (etwa nach Mitternacht oder bei
  /// Rückkehr in die App), und lädt dann neu. Liefert true bei neuem Tag.
  bool checkToday() {
    if (training.schedule.today() == _today) return false;
    load();
    return true;
  }

  /// Liest alle Quellen neu und berechnet den angezeigten Monat. Laufende
  /// Ladevorgänge werden nicht doppelt gestartet; ein Aufruf währenddessen
  /// lädt danach noch einmal.
  Future<void> load() => _load(refresh: true);

  Future<void> _load({required bool refresh}) {
    if (refresh) _refreshRequested = true;
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
    final previousToday = _today;
    _today = training.schedule.today();
    // Nach Mitternacht wandert die Auswahl von gestern auf den neuen Tag.
    if (_selected == previousToday && _today != previousToday) {
      _selected = _today;
      _month = LocalDay(_today.year, _today.month, 1);
    }
    final month = _month;
    final today = _today;
    _isLoading = true;
    _notify();

    var history = _history;
    if (history == null || _refreshRequested) {
      _refreshRequested = false;
      history = await _readHistory();
      if (_disposed) return;
      _history = history;
    }
    final days = visibleDaysOf(month);
    final failed = {...history.failed};
    final food = await _guard(
      CalendarSource.nutrition,
      failed,
      () async => nutrition?.readDays(days.first.toIso(), days.last.toIso()),
      null,
    );
    if (_disposed) return;

    final projection = TrainingScheduleProjection(
      schedule: history.schedule,
      plans: history.plans,
      workouts: history.workouts,
      today: today,
    );
    _projection = projection;
    _days = _buildDays(days.first, days.last, history, food, projection);
    _failed = failed;
    _isLoading = false;
    _notify();
  }

  /// Liest die Verlaufsquellen parallel; jede darf einzeln fehlschlagen.
  Future<_History> _readHistory() async {
    final failed = <CalendarSource>{};
    final results = await Future.wait<Object?>([
      _guard(
        CalendarSource.training,
        failed,
        training.readDiary,
        const <Workout>[],
      ),
      _guard(
        CalendarSource.training,
        failed,
        () => training.readPlans(includeArchived: true),
        const <TrainingPlanModel>[],
      ),
      _guard(CalendarSource.schedule, failed, training.schedule.read, null),
      _guard(
        CalendarSource.checkIns,
        failed,
        training.readCheckIns,
        const <DailyCheckIn>[],
      ),
      // Fehlt der Katalog, rechnet das Volumen mit Standardfaktoren.
      training.readExercisesOffline().then<List<CatalogExercise>>(
        (value) => value,
        onError: (Object _) => const <CatalogExercise>[],
      ),
      _guard(
        CalendarSource.cardio,
        failed,
        () async => await cardio?.readSessions() ?? const <CardioSession>[],
        const <CardioSession>[],
      ),
    ]);
    return _History(
      workouts: results[0]! as List<Workout>,
      plans: results[1]! as List<TrainingPlanModel>,
      schedule: results[2] as TrainingSchedule?,
      checkIns: results[3]! as List<DailyCheckIn>,
      exercises: results[4]! as List<CatalogExercise>,
      sessions: results[5]! as List<CardioSession>,
      failed: failed,
    );
  }

  static Future<T> _guard<T>(
    CalendarSource source,
    Set<CalendarSource> failed,
    Future<T> Function() read,
    T fallback,
  ) async {
    try {
      return await read();
    } on Object {
      failed.add(source);
      return fallback;
    }
  }

  Map<LocalDay, CalendarDay> _buildDays(
    LocalDay from,
    LocalDay to,
    _History history,
    ({List<NutritionDay> days, NutritionTargetSchedule? targets})? food,
    TrainingScheduleProjection projection,
  ) {
    bool inRange(LocalDay day) => !day.isBefore(from) && !day.isAfter(to);

    final workoutsByDay = <LocalDay, List<CalendarWorkout>>{};
    for (final workout in history.workouts.reversed) {
      if (!isCountedWorkout(workout)) continue;
      final day = localDayOfUtc(workout.startedAtUtc);
      if (!inRange(day)) continue;
      final stats = workoutExerciseStats(
        workout,
        checkIns: history.checkIns,
        catalog: history.exercises,
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
    for (final session in history.sessions.reversed) {
      final day = localDayOfUtc(session.startedAtUtc);
      if (!inRange(day)) continue;
      cardioByDay.putIfAbsent(day, () => []).add(session);
    }

    final checkInByDay = <LocalDay, DailyCheckIn>{
      for (final checkIn in history.checkIns)
        if (_tryParseDay(checkIn.localDate) case final day? when inRange(day))
          day: checkIn,
    };

    final targets = food?.targets;
    final manualKinds = <String, NutritionDayKind?>{
      for (final entry in food?.days ?? const <NutritionDay>[])
        entry.localDate: entry.dayKind,
    };
    CalendarNutritionTarget? targetOn(LocalDay day) {
      final result = dayTarget(
        localDate: day.toIso(),
        targets: targets,
        manualKind: manualKinds[day.toIso()],
        projection: projection,
      );
      return result == null
          ? null
          : CalendarNutritionTarget.of(
              result,
              automatic: automaticDayKind(day, projection),
            );
    }

    final nutritionByDay = <LocalDay, CalendarNutrition>{};
    for (final entry in food?.days ?? const <NutritionDay>[]) {
      if (entry.entries.isEmpty) continue;
      final day = _tryParseDay(entry.localDate);
      if (day == null) continue;
      final totals = entry.totals;
      nutritionByDay[day] = CalendarNutrition(
        kilocalories: totals.kilocalories,
        proteinGrams: totals.proteinGrams,
        carbohydrateGrams: totals.carbohydrateGrams,
        fatGrams: totals.fatGrams,
        saltGrams: totals.saltGrams,
        target: targetOn(day),
      );
    }

    return {
      for (final day in projection.days(from, to))
        day.date: CalendarDay(
          date: day.date,
          schedule: day,
          workouts: workoutsByDay[day.date] ?? const [],
          cardio: cardioByDay[day.date] ?? const [],
          nutrition: nutritionByDay[day.date],
          nutritionTarget: targetOn(day.date),
          checkIn: checkInByDay[day.date],
        ),
    };
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
