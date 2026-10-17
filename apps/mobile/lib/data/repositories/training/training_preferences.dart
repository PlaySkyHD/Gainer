import '../../../domain/models/training/workout_input.dart';
import '../sync/local_sync_store.dart';

const _preferencesKey = 'trainingPreferences';

/// Anzeigeeinstellungen des Trainings. Gerätezustand des Kontos: keine
/// Sync-Mutation und keine Workout-Version.
final class TrainingPreferenceValues {
  const TrainingPreferenceValues({
    this.showRir = false,
    this.weightUnit = WeightUnit.kg,
  });

  final bool showRir;
  final WeightUnit weightUnit;

  TrainingPreferenceValues copyWith({bool? showRir, WeightUnit? weightUnit}) =>
      TrainingPreferenceValues(
        showRir: showRir ?? this.showRir,
        weightUnit: weightUnit ?? this.weightUnit,
      );

  Map<String, Object?> toJson() => {
    'showRir': showRir,
    'weightUnit': weightUnit.name,
  };

  @override
  bool operator ==(Object other) =>
      other is TrainingPreferenceValues &&
      other.showRir == showRir &&
      other.weightUnit == weightUnit;

  @override
  int get hashCode => Object.hash(showRir, weightUnit);
}

/// Liest und schreibt die Trainingseinstellungen über die kontogebundenen
/// Metadaten des lokalen Sync-Speichers.
class TrainingPreferences {
  TrainingPreferences({required this.store});

  final LocalSyncStore store;

  Future<TrainingPreferenceValues> read() async {
    final raw = await store.readSyncMetadata(_preferencesKey);
    if (raw == null) return const TrainingPreferenceValues();
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Invalid training preferences.');
    }
    final unitName = raw['weightUnit'];
    return TrainingPreferenceValues(
      showRir: raw['showRir'] == true,
      weightUnit:
          WeightUnit.values
              .where((unit) => unit.name == unitName)
              .firstOrNull ??
          WeightUnit.kg,
    );
  }

  Future<void> write(TrainingPreferenceValues values) {
    return store.writeSyncMetadata(_preferencesKey, values.toJson());
  }
}
