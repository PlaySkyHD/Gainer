import '../body/body_tracking.dart';
import 'exercise_catalog_model.dart';
import 'training_schedule.dart';
import 'training_statistics.dart';
import 'training_trends.dart';
import 'workout_model.dart';

/// Entwicklung einer Übung im Zeitraum, gemessen am geschätzten 1RM.
enum ExerciseProgressStatus {
  progressing,
  stagnating,
  regressing,
  insufficientData,
}

enum FatigueSignalKind {
  /// Die Wiederholungen der Topsätze fielen zweimal in Folge bei gleichem
  /// oder geringerem Gewicht.
  decliningRepetitions,

  /// In den letzten zwei Einheiten hatte mehr als die Hälfte der Sätze mit
  /// RIR den Wert 0.
  failureOnMostSets,

  /// Die letzte Einheit verlor mindestens 20 % Volumen und 5 % 1RM gegenüber
  /// den Einheiten davor.
  volumeAndStrengthDrop,
}

enum RecommendationKind {
  increaseWeight,
  increaseReps,
  keepWeight,
  deload,
  changeStimulus,
  noRecommendation,
}

/// Zeitraum der Trainingsanalyse; ohne „Alle“, weil die Analyse begrenzt ist.
const analysisPeriods = [
  TrendPeriod.fourWeeks,
  TrendPeriod.threeMonths,
  TrendPeriod.year,
];

const _minimumSessions = 3;
const _sessionsForChangeStimulus = 4;
const _defaultStepCents = 250;
const _trendThresholdPercent = 2.5;

/// Ein Training einer Übung mit ihren Arbeitssätzen (ohne Aufwärmsätze).
class AnalysisSession {
  const AnalysisSession({
    required this.workoutId,
    required this.day,
    required this.workingSets,
    required this.volumeKg,
    required this.estimatedOneRepMaxKg,
    required this.topWeightKg,
    required this.topSetMinRepetitions,
    required this.topSetMaxRepetitions,
    required this.topLoggedWeightKg,
    required this.ratedSets,
    required this.zeroRirSets,
  });

  final String workoutId;
  final LocalDay day;
  final int workingSets;
  final double volumeKg;
  final double estimatedOneRepMaxKg;

  /// Höchstes effektives Gewicht; Topsätze sind die Sätze mit diesem Gewicht.
  final double topWeightKg;
  final int topSetMinRepetitions;
  final int topSetMaxRepetitions;

  /// Größtes eingetragenes Gewicht der Topsätze (Zusatz- oder Unterstützungsgewicht).
  final double? topLoggedWeightKg;
  final int ratedSets;
  final int zeroRirSets;
}

/// Ermüdungssignal mit Belegen; nicht zur Art passende Felder sind `null`.
class FatigueSignal {
  const FatigueSignal({
    required this.kind,
    required this.sessions,
    this.fromRepetitions,
    this.toRepetitions,
    this.weightKg,
    this.zeroRirSets,
    this.ratedSets,
    this.volumeChangePercent,
    this.estimatedOneRepMaxChangePercent,
  });

  final FatigueSignalKind kind;
  final int sessions;
  final int? fromRepetitions;
  final int? toRepetitions;
  final double? weightKg;
  final int? zeroRirSets;
  final int? ratedSets;
  final double? volumeChangePercent;
  final double? estimatedOneRepMaxChangePercent;
}

/// Regelbasierter Vorschlag für das nächste Training.
class TrainingRecommendation {
  const TrainingRecommendation({
    required this.kind,
    this.suggestedWeightKg,
    this.suggestedRepetitions,
    this.repetitionRangeLow,
    this.repetitionRangeHigh,
    this.weightStepKg,
    this.sessionsSinceBest = 0,
  });

  final RecommendationKind kind;
  final double? suggestedWeightKg;
  final int? suggestedRepetitions;
  final int? repetitionRangeLow;
  final int? repetitionRangeHigh;
  final double? weightStepKg;
  final int sessionsSinceBest;

  /// Begründung auf Deutsch, gleich formuliert wie auf dem Server.
  /// [formatWeight] formatiert Gewichte, Standard „92,5 kg“.
  String text({String Function(double kg)? formatWeight}) {
    final format = formatWeight ?? (kg) => '${formatAnalysisNumber(kg)} kg';
    final range = '$repetitionRangeLow–$repetitionRangeHigh Wdh.';
    final weight = switch (suggestedWeightKg) {
      final kg? => format(kg),
      null => null,
    };
    final reps = suggestedRepetitions;
    return switch (kind) {
      RecommendationKind.increaseWeight =>
        'Oberes Ende von $range in allen Sätzen erreicht: nächstes Mal '
            '$weight mit $reps Wdh.',
      RecommendationKind.increaseReps =>
        weight == null
            ? 'Im Bereich $range: auf $reps Wdh. je Satz steigern.'
            : 'Im Bereich $range: $weight halten und auf $reps Wdh. je Satz '
                  'steigern.',
      RecommendationKind.keepWeight =>
        'Unter $repetitionRangeLow Wdh. im Bereich $range: '
            '${weight ?? 'Belastung'} halten, bis alle Sätze $reps Wdh. '
            'schaffen.',
      RecommendationKind.deload =>
        weight == null
            ? 'Ermüdung oder Leistungsabfall: nächstes Mal leichter trainieren '
                  'oder einen Ruhetag mehr einplanen.'
            : 'Ermüdung oder Leistungsabfall: nächstes Mal $weight (−10 %) '
                  'und nicht bis zum Muskelversagen.',
      RecommendationKind.changeStimulus =>
        repetitionRangeHigh == null
            ? 'Seit $sessionsSinceBest Trainings kein neuer Bestwert: '
                  'Wiederholungsbereich oder Übungsvariante wechseln.'
            : 'Oberes Ende von $range erreicht: schwerere Variante wählen '
                  'oder Unterstützung verringern.',
      RecommendationKind.noRecommendation =>
        'Noch keine Arbeitssätze im Zeitraum: keine Empfehlung.',
    };
  }
}

class ExerciseAnalysis {
  const ExerciseAnalysis({
    required this.exerciseId,
    required this.name,
    required this.exerciseType,
    required this.sessions,
    required this.bestEstimatedOneRepMaxKg,
    required this.sessionsSinceBest,
    required this.estimatedOneRepMaxFirstKg,
    required this.estimatedOneRepMaxLastKg,
    required this.estimatedOneRepMaxChangePercent,
    required this.topWeightChangePercent,
    required this.topRepetitionsChange,
    required this.volumeChangePercent,
    required this.volumePerWeekKg,
    required this.workingSetsPerWeek,
    required this.status,
    required this.fatigueSignals,
    required this.recommendation,
  });

  final String exerciseId;
  final String name;
  final ExerciseKind exerciseType;
  final List<AnalysisSession> sessions;
  final double? bestEstimatedOneRepMaxKg;
  final int sessionsSinceBest;

  /// Mittel des 1RM im ersten bzw. letzten Drittel der Einheiten.
  final double? estimatedOneRepMaxFirstKg;
  final double? estimatedOneRepMaxLastKg;
  final double? estimatedOneRepMaxChangePercent;
  final double? topWeightChangePercent;
  final double? topRepetitionsChange;
  final double? volumeChangePercent;
  final double volumePerWeekKg;
  final double workingSetsPerWeek;
  final ExerciseProgressStatus status;
  final List<FatigueSignal> fatigueSignals;
  final TrainingRecommendation recommendation;
}

/// Volumen und Arbeitssätze aller Übungen in 7 Tagen ab dem Zeitraumbeginn.
class AnalysisWeek {
  const AnalysisWeek({
    required this.start,
    required this.complete,
    required this.volumeKg,
    required this.workingSets,
  });

  final LocalDay start;

  /// Der Abschnitt endet spätestens heute.
  final bool complete;
  final double volumeKg;
  final int workingSets;
}

class TrainingAnalysisOverall {
  const TrainingAnalysisOverall({
    required this.weeks,
    required this.weeklyVolumeChangePercent,
    required this.exercisesWithFatigue,
    required this.eligibleExercises,
    required this.fatigued,
  });

  final List<AnalysisWeek> weeks;
  final double? weeklyVolumeChangePercent;
  final int exercisesWithFatigue;
  final int eligibleExercises;
  final bool fatigued;
}

/// Trainingsanalyse eines Zeitraums. Die Regeln stehen in
/// `contracts/fixtures/training-analysis.json`; der Server rechnet sie gleich
/// (`get_training_analysis`).
class TrainingAnalysis {
  const TrainingAnalysis({
    required this.period,
    required this.start,
    required this.today,
    required this.exercises,
    required this.overall,
  });

  final TrendPeriod period;
  final LocalDay start;
  final LocalDay today;
  final List<ExerciseAnalysis> exercises;
  final TrainingAnalysisOverall overall;

  bool get isEmpty => exercises.isEmpty;

  static TrainingAnalysis compute(
    List<Workout> workouts, {
    required List<DailyCheckIn> checkIns,
    required List<CatalogExercise> catalog,
    required TrendPeriod period,
    required LocalDay today,
    LocalDay Function(DateTime utc) dayOf = localDayOfUtc,
  }) {
    final start = TrainingTrends.fixedStart(period, today);
    if (start == null) {
      throw ArgumentError.value(
        period,
        'period',
        'Zeitraum muss begrenzt sein.',
      );
    }
    final counted = workouts.where(isCountedWorkout).toList()
      ..sort((a, b) {
        final byStart = a.startedAtUtc.compareTo(b.startedAtUtc);
        return byStart == 0 ? a.workoutId.compareTo(b.workoutId) : byStart;
      });
    final collectors = <String, _ExerciseCollector>{};
    for (final workout in counted) {
      final day = dayOf(workout.startedAtUtc);
      if (day.isBefore(start) || day.isAfter(today)) continue;
      final stats = workoutExerciseStats(
        workout,
        checkIns: checkIns,
        catalog: catalog,
        localDayOf: (utc) => dayOf(utc).toIso(),
      );
      final inWorkout = <_ExerciseCollector>[];
      for (var i = 0; i < workout.exercises.length; i++) {
        final block = workout.exercises[i];
        final collector = collectors.putIfAbsent(
          block.sourceExerciseId,
          () => _ExerciseCollector(block.sourceExerciseId),
        );
        collector.addBlock(block, stats[i]);
        if (!inWorkout.contains(collector)) inWorkout.add(collector);
      }
      for (final collector in inWorkout) {
        collector.endWorkout(workout.workoutId, day);
      }
    }
    final days = start.daysUntil(today) + 1;
    final analyses = [
      for (final collector in collectors.values) collector.analyze(days),
    ]..sort(_byLastSession);
    return TrainingAnalysis(
      period: period,
      start: start,
      today: today,
      exercises: analyses,
      overall: _overall(analyses, start, today),
    );
  }

  static int _byLastSession(ExerciseAnalysis a, ExerciseAnalysis b) {
    final aDay = a.sessions.isEmpty ? null : a.sessions.last.day;
    final bDay = b.sessions.isEmpty ? null : b.sessions.last.day;
    if (aDay != bDay) {
      if (aDay == null) return 1;
      if (bDay == null) return -1;
      final byDay = bDay.compareTo(aDay);
      if (byDay != 0) return byDay;
    }
    final byName = a.name.compareTo(b.name);
    return byName != 0 ? byName : a.exerciseId.compareTo(b.exerciseId);
  }

  static TrainingAnalysisOverall _overall(
    List<ExerciseAnalysis> analyses,
    LocalDay start,
    LocalDay today,
  ) {
    final days = start.daysUntil(today) + 1;
    final count = (days + 6) ~/ 7;
    final volume = List<double>.filled(count, 0);
    final sets = List<int>.filled(count, 0);
    for (final analysis in analyses) {
      for (final session in analysis.sessions) {
        final index = start.daysUntil(session.day) ~/ 7;
        volume[index] += session.volumeKg;
        sets[index] += session.workingSets;
      }
    }
    final weeks = [
      for (var i = 0; i < count; i++)
        AnalysisWeek(
          start: start.addDays(7 * i),
          complete: !start.addDays(7 * i + 6).isAfter(today),
          volumeKg: volume[i],
          workingSets: sets[i],
        ),
    ];
    final thirds = _Thirds.of([
      for (final week in weeks)
        if (week.complete) week.volumeKg,
    ]);
    final eligible = analyses
        .where((item) => item.sessions.length >= _minimumSessions)
        .length;
    final fatigued = analyses
        .where((item) => item.fatigueSignals.isNotEmpty)
        .length;
    return TrainingAnalysisOverall(
      weeks: weeks,
      weeklyVolumeChangePercent: _percent(thirds.first, thirds.last),
      exercisesWithFatigue: fatigued,
      eligibleExercises: eligible,
      fatigued: fatigued > 0 && fatigued * 3 >= eligible,
    );
  }
}

/// Bis zu zwei Nachkommastellen mit Komma und Tausenderpunkt, z. B. „1.002,5“.
String formatAnalysisNumber(double value) {
  var text = value.toStringAsFixed(2);
  text = text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  final negative = text.startsWith('-');
  if (negative) text = text.substring(1);
  final parts = text.split('.');
  final digits = parts.first;
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write('.');
    grouped.write(digits[i]);
  }
  final fraction = parts.length > 1 ? ',${parts[1]}' : '';
  return '${negative ? '-' : ''}$grouped$fraction';
}

int _cents(double value) => (value * 100).round();

double? _percent(double? from, double? to) {
  if (from == null || to == null || from == 0) return null;
  return (to - from) / from * 100;
}

double? _maxOrNull(Iterable<double?> values) {
  double? max;
  for (final value in values) {
    if (value != null && (max == null || value > max)) max = value;
  }
  return max;
}

class _WorkingSet {
  const _WorkingSet(this.result);

  final SetResult result;

  double get effectiveWeightKg => result.effectiveWeightKg;
  int get repetitions => result.repetitions;
  double? get loggedWeightKg => result.set.weightKg;
  int? get rir => result.set.rir;
}

/// Mittel des ersten und letzten Drittels (mindestens je ein Wert); `null`
/// unter zwei Werten.
class _Thirds {
  const _Thirds(this.first, this.last);

  factory _Thirds.of(List<double> values) {
    if (values.length < 2) return const _Thirds(null, null);
    final size = values.length ~/ 3 < 1 ? 1 : values.length ~/ 3;
    double mean(Iterable<double> part) =>
        part.fold<double>(0, (sum, value) => sum + value) / size;
    return _Thirds(
      mean(values.take(size)),
      mean(values.skip(values.length - size)),
    );
  }

  final double? first;
  final double? last;
}

class _ExerciseCollector {
  _ExerciseCollector(this.exerciseId);

  final String exerciseId;
  final List<AnalysisSession> _sessions = [];
  final Set<int> _loggedCents = {};
  final List<_WorkingSet> _current = [];
  String _name = '';
  ExerciseKind _type = ExerciseKind.strength;

  void addBlock(WorkoutBlock block, ExerciseStats stats) {
    _name = block.exerciseNameSnapshot;
    _type = block.exerciseTypeSnapshot;
    for (final result in stats.sets) {
      _current.add(_WorkingSet(result));
      if (result.set.weightKg case final logged?) {
        _loggedCents.add(_cents(logged));
      }
    }
  }

  void endWorkout(String workoutId, LocalDay day) {
    if (_current.isEmpty) return;
    final topCents = _current
        .map((set) => _cents(set.effectiveWeightKg))
        .reduce((a, b) => a > b ? a : b);
    final top = [
      for (final set in _current)
        if (_cents(set.effectiveWeightKg) == topCents) set,
    ];
    final topReps = [for (final set in top) set.repetitions];
    _sessions.add(
      AnalysisSession(
        workoutId: workoutId,
        day: day,
        workingSets: _current.length,
        volumeKg: _current.fold<double>(
          0,
          (sum, set) => sum + set.result.volumeKg,
        ),
        estimatedOneRepMaxKg: _maxOrNull(
          _current.map((set) => set.result.estimatedOneRepMaxKg),
        )!,
        topWeightKg: _maxOrNull(_current.map((set) => set.effectiveWeightKg))!,
        topSetMinRepetitions: topReps.reduce((a, b) => a < b ? a : b),
        topSetMaxRepetitions: topReps.reduce((a, b) => a > b ? a : b),
        topLoggedWeightKg: _maxOrNull(top.map((set) => set.loggedWeightKg)),
        ratedSets: _current.where((set) => set.rir != null).length,
        zeroRirSets: _current.where((set) => (set.rir ?? 1) <= 0).length,
      ),
    );
    _current.clear();
  }

  ExerciseAnalysis analyze(int days) {
    final weeks = days / 7;
    final e1rm = _Thirds.of([
      for (final item in _sessions) item.estimatedOneRepMaxKg,
    ]);
    final topWeight = _Thirds.of([
      for (final item in _sessions) item.topWeightKg,
    ]);
    final reps = _Thirds.of([
      for (final item in _sessions) item.topSetMaxRepetitions.toDouble(),
    ]);
    final volume = _Thirds.of([for (final item in _sessions) item.volumeKg]);
    final sinceBest = _sessionsSinceBest();
    final e1rmChange = _percent(e1rm.first, e1rm.last);
    final status = _statusOf(_sessions.length, e1rmChange, sinceBest);
    final fatigue = _fatigueSignals(_sessions);
    final firstReps = reps.first;
    final lastReps = reps.last;
    return ExerciseAnalysis(
      exerciseId: exerciseId,
      name: _name,
      exerciseType: _type,
      sessions: List.unmodifiable(_sessions),
      bestEstimatedOneRepMaxKg: _maxOrNull(
        _sessions.map((item) => item.estimatedOneRepMaxKg),
      ),
      sessionsSinceBest: sinceBest,
      estimatedOneRepMaxFirstKg: e1rm.first,
      estimatedOneRepMaxLastKg: e1rm.last,
      estimatedOneRepMaxChangePercent: e1rmChange,
      topWeightChangePercent: _percent(topWeight.first, topWeight.last),
      topRepetitionsChange: firstReps != null && lastReps != null
          ? lastReps - firstReps
          : null,
      volumeChangePercent: _percent(volume.first, volume.last),
      volumePerWeekKg:
          _sessions.fold<double>(0, (sum, item) => sum + item.volumeKg) / weeks,
      workingSetsPerWeek:
          _sessions.fold<int>(0, (sum, item) => sum + item.workingSets) / weeks,
      status: status,
      fatigueSignals: fatigue,
      recommendation: _recommendation(
        _sessions,
        type: _type,
        status: status,
        fatigued: fatigue.isNotEmpty,
        sinceBest: sinceBest,
        stepCents: _stepCents(),
      ),
    );
  }

  /// Einheiten nach der ersten mit dem höchsten 1RM des Zeitraums.
  int _sessionsSinceBest() {
    if (_sessions.isEmpty) return 0;
    final best = _maxOrNull(_sessions.map((item) => item.estimatedOneRepMaxKg));
    final index = _sessions.indexWhere(
      (item) => item.estimatedOneRepMaxKg == best,
    );
    return _sessions.length - 1 - index;
  }

  /// Kleinster positiver Abstand der eingetragenen Gewichte, höchstens 2,5 kg.
  int _stepCents() {
    final sorted = _loggedCents.toList()..sort();
    var step = _defaultStepCents;
    for (var i = 1; i < sorted.length; i++) {
      final difference = sorted[i] - sorted[i - 1];
      if (difference < step) step = difference;
    }
    return step;
  }
}

ExerciseProgressStatus _statusOf(int count, double? change, int sinceBest) {
  if (count < _minimumSessions || change == null) {
    return ExerciseProgressStatus.insufficientData;
  }
  if (change <= -_trendThresholdPercent) {
    return ExerciseProgressStatus.regressing;
  }
  return change >= _trendThresholdPercent && sinceBest < _minimumSessions
      ? ExerciseProgressStatus.progressing
      : ExerciseProgressStatus.stagnating;
}

List<FatigueSignal> _fatigueSignals(List<AnalysisSession> sessions) => [
  ?_decliningRepetitions(sessions),
  ?_failureOnMostSets(sessions),
  ?_volumeAndStrengthDrop(sessions),
];

FatigueSignal? _decliningRepetitions(List<AnalysisSession> sessions) {
  if (sessions.length < _minimumSessions) return null;
  final first = sessions[sessions.length - 3];
  final second = sessions[sessions.length - 2];
  final last = sessions.last;
  final sameOrLower =
      _cents(second.topWeightKg) <= _cents(first.topWeightKg) &&
      _cents(last.topWeightKg) <= _cents(second.topWeightKg);
  final falling =
      second.topSetMaxRepetitions < first.topSetMaxRepetitions &&
      last.topSetMaxRepetitions < second.topSetMaxRepetitions;
  if (!sameOrLower || !falling) return null;
  return FatigueSignal(
    kind: FatigueSignalKind.decliningRepetitions,
    sessions: _minimumSessions,
    fromRepetitions: first.topSetMaxRepetitions,
    toRepetitions: last.topSetMaxRepetitions,
    weightKg: last.topWeightKg,
  );
}

FatigueSignal? _failureOnMostSets(List<AnalysisSession> sessions) {
  const sessionCount = 2;
  if (sessions.length < sessionCount) return null;
  final failing = sessions
      .skip(sessions.length - sessionCount)
      .every(
        (item) => item.ratedSets >= 2 && item.zeroRirSets * 2 > item.ratedSets,
      );
  if (!failing) return null;
  return FatigueSignal(
    kind: FatigueSignalKind.failureOnMostSets,
    sessions: sessionCount,
    zeroRirSets: sessions.last.zeroRirSets,
    ratedSets: sessions.last.ratedSets,
  );
}

/// Letzte Einheit gegen das Mittel der bis zu drei Einheiten davor.
FatigueSignal? _volumeAndStrengthDrop(List<AnalysisSession> sessions) {
  if (sessions.length < _minimumSessions) return null;
  final last = sessions.last;
  final before = sessions.sublist(
    sessions.length - 1 - _minimumSessions < 0
        ? 0
        : sessions.length - 1 - _minimumSessions,
    sessions.length - 1,
  );
  double mean(double Function(AnalysisSession) value) =>
      before.fold<double>(0, (sum, item) => sum + value(item)) / before.length;
  final volume = _percent(mean((item) => item.volumeKg), last.volumeKg);
  final e1rm = _percent(
    mean((item) => item.estimatedOneRepMaxKg),
    last.estimatedOneRepMaxKg,
  );
  if (volume == null || e1rm == null || volume > -20 || e1rm > -5) return null;
  return FatigueSignal(
    kind: FatigueSignalKind.volumeAndStrengthDrop,
    sessions: before.length + 1,
    volumeChangePercent: volume,
    estimatedOneRepMaxChangePercent: e1rm,
  );
}

TrainingRecommendation _recommendation(
  List<AnalysisSession> sessions, {
  required ExerciseKind type,
  required ExerciseProgressStatus status,
  required bool fatigued,
  required int sinceBest,
  required int stepCents,
}) {
  if (sessions.isEmpty) {
    return const TrainingRecommendation(
      kind: RecommendationKind.noRecommendation,
    );
  }
  final last = sessions.last;
  final weighted =
      type == ExerciseKind.strength || type == ExerciseKind.bodyweightLoaded;
  final step = weighted ? stepCents / 100 : null;
  final logged = weighted ? last.topLoggedWeightKg : null;
  if (fatigued || status == ExerciseProgressStatus.regressing) {
    return TrainingRecommendation(
      kind: RecommendationKind.deload,
      suggestedWeightKg: _deloadWeight(logged, stepCents),
      weightStepKg: step,
      sessionsSinceBest: sinceBest,
    );
  }
  if (status == ExerciseProgressStatus.stagnating &&
      sinceBest >= _sessionsForChangeStimulus) {
    return TrainingRecommendation(
      kind: RecommendationKind.changeStimulus,
      weightStepKg: step,
      sessionsSinceBest: sinceBest,
    );
  }
  return _doubleProgression(
    last,
    weighted: weighted,
    logged: logged,
    step: step,
    sinceBest: sinceBest,
  );
}

/// Doppelte Progression im Bereich des besten Topsatzes der letzten Einheit.
TrainingRecommendation _doubleProgression(
  AnalysisSession last, {
  required bool weighted,
  required double? logged,
  required double? step,
  required int sinceBest,
}) {
  final (low, high) = switch (last.topSetMaxRepetitions) {
    <= 5 => (3, 5),
    <= 12 => (6, 12),
    _ => (13, 20),
  };
  final reps = last.topSetMinRepetitions;
  final RecommendationKind kind;
  var weight = logged;
  int? target;
  if (reps >= high && weighted) {
    kind = RecommendationKind.increaseWeight;
    weight = (logged ?? 0) + step!;
    target = low;
  } else if (reps >= high) {
    kind = RecommendationKind.changeStimulus;
  } else if (reps < low) {
    kind = RecommendationKind.keepWeight;
    target = low;
  } else {
    kind = RecommendationKind.increaseReps;
    target = reps + 1;
  }
  return TrainingRecommendation(
    kind: kind,
    suggestedWeightKg: weight,
    suggestedRepetitions: target,
    repetitionRangeLow: low,
    repetitionRangeHigh: high,
    weightStepKg: step,
    sessionsSinceBest: sinceBest,
  );
}

/// 90 % des eingetragenen Gewichts, auf die Stufe abgerundet; `null` ohne
/// positives Ergebnis.
double? _deloadWeight(double? logged, int stepCents) {
  if (logged == null) return null;
  final target = _cents(logged) * 9 ~/ (10 * stepCents) * stepCents;
  return target > 0 ? target / 100 : null;
}
