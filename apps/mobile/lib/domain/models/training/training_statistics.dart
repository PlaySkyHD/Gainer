import '../body/body_tracking.dart';
import 'exercise_catalog_model.dart';
import 'workout_model.dart';
import 'workout_rules.dart';

/// Liefert das lokale Kalenderdatum (`YYYY-MM-DD`) zu einem UTC-Zeitpunkt.
typedef LocalDayOf = String Function(DateTime instant);

/// Gerätezeitzone, wie bei der Auswertung der Körpermessungen.
String deviceLocalDay(DateTime instant) => formatCalendarDay(instant.toLocal());

String formatCalendarDay(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// Wiederholungszahlen, für die je Übung das maximale Gewicht ausgewiesen wird.
const repetitionRecordThresholds = [1, 3, 5, 8, 10, 12];

enum RecordKind { maxWeight, estimatedOneRepMax, volume, maxRepetitions }

/// Kaufmännische Rundung auf zwei Nachkommastellen, nur für die Ausgabe.
double roundToTwoDecimals(double value) => (value * 100).roundToDouble() / 100;

/// Epley: Gewicht × (1 + Wiederholungen / 30). Eine Wiederholung ist das Gewicht selbst.
double epleyOneRepMaxKg(double weightKg, int repetitions) {
  if (repetitions <= 0) return 0;
  if (repetitions == 1) return weightKg;
  return weightKg * (1 + repetitions / 30);
}

/// Effektives Gewicht eines Satzes. Assistierte Übungen ziehen das
/// Unterstützungsgewicht vom Körpergewicht ab und gehen nicht unter 0.
double effectiveWeightKg({
  required ExerciseKind kind,
  required double? weightKg,
  required double bodyweightFactor,
  required double weightFactor,
  required double? bodyweightKg,
}) {
  final bodyweightPart = (bodyweightKg ?? 0) * bodyweightFactor;
  if (kind == ExerciseKind.assisted) {
    final remaining = bodyweightPart - (weightKg ?? 0);
    return remaining < 0 ? 0 : remaining;
  }
  return (weightKg ?? 0) * weightFactor + bodyweightPart;
}

/// Jüngster Check-in mit lokalem Datum am oder vor dem lokalen Starttag.
/// Bei gleichem Datum gewinnt der Eintrag weiter hinten in der Liste.
double? bodyweightForWorkout(
  Workout workout,
  List<DailyCheckIn> checkIns, {
  LocalDayOf localDayOf = deviceLocalDay,
}) {
  final startDay = localDayOf(workout.startedAtUtc);
  DailyCheckIn? latest;
  for (final checkIn in checkIns) {
    if (checkIn.localDate.compareTo(startDay) > 0) continue;
    if (latest == null || checkIn.localDate.compareTo(latest.localDate) >= 0) {
      latest = checkIn;
    }
  }
  return latest?.weightKg;
}

class SetResult {
  const SetResult({
    required this.set,
    required this.effectiveWeightKg,
    required this.repetitions,
  });

  final LoggedSet set;
  final double effectiveWeightKg;
  final int repetitions;

  double get volumeKg => effectiveWeightKg * repetitions;

  double get estimatedOneRepMaxKg =>
      epleyOneRepMaxKg(effectiveWeightKg, repetitions);
}

/// Kennzahlen eines Blocks (Übung) in einem Training. Nur erfasste Sätze fließen ein.
class ExerciseStats {
  const ExerciseStats({
    required this.workoutId,
    required this.workoutExerciseId,
    required this.sourceExerciseId,
    required this.sets,
    required this.bodyweightKg,
    required this.bodyweightMissing,
  });

  final String workoutId;
  final String workoutExerciseId;
  final String sourceExerciseId;
  final List<SetResult> sets;
  final double? bodyweightKg;

  /// Körpergewicht fehlt, obwohl die Übung einen Körpergewichtsanteil hat.
  final bool bodyweightMissing;

  int get setCount => sets.length;

  int get totalRepetitions => sets.fold(0, (sum, set) => sum + set.repetitions);

  int get maxRepetitions =>
      sets.fold(0, (max, set) => set.repetitions > max ? set.repetitions : max);

  double get volumeKg => sets.fold<double>(0, (sum, set) => sum + set.volumeKg);

  double? get maxWeightKg =>
      _maxOrNull(sets.map((set) => set.effectiveWeightKg));

  double? get averageWeightKg {
    if (sets.isEmpty) return null;
    final reps = totalRepetitions;
    return reps == 0 ? 0 : volumeKg / reps;
  }

  double? get estimatedOneRepMaxKg =>
      _maxOrNull(sets.map((set) => set.estimatedOneRepMaxKg));

  /// Satz mit dem höchsten geschätzten 1RM; bei Gleichstand der erste.
  SetResult? get bestSet {
    SetResult? best;
    for (final set in sets) {
      if (best == null ||
          set.estimatedOneRepMaxKg > best.estimatedOneRepMaxKg) {
        best = set;
      }
    }
    return best;
  }
}

class RecordEvent {
  const RecordEvent({required this.workoutId, required this.value});

  final String workoutId;
  final double value;
}

/// Rekordverläufe einer Übung über alle beendeten, nicht gelöschten Trainings.
class ExerciseRecords {
  const ExerciseRecords({
    required this.maxWeight,
    required this.estimatedOneRepMax,
    required this.volume,
    required this.maxRepetitions,
    required this.repRecords,
  });

  final List<RecordEvent> maxWeight;
  final List<RecordEvent> estimatedOneRepMax;
  final List<RecordEvent> volume;
  final List<RecordEvent> maxRepetitions;

  /// Maximales Gewicht je Wiederholungszahl aus [repetitionRecordThresholds]; `null` ohne passenden Satz.
  final Map<int, double?> repRecords;

  List<RecordEvent> eventsOf(RecordKind kind) => switch (kind) {
    RecordKind.maxWeight => maxWeight,
    RecordKind.estimatedOneRepMax => estimatedOneRepMax,
    RecordKind.volume => volume,
    RecordKind.maxRepetitions => maxRepetitions,
  };
}

class BestSet {
  const BestSet({required this.sourceExerciseId, required this.set});

  final String sourceExerciseId;
  final SetResult set;
}

class NewRecord {
  const NewRecord({
    required this.sourceExerciseId,
    required this.kind,
    required this.value,
  });

  final String sourceExerciseId;
  final RecordKind kind;
  final double value;
}

class TrainingSummary {
  const TrainingSummary({
    required this.workoutId,
    required this.duration,
    required this.setCount,
    required this.totalRepetitions,
    required this.volumeKg,
    required this.bestSets,
    required this.newRecords,
  });

  final String workoutId;
  final Duration duration;
  final int setCount;
  final int totalRepetitions;
  final double volumeKg;
  final List<BestSet> bestSets;
  final List<NewRecord> newRecords;
}

class WorkoutCounts {
  const WorkoutCounts({required this.total, required this.thisWeek});

  /// Beendete, nicht gelöschte Trainings.
  final int total;

  /// Davon mit lokalem Starttag in der laufenden Woche (Montag bis Sonntag).
  final int thisWeek;
}

/// Kennzahlen je Block eines Trainings. Warmups bleiben ohne [includeWarmups] außen vor.
List<ExerciseStats> workoutExerciseStats(
  Workout workout, {
  required List<DailyCheckIn> checkIns,
  required List<CatalogExercise> catalog,
  LocalDayOf localDayOf = deviceLocalDay,
  bool includeWarmups = false,
}) {
  final catalogById = _catalogIndex(catalog);
  final bodyweightKg = bodyweightForWorkout(
    workout,
    checkIns,
    localDayOf: localDayOf,
  );
  return [
    for (final block in workout.exercises)
      _blockStats(
        workout,
        block,
        bodyweightKg: bodyweightKg,
        catalogById: catalogById,
        includeWarmups: includeWarmups,
      ),
  ];
}

/// Rekordverläufe je Übung (`sourceExerciseId`). Nur beendete, nicht gelöschte Trainings.
Map<String, ExerciseRecords> exerciseRecords(
  List<Workout> workouts, {
  required List<DailyCheckIn> checkIns,
  required List<CatalogExercise> catalog,
  LocalDayOf localDayOf = deviceLocalDay,
  bool includeWarmups = false,
}) {
  final finished = _finishedChronological(workouts);
  final catalogById = _catalogIndex(catalog);

  final perWorkout = <String, List<_ExerciseTotals>>{};
  final sets = <String, List<SetResult>>{};
  for (final workout in finished) {
    final bodyweightKg = bodyweightForWorkout(
      workout,
      checkIns,
      localDayOf: localDayOf,
    );
    final totals = <String, _ExerciseTotals>{};
    for (final block in workout.exercises) {
      final stats = _blockStats(
        workout,
        block,
        bodyweightKg: bodyweightKg,
        catalogById: catalogById,
        includeWarmups: includeWarmups,
      );
      sets.putIfAbsent(block.sourceExerciseId, () => []).addAll(stats.sets);
      if (stats.sets.isEmpty) continue;
      totals
          .putIfAbsent(
            block.sourceExerciseId,
            () => _ExerciseTotals(workout.workoutId),
          )
          .add(stats);
    }
    totals.forEach(
      (sourceExerciseId, total) =>
          perWorkout.putIfAbsent(sourceExerciseId, () => []).add(total),
    );
  }

  return {
    for (final entry in sets.entries)
      entry.key: _recordsFor(perWorkout[entry.key] ?? const [], entry.value),
  };
}

/// Zusammenfassung eines beendeten Trainings. [history] darf das Training selbst enthalten.
TrainingSummary summarizeTraining(
  Workout workout, {
  required List<Workout> history,
  required List<DailyCheckIn> checkIns,
  required List<CatalogExercise> catalog,
  LocalDayOf localDayOf = deviceLocalDay,
  bool includeWarmups = false,
}) {
  final endedAt = workout.endedAtUtc;
  if (endedAt == null || workout.deletedAtUtc != null) {
    throw ArgumentError.value(
      workout,
      'workout',
      'Nur beendete, nicht gelöschte Trainings können zusammengefasst werden.',
    );
  }

  final stats = workoutExerciseStats(
    workout,
    checkIns: checkIns,
    catalog: catalog,
    localDayOf: localDayOf,
    includeWarmups: includeWarmups,
  );
  final records = exerciseRecords(
    [
      for (final other in history)
        if (other.workoutId != workout.workoutId) other,
      workout,
    ],
    checkIns: checkIns,
    catalog: catalog,
    localDayOf: localDayOf,
    includeWarmups: includeWarmups,
  );

  final newRecords = <NewRecord>[];
  final seen = <String>{};
  for (final stat in stats) {
    if (!seen.add(stat.sourceExerciseId)) continue;
    final exerciseRecordsFor = records[stat.sourceExerciseId];
    if (exerciseRecordsFor == null) continue;
    for (final kind in RecordKind.values) {
      for (final event in exerciseRecordsFor.eventsOf(kind)) {
        if (event.workoutId == workout.workoutId) {
          newRecords.add(
            NewRecord(
              sourceExerciseId: stat.sourceExerciseId,
              kind: kind,
              value: event.value,
            ),
          );
        }
      }
    }
  }

  return TrainingSummary(
    workoutId: workout.workoutId,
    duration: endedAt.difference(workout.startedAtUtc),
    setCount: stats.fold(0, (sum, stat) => sum + stat.setCount),
    totalRepetitions: stats.fold(0, (sum, stat) => sum + stat.totalRepetitions),
    volumeKg: stats.fold<double>(0, (sum, stat) => sum + stat.volumeKg),
    bestSets: [
      for (final stat in stats)
        if (stat.bestSet != null)
          BestSet(sourceExerciseId: stat.sourceExerciseId, set: stat.bestSet!),
    ],
    newRecords: newRecords,
  );
}

/// Zähler „n. Training · m. diese Woche“. Woche = Montag bis Sonntag, lokal.
WorkoutCounts workoutCounts(
  List<Workout> workouts, {
  required DateTime now,
  LocalDayOf localDayOf = deviceLocalDay,
}) {
  final finished = workouts.where(isCountedWorkout).toList();
  final today = _parseCalendarDay(localDayOf(now));
  final monday = today.subtract(Duration(days: today.weekday - 1));
  final sunday = monday.add(const Duration(days: 6));
  final firstDay = formatCalendarDay(monday);
  final lastDay = formatCalendarDay(sunday);

  var thisWeek = 0;
  for (final workout in finished) {
    final day = localDayOf(workout.startedAtUtc);
    if (day.compareTo(firstDay) >= 0 && day.compareTo(lastDay) <= 0) {
      thisWeek++;
    }
  }
  return WorkoutCounts(total: finished.length, thisWeek: thisWeek);
}

class _ExerciseTotals {
  _ExerciseTotals(this.workoutId);

  final String workoutId;
  int setCount = 0;
  int maxRepetitions = 0;
  double volumeKg = 0;
  double? maxWeightKg;
  double? estimatedOneRepMaxKg;

  void add(ExerciseStats stats) {
    setCount += stats.setCount;
    volumeKg += stats.volumeKg;
    if (stats.maxRepetitions > maxRepetitions) {
      maxRepetitions = stats.maxRepetitions;
    }
    maxWeightKg = _maxOrNull([?maxWeightKg, ?stats.maxWeightKg]);
    estimatedOneRepMaxKg = _maxOrNull([
      ?estimatedOneRepMaxKg,
      ?stats.estimatedOneRepMaxKg,
    ]);
  }
}

ExerciseRecords _recordsFor(
  List<_ExerciseTotals> entries,
  List<SetResult> sets,
) {
  return ExerciseRecords(
    maxWeight: _strictRecords([
      for (final entry in entries)
        if (entry.maxWeightKg != null)
          RecordEvent(workoutId: entry.workoutId, value: entry.maxWeightKg!),
    ]),
    estimatedOneRepMax: _strictRecords([
      for (final entry in entries)
        if (entry.estimatedOneRepMaxKg != null)
          RecordEvent(
            workoutId: entry.workoutId,
            value: entry.estimatedOneRepMaxKg!,
          ),
    ]),
    volume: _strictRecords([
      for (final entry in entries)
        if (entry.setCount > 0)
          RecordEvent(workoutId: entry.workoutId, value: entry.volumeKg),
    ]),
    maxRepetitions: _strictRecords([
      for (final entry in entries)
        if (entry.setCount > 0)
          RecordEvent(
            workoutId: entry.workoutId,
            value: entry.maxRepetitions.toDouble(),
          ),
    ]),
    repRecords: {
      for (final threshold in repetitionRecordThresholds)
        threshold: _maxOrNull([
          for (final set in sets)
            if (set.repetitions >= threshold) set.effectiveWeightKg,
        ]),
    },
  );
}

/// Ein Wert ist nur dann ein Rekord, wenn er den bisherigen Bestwert strikt übertrifft.
List<RecordEvent> _strictRecords(List<RecordEvent> chronological) {
  final events = <RecordEvent>[];
  double? best;
  for (final event in chronological) {
    if (best == null || event.value > best) {
      events.add(event);
      best = event.value;
    }
  }
  return events;
}

ExerciseStats _blockStats(
  Workout workout,
  WorkoutBlock block, {
  required double? bodyweightKg,
  required Map<String, CatalogExercise> catalogById,
  required bool includeWarmups,
}) {
  final kind = block.exerciseTypeSnapshot;
  final exercise = catalogById[block.sourceExerciseId];
  final bodyweightFactor =
      exercise?.bodyweightFactor ?? _defaultBodyweightFactor(kind);
  final weightFactor = exercise?.weightFactor ?? 1;

  final sets = <SetResult>[];
  for (final set in block.sets) {
    if (!includeWarmups && set.setType == SetType.warmup) continue;
    if (!isSetRecorded(set, kind)) continue;
    sets.add(
      SetResult(
        set: set,
        effectiveWeightKg: effectiveWeightKg(
          kind: kind,
          weightKg: set.weightKg,
          bodyweightFactor: bodyweightFactor,
          weightFactor: weightFactor,
          bodyweightKg: bodyweightKg,
        ),
        repetitions: set.repetitions ?? 0,
      ),
    );
  }

  return ExerciseStats(
    workoutId: workout.workoutId,
    workoutExerciseId: block.workoutExerciseId,
    sourceExerciseId: block.sourceExerciseId,
    sets: sets,
    bodyweightKg: bodyweightKg,
    bodyweightMissing:
        bodyweightKg == null && bodyweightFactor > 0 && sets.isNotEmpty,
  );
}

/// Ohne Katalogwert: Kraft hat keinen Körpergewichtsanteil, alle anderen Typen 100 %.
double _defaultBodyweightFactor(ExerciseKind kind) =>
    kind == ExerciseKind.strength ? 0 : 1;

Map<String, CatalogExercise> _catalogIndex(List<CatalogExercise> catalog) => {
  for (final exercise in catalog) exercise.id: exercise,
};

List<Workout> _finishedChronological(List<Workout> workouts) {
  final finished = workouts.where(isCountedWorkout).toList()
    ..sort((a, b) {
      final byStart = a.startedAtUtc.compareTo(b.startedAtUtc);
      return byStart == 0 ? a.workoutId.compareTo(b.workoutId) : byStart;
    });
  return finished;
}

/// Zählt für Kennzahlen, Rekorde und Zähler: beendet und nicht gelöscht.
bool isCountedWorkout(Workout workout) =>
    workout.endedAtUtc != null && workout.deletedAtUtc == null;

DateTime _parseCalendarDay(String value) {
  final parts = value.split('-');
  return DateTime.utc(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

double? _maxOrNull(Iterable<double> values) {
  double? max;
  for (final value in values) {
    if (max == null || value > max) max = value;
  }
  return max;
}
