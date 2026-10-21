import 'workout_model.dart';

class PlanEntry {
  const PlanEntry({
    required this.entryId,
    required this.exerciseId,
    this.warmupSets = 0,
    this.workingSets = 3,
    this.notes,
    this.supersetId,
  });

  factory PlanEntry.fromJson(Map<String, Object?> json) => PlanEntry(
    entryId: json['entryId'] as String,
    exerciseId: json['exerciseId'] as String,
    warmupSets: (json['warmupSets'] as num).toInt(),
    workingSets: (json['workingSets'] as num).toInt(),
    notes: json['notes'] as String?,
    supersetId: json['supersetId'] as String?,
  );

  final String entryId;
  final String exerciseId;
  final int warmupSets;
  final int workingSets;
  final String? notes;
  final String? supersetId;

  PlanEntry copyWith({
    String? entryId,
    String? exerciseId,
    int? warmupSets,
    int? workingSets,
    String? Function()? notes,
    String? Function()? supersetId,
  }) => PlanEntry(
    entryId: entryId ?? this.entryId,
    exerciseId: exerciseId ?? this.exerciseId,
    warmupSets: warmupSets ?? this.warmupSets,
    workingSets: workingSets ?? this.workingSets,
    notes: notes != null ? notes() : this.notes,
    supersetId: supersetId != null ? supersetId() : this.supersetId,
  );

  Map<String, Object?> toJson() => {
    'entryId': entryId,
    'exerciseId': exerciseId,
    'warmupSets': warmupSets,
    'workingSets': workingSets,
    'notes': notes,
    'supersetId': supersetId,
  };

  @override
  bool operator ==(Object other) =>
      other is PlanEntry &&
      other.entryId == entryId &&
      other.exerciseId == exerciseId &&
      other.warmupSets == warmupSets &&
      other.workingSets == workingSets &&
      other.notes == notes &&
      other.supersetId == supersetId;

  @override
  int get hashCode => Object.hash(
    entryId,
    exerciseId,
    warmupSets,
    workingSets,
    notes,
    supersetId,
  );
}

class TrainingPlanModel {
  TrainingPlanModel({
    required this.planId,
    required this.name,
    this.notes,
    required this.previousValueSource,
    List<PlanEntry> entries = const [],
    this.sortOrder = 0,
    this.isArchived = false,
  }) : entries = List.unmodifiable(entries);

  factory TrainingPlanModel.fromJson(Map<String, Object?> json) =>
      TrainingPlanModel(
        planId: json['planId'] as String,
        name: json['name'] as String,
        notes: json['notes'] as String?,
        previousValueSource: PreviousValueSource.fromWireValue(
          json['previousValueSource'] as String,
        ),
        entries: [
          for (final entry in (json['entries'] as List<Object?>? ?? const []))
            PlanEntry.fromJson(entry! as Map<String, Object?>),
        ],
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
        isArchived: json['isArchived'] as bool? ?? false,
      );

  final String planId;
  final String name;
  final String? notes;
  final PreviousValueSource previousValueSource;
  final List<PlanEntry> entries;
  final int sortOrder;
  final bool isArchived;

  TrainingPlanModel copyWith({
    String? planId,
    String? name,
    String? Function()? notes,
    PreviousValueSource? previousValueSource,
    List<PlanEntry>? entries,
    int? sortOrder,
    bool? isArchived,
  }) => TrainingPlanModel(
    planId: planId ?? this.planId,
    name: name ?? this.name,
    notes: notes != null ? notes() : this.notes,
    previousValueSource: previousValueSource ?? this.previousValueSource,
    entries: entries ?? this.entries,
    sortOrder: sortOrder ?? this.sortOrder,
    isArchived: isArchived ?? this.isArchived,
  );

  Map<String, Object?> toJson() => {
    'planId': planId,
    'name': name,
    'notes': notes,
    'previousValueSource': previousValueSource.wireValue,
    'entries': [for (final entry in entries) entry.toJson()],
    'sortOrder': sortOrder,
    'isArchived': isArchived,
  };

  @override
  bool operator ==(Object other) =>
      other is TrainingPlanModel &&
      other.planId == planId &&
      other.name == name &&
      other.notes == notes &&
      other.previousValueSource == previousValueSource &&
      other.sortOrder == sortOrder &&
      other.isArchived == isArchived &&
      listsEqual(other.entries, entries);

  @override
  int get hashCode => Object.hash(
    planId,
    name,
    notes,
    previousValueSource,
    sortOrder,
    isArchived,
    Object.hashAll(entries),
  );
}
