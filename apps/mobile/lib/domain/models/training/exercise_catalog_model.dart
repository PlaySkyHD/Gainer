import 'workout_model.dart';

class CatalogCategory {
  const CatalogCategory({
    required this.id,
    required this.name,
    required this.isBase,
    this.isArchived = false,
  });

  factory CatalogCategory.fromJson(Map<String, Object?> json) =>
      CatalogCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        isBase: json['isBase'] as bool? ?? false,
        isArchived: json['isArchived'] as bool? ?? false,
      );

  final String id;
  final String name;
  final bool isBase;
  final bool isArchived;

  CatalogCategory copyWith({
    String? id,
    String? name,
    bool? isBase,
    bool? isArchived,
  }) => CatalogCategory(
    id: id ?? this.id,
    name: name ?? this.name,
    isBase: isBase ?? this.isBase,
    isArchived: isArchived ?? this.isArchived,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'isBase': isBase,
    'isArchived': isArchived,
  };

  @override
  bool operator ==(Object other) =>
      other is CatalogCategory &&
      other.id == id &&
      other.name == name &&
      other.isBase == isBase &&
      other.isArchived == isArchived;

  @override
  int get hashCode => Object.hash(id, name, isBase, isArchived);
}

class CatalogExercise {
  const CatalogExercise({
    required this.id,
    required this.name,
    required this.exerciseType,
    this.description,
    this.targetMuscle,
    this.muscleGroup,
    this.equipment,
    this.notes,
    this.bodyweightFactor,
    this.weightFactor,
    this.categoryIds = const [],
    required this.isBase,
    this.isArchived = false,
  });

  factory CatalogExercise.fromJson(Map<String, Object?> json) =>
      CatalogExercise(
        id: json['id'] as String,
        name: json['name'] as String,
        exerciseType: ExerciseKind.fromWireValue(
          json['exerciseType'] as String,
        ),
        description: json['description'] as String?,
        targetMuscle: json['targetMuscle'] as String?,
        muscleGroup: json['muscleGroup'] as String?,
        equipment: json['equipment'] as String?,
        notes: json['notes'] as String?,
        bodyweightFactor: (json['bodyweightFactor'] as num?)?.toDouble(),
        weightFactor: (json['weightFactor'] as num?)?.toDouble(),
        categoryIds: [
          for (final id in (json['categoryIds'] as List<Object?>? ?? const []))
            id! as String,
        ],
        isBase: json['isBase'] as bool? ?? false,
        isArchived: json['isArchived'] as bool? ?? false,
      );

  final String id;
  final String name;
  final ExerciseKind exerciseType;
  final String? description;
  final String? targetMuscle;
  final String? muscleGroup;
  final String? equipment;
  final String? notes;

  /// Anteil des Körpergewichts (0–1), wie in der Übungsdefinition gespeichert.
  final double? bodyweightFactor;

  /// Faktor auf das Zusatzgewicht (> 0, höchstens 10).
  final double? weightFactor;
  final List<String> categoryIds;
  final bool isBase;
  final bool isArchived;

  /// Eigener Faktor vor Katalogwert. Ohne beides: 0 bei Kraft, sonst 1.
  double get effectiveBodyweightFactor =>
      bodyweightFactor ?? (exerciseType == ExerciseKind.strength ? 0 : 1);

  /// Eigener Faktor vor Katalogwert. Ohne beides: 1.
  double get effectiveWeightFactor => weightFactor ?? 1;

  CatalogExercise copyWith({
    String? id,
    String? name,
    ExerciseKind? exerciseType,
    String? Function()? description,
    String? Function()? targetMuscle,
    String? Function()? muscleGroup,
    String? Function()? equipment,
    String? Function()? notes,
    double? Function()? bodyweightFactor,
    double? Function()? weightFactor,
    List<String>? categoryIds,
    bool? isBase,
    bool? isArchived,
  }) => CatalogExercise(
    id: id ?? this.id,
    name: name ?? this.name,
    exerciseType: exerciseType ?? this.exerciseType,
    description: description != null ? description() : this.description,
    targetMuscle: targetMuscle != null ? targetMuscle() : this.targetMuscle,
    muscleGroup: muscleGroup != null ? muscleGroup() : this.muscleGroup,
    equipment: equipment != null ? equipment() : this.equipment,
    notes: notes != null ? notes() : this.notes,
    bodyweightFactor: bodyweightFactor != null
        ? bodyweightFactor()
        : this.bodyweightFactor,
    weightFactor: weightFactor != null ? weightFactor() : this.weightFactor,
    categoryIds: categoryIds ?? this.categoryIds,
    isBase: isBase ?? this.isBase,
    isArchived: isArchived ?? this.isArchived,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'exerciseType': exerciseType.wireValue,
    'description': description,
    'targetMuscle': targetMuscle,
    'muscleGroup': muscleGroup,
    'equipment': equipment,
    'notes': notes,
    'bodyweightFactor': bodyweightFactor,
    'weightFactor': weightFactor,
    'categoryIds': categoryIds,
    'isBase': isBase,
    'isArchived': isArchived,
  };

  @override
  bool operator ==(Object other) =>
      other is CatalogExercise &&
      other.id == id &&
      other.name == name &&
      other.exerciseType == exerciseType &&
      other.description == description &&
      other.targetMuscle == targetMuscle &&
      other.muscleGroup == muscleGroup &&
      other.equipment == equipment &&
      other.notes == notes &&
      other.bodyweightFactor == bodyweightFactor &&
      other.weightFactor == weightFactor &&
      listsEqual(other.categoryIds, categoryIds) &&
      other.isBase == isBase &&
      other.isArchived == isArchived;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    exerciseType,
    description,
    targetMuscle,
    muscleGroup,
    equipment,
    notes,
    bodyweightFactor,
    weightFactor,
    Object.hashAll(categoryIds),
    isBase,
    isArchived,
  );
}
