import 'exercise_catalog_model.dart';
import 'muscles.dart';
import 'training_plan_model.dart';
import 'workout_model.dart';
import 'workout_rules.dart';

/// Anteil eines Hilfsmuskels an einem Arbeitssatz.
const secondaryMuscleShare = 0.5;

enum MuscleRole { primary, secondary }

/// Verweis auf eine Übung mit dem angezeigten Namen.
typedef ExerciseRef = ({String id, String name});

/// Beitrag einer Übung zu einem Muskel.
class MuscleContribution {
  const MuscleContribution({
    required this.exerciseId,
    required this.exerciseName,
    required this.role,
    required this.workingSets,
  });

  final String exerciseId;
  final String exerciseName;
  final MuscleRole role;

  /// Arbeitssätze der Übung, ungewichtet.
  final double workingSets;

  /// Gewichtete Sätze für den Muskel.
  double get sets => role == MuscleRole.primary
      ? workingSets
      : workingSets * secondaryMuscleShare;
}

/// Farbstufe einer Satzzahl (Design D4).
enum MuscleLevel {
  none,
  low,
  medium,
  high,
  veryHigh;

  static MuscleLevel of(double sets) {
    if (sets <= 0) return none;
    if (sets < 4) return low;
    if (sets < 10) return medium;
    if (sets <= 20) return high;
    return veryHigh;
  }
}

/// Gewichtete Sätze je Muskel mit den beitragenden Übungen.
class MuscleVolume {
  MuscleVolume._(this._contributions, this.exercisesWithoutMuscles);

  static final empty = MuscleVolume._(const {}, const []);

  /// Arbeitssätze je Plan-Eintrag. Archivierte Pläne zählen nicht.
  factory MuscleVolume.fromPlans(
    Iterable<TrainingPlanModel> plans,
    Map<String, CatalogExercise> exercisesById,
  ) {
    final builder = _Builder(exercisesById);
    for (final plan in plans) {
      if (plan.isArchived) continue;
      for (final entry in plan.entries) {
        builder.add(entry.exerciseId, null, entry.workingSets.toDouble());
      }
    }
    return builder.build();
  }

  /// Erfasste Arbeitssätze abgeschlossener Trainings mit Start in
  /// `[fromUtc, toUtc)`, geteilt durch [weeks] (Ø pro Woche).
  factory MuscleVolume.fromWorkouts(
    Iterable<Workout> workouts,
    Map<String, CatalogExercise> exercisesById, {
    required DateTime fromUtc,
    required DateTime toUtc,
    int weeks = 1,
  }) {
    final builder = _Builder(exercisesById);
    for (final workout in workouts) {
      if (!_countsInRange(workout, fromUtc, toUtc)) continue;
      for (final block in workout.exercises) {
        final sets = _recordedWorkingSets(block);
        if (sets == 0) continue;
        builder.add(
          block.sourceExerciseId,
          block.exerciseNameSnapshot,
          sets / weeks,
        );
      }
    }
    return builder.build();
  }

  static bool _countsInRange(
    Workout workout,
    DateTime fromUtc,
    DateTime toUtc,
  ) {
    final ongoingOrDeleted =
        workout.endedAtUtc == null || workout.deletedAtUtc != null;
    final started = workout.startedAtUtc;
    return !ongoingOrDeleted &&
        !started.isBefore(fromUtc) &&
        started.isBefore(toUtc);
  }

  static int _recordedWorkingSets(WorkoutBlock block) {
    var sets = 0;
    for (final set in block.sets) {
      if (set.setType == SetType.warmup) continue;
      if (isSetRecorded(set, block.exerciseTypeSnapshot)) sets++;
    }
    return sets;
  }

  final Map<Muscle, List<MuscleContribution>> _contributions;

  /// Übungen ohne Muskelangabe, alphabetisch nach Name.
  final List<ExerciseRef> exercisesWithoutMuscles;

  double setsFor(Muscle muscle) {
    var total = 0.0;
    for (final contribution in _contributions[muscle] ?? const []) {
      total += contribution.sets;
    }
    return total;
  }

  MuscleLevel levelFor(Muscle muscle) => MuscleLevel.of(setsFor(muscle));

  /// Beiträge zu einem Muskel, die größten zuerst.
  List<MuscleContribution> contributionsFor(Muscle muscle) =>
      _contributions[muscle] ?? const [];

  /// Alle Muskeln, absteigend nach Sätzen; Gleichstand in fester Reihenfolge.
  List<Muscle> get ranked {
    final muscles = [...Muscle.values];
    muscles.sort((a, b) {
      final bySets = setsFor(b).compareTo(setsFor(a));
      return bySets != 0 ? bySets : a.index.compareTo(b.index);
    });
    return muscles;
  }

  bool get isEmpty => _contributions.isEmpty;
}

class _Builder {
  _Builder(this.exercisesById);

  final Map<String, CatalogExercise> exercisesById;
  final _sets = <String, double>{};
  final _names = <String, String>{};

  void add(String exerciseId, String? fallbackName, double workingSets) {
    if (workingSets <= 0) return;
    _sets[exerciseId] = (_sets[exerciseId] ?? 0) + workingSets;
    _names.putIfAbsent(
      exerciseId,
      () => exercisesById[exerciseId]?.name ?? fallbackName ?? 'Übung',
    );
  }

  MuscleVolume build() {
    final contributions = <Muscle, List<MuscleContribution>>{};
    final withoutMuscles = <ExerciseRef>[];
    for (final MapEntry(key: id, value: sets) in _sets.entries) {
      final exercise = exercisesById[id];
      final name = _names[id]!;
      final primary = exercise?.primaryMuscles ?? const <Muscle>[];
      final secondary = exercise?.secondaryMuscles ?? const <Muscle>[];
      if (primary.isEmpty && secondary.isEmpty) {
        withoutMuscles.add((id: id, name: name));
        continue;
      }
      void put(Muscle muscle, MuscleRole role) =>
          (contributions[muscle] ??= []).add(
            MuscleContribution(
              exerciseId: id,
              exerciseName: name,
              role: role,
              workingSets: sets,
            ),
          );
      for (final muscle in primary) {
        put(muscle, MuscleRole.primary);
      }
      for (final muscle in secondary) {
        put(muscle, MuscleRole.secondary);
      }
    }
    for (final list in contributions.values) {
      list.sort((a, b) {
        final bySets = b.sets.compareTo(a.sets);
        return bySets != 0 ? bySets : a.exerciseName.compareTo(b.exerciseName);
      });
    }
    final names = withoutMuscles
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return MuscleVolume._({
      for (final MapEntry(:key, :value) in contributions.entries)
        key: List.unmodifiable(value),
    }, List.unmodifiable(names));
  }
}
