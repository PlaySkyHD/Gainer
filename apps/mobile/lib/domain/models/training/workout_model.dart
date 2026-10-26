import 'unknown_wire_value_exception.dart';

typedef IdFactory = String Function();

enum ExerciseKind {
  strength,
  bodyweightLoaded,
  bodyweightOnly,
  assisted;

  String get wireValue => name;

  static ExerciseKind fromWireValue(String value) {
    final kind = _enumByName(values, value);
    if (kind == null) {
      throw UnknownWireValueException('Unbekannter Übungstyp: $value');
    }
    return kind;
  }
}

enum SetType {
  normal,
  warmup,
  dropset;

  String get wireValue => name;

  /// Unbekannte Typen aus dem Sync werden bewusst als normale Sätze gelesen.
  static SetType fromWireValue(String? value) =>
      _enumByName(values, value) ?? SetType.normal;
}

enum PreviousValueSource {
  exercise,
  plan,
  workout;

  String get wireValue => name;

  static PreviousValueSource fromWireValue(String value) {
    final source = _enumByName(values, value);
    if (source == null) {
      throw UnknownWireValueException('Unbekannte Vorwertquelle: $value');
    }
    return source;
  }
}

class LoggedSet {
  const LoggedSet({
    required this.setId,
    this.setType = SetType.normal,
    this.weightKg,
    this.repetitions,
    this.rir,
    this.notes,
  });

  factory LoggedSet.fromJson(Map<String, Object?> json) => LoggedSet(
    setId: json['setId'] as String,
    setType: SetType.fromWireValue(json['setType'] as String?),
    weightKg: (json['weightKg'] as num?)?.toDouble(),
    repetitions: (json['repetitions'] as num?)?.toInt(),
    rir: (json['rir'] as num?)?.toInt(),
    notes: json['notes'] as String?,
  );

  final String setId;
  final SetType setType;
  final double? weightKg;
  final int? repetitions;
  final int? rir;
  final String? notes;

  LoggedSet copyWith({
    String? setId,
    SetType? setType,
    double? Function()? weightKg,
    int? Function()? repetitions,
    int? Function()? rir,
    String? Function()? notes,
  }) => LoggedSet(
    setId: setId ?? this.setId,
    setType: setType ?? this.setType,
    weightKg: weightKg != null ? weightKg() : this.weightKg,
    repetitions: repetitions != null ? repetitions() : this.repetitions,
    rir: rir != null ? rir() : this.rir,
    notes: notes != null ? notes() : this.notes,
  );

  Map<String, Object?> toJson() => {
    'setId': setId,
    'setType': setType.wireValue,
    'weightKg': weightKg,
    'repetitions': repetitions,
    'rir': rir,
    'notes': notes,
  };

  @override
  bool operator ==(Object other) =>
      other is LoggedSet &&
      other.setId == setId &&
      other.setType == setType &&
      other.weightKg == weightKg &&
      other.repetitions == repetitions &&
      other.rir == rir &&
      other.notes == notes;

  @override
  int get hashCode =>
      Object.hash(setId, setType, weightKg, repetitions, rir, notes);
}

class WorkoutBlock {
  WorkoutBlock({
    required this.workoutExerciseId,
    required this.sourceExerciseId,
    required this.exerciseNameSnapshot,
    required this.exerciseTypeSnapshot,
    this.notes,
    this.supersetId,
    List<LoggedSet> sets = const [],
  }) : sets = List.unmodifiable(sets);

  factory WorkoutBlock.fromJson(Map<String, Object?> json) => WorkoutBlock(
    workoutExerciseId: json['workoutExerciseId'] as String,
    sourceExerciseId: json['sourceExerciseId'] as String,
    exerciseNameSnapshot: json['exerciseNameSnapshot'] as String,
    exerciseTypeSnapshot: ExerciseKind.fromWireValue(
      json['exerciseTypeSnapshot'] as String,
    ),
    notes: json['notes'] as String?,
    supersetId: json['supersetId'] as String?,
    sets: [
      for (final set in (json['sets'] as List<Object?>? ?? const []))
        LoggedSet.fromJson(set! as Map<String, Object?>),
    ],
  );

  final String workoutExerciseId;
  final String sourceExerciseId;
  final String exerciseNameSnapshot;
  final ExerciseKind exerciseTypeSnapshot;
  final String? notes;
  final String? supersetId;
  final List<LoggedSet> sets;

  WorkoutBlock copyWith({
    String? workoutExerciseId,
    String? sourceExerciseId,
    String? exerciseNameSnapshot,
    ExerciseKind? exerciseTypeSnapshot,
    String? Function()? notes,
    String? Function()? supersetId,
    List<LoggedSet>? sets,
  }) => WorkoutBlock(
    workoutExerciseId: workoutExerciseId ?? this.workoutExerciseId,
    sourceExerciseId: sourceExerciseId ?? this.sourceExerciseId,
    exerciseNameSnapshot: exerciseNameSnapshot ?? this.exerciseNameSnapshot,
    exerciseTypeSnapshot: exerciseTypeSnapshot ?? this.exerciseTypeSnapshot,
    notes: notes != null ? notes() : this.notes,
    supersetId: supersetId != null ? supersetId() : this.supersetId,
    sets: sets ?? this.sets,
  );

  Map<String, Object?> toJson() => {
    'workoutExerciseId': workoutExerciseId,
    'sourceExerciseId': sourceExerciseId,
    'exerciseNameSnapshot': exerciseNameSnapshot,
    'exerciseTypeSnapshot': exerciseTypeSnapshot.wireValue,
    'notes': notes,
    'supersetId': supersetId,
    'sets': [for (final set in sets) set.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is WorkoutBlock &&
      other.workoutExerciseId == workoutExerciseId &&
      other.sourceExerciseId == sourceExerciseId &&
      other.exerciseNameSnapshot == exerciseNameSnapshot &&
      other.exerciseTypeSnapshot == exerciseTypeSnapshot &&
      other.notes == notes &&
      other.supersetId == supersetId &&
      listsEqual(other.sets, sets);

  @override
  int get hashCode => Object.hash(
    workoutExerciseId,
    sourceExerciseId,
    exerciseNameSnapshot,
    exerciseTypeSnapshot,
    notes,
    supersetId,
    Object.hashAll(sets),
  );
}

class Workout {
  Workout({
    required this.workoutId,
    required this.title,
    this.notes,
    required this.startedAtUtc,
    this.endedAtUtc,
    required this.previousValueSource,
    this.sourcePlanId,
    this.sourceWorkoutId,
    List<WorkoutBlock> exercises = const [],
    this.deletedAtUtc,
  }) : exercises = List.unmodifiable(exercises);

  factory Workout.fromJson(Map<String, Object?> json) => Workout(
    workoutId: json['workoutId'] as String,
    title: json['title'] as String,
    notes: json['notes'] as String?,
    startedAtUtc: _dateTimeFromJson(json['startedAtUtc'] as String),
    endedAtUtc: _nullableDateTimeFromJson(json['endedAtUtc']),
    previousValueSource: PreviousValueSource.fromWireValue(
      json['previousValueSource'] as String,
    ),
    sourcePlanId: json['sourcePlanId'] as String?,
    sourceWorkoutId: json['sourceWorkoutId'] as String?,
    exercises: [
      for (final block in (json['exercises'] as List<Object?>? ?? const []))
        WorkoutBlock.fromJson(block! as Map<String, Object?>),
    ],
    deletedAtUtc: _nullableDateTimeFromJson(json['deletedAtUtc']),
  );

  final String workoutId;
  final String title;
  final String? notes;
  final DateTime startedAtUtc;
  final DateTime? endedAtUtc;
  final PreviousValueSource previousValueSource;
  final String? sourcePlanId;
  final String? sourceWorkoutId;
  final List<WorkoutBlock> exercises;
  final DateTime? deletedAtUtc;

  /// Ein Training ist aktiv, solange es weder beendet noch gelöscht ist.
  bool get isActive => endedAtUtc == null && deletedAtUtc == null;

  Workout copyWith({
    String? workoutId,
    String? title,
    String? Function()? notes,
    DateTime? startedAtUtc,
    DateTime? Function()? endedAtUtc,
    PreviousValueSource? previousValueSource,
    String? Function()? sourcePlanId,
    String? Function()? sourceWorkoutId,
    List<WorkoutBlock>? exercises,
    DateTime? Function()? deletedAtUtc,
  }) => Workout(
    workoutId: workoutId ?? this.workoutId,
    title: title ?? this.title,
    notes: notes != null ? notes() : this.notes,
    startedAtUtc: startedAtUtc ?? this.startedAtUtc,
    endedAtUtc: endedAtUtc != null ? endedAtUtc() : this.endedAtUtc,
    previousValueSource: previousValueSource ?? this.previousValueSource,
    sourcePlanId: sourcePlanId != null ? sourcePlanId() : this.sourcePlanId,
    sourceWorkoutId: sourceWorkoutId != null
        ? sourceWorkoutId()
        : this.sourceWorkoutId,
    exercises: exercises ?? this.exercises,
    deletedAtUtc: deletedAtUtc != null ? deletedAtUtc() : this.deletedAtUtc,
  );

  /// Serialisiert alle Felder, auch lokale Zustände wie `deletedAtUtc`, damit
  /// gespeicherte Envelopes verlustfrei zurückgelesen werden. Der Sync-Codec
  /// wählt die Payload-Felder aus.
  Map<String, Object?> toJson() => {
    'workoutId': workoutId,
    'title': title,
    'notes': notes,
    'startedAtUtc': _dateTimeToJson(startedAtUtc),
    'endedAtUtc': endedAtUtc == null ? null : _dateTimeToJson(endedAtUtc!),
    'previousValueSource': previousValueSource.wireValue,
    'sourcePlanId': sourcePlanId,
    'sourceWorkoutId': sourceWorkoutId,
    'exercises': [for (final block in exercises) block.toJson()],
    'deletedAtUtc': deletedAtUtc == null
        ? null
        : _dateTimeToJson(deletedAtUtc!),
  };

  @override
  bool operator ==(Object other) =>
      other is Workout &&
      other.workoutId == workoutId &&
      other.title == title &&
      other.notes == notes &&
      other.startedAtUtc == startedAtUtc &&
      other.endedAtUtc == endedAtUtc &&
      other.previousValueSource == previousValueSource &&
      other.sourcePlanId == sourcePlanId &&
      other.sourceWorkoutId == sourceWorkoutId &&
      other.deletedAtUtc == deletedAtUtc &&
      listsEqual(other.exercises, exercises);

  @override
  int get hashCode => Object.hash(
    workoutId,
    title,
    notes,
    startedAtUtc,
    endedAtUtc,
    previousValueSource,
    sourcePlanId,
    sourceWorkoutId,
    deletedAtUtc,
    Object.hashAll(exercises),
  );
}

/// Gleiche Länge und gleiche Elemente in gleicher Reihenfolge.
bool listsEqual<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

T? _enumByName<T extends Enum>(List<T> values, String? name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}

DateTime _dateTimeFromJson(String value) => DateTime.parse(value).toUtc();

DateTime? _nullableDateTimeFromJson(Object? value) =>
    value == null ? null : _dateTimeFromJson(value as String);

String _dateTimeToJson(DateTime value) => value.toUtc().toIso8601String();
