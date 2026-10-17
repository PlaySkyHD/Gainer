import 'package:flutter/foundation.dart';

import '../../../domain/models/training/workout_input.dart';
import '../sync/local_sync_store.dart';

const _preferencesKey = 'trainingPreferences';

/// Anzeigeeinstellungen des Trainings. Gerätezustand des Kontos: keine
/// Sync-Mutation und keine Workout-Version.
final class TrainingPreferenceValues {
  const TrainingPreferenceValues({
    this.showRir = false,
    this.weightUnit = WeightUnit.kg,
    this.liveActivityDetails = false,
  });

  final bool showRir;
  final WeightUnit weightUnit;

  /// Training, Übung und Satzposition auf dem Sperrbildschirm. Gewichte und
  /// Wiederholungen erscheinen dort nie.
  final bool liveActivityDetails;

  TrainingPreferenceValues copyWith({
    bool? showRir,
    WeightUnit? weightUnit,
    bool? liveActivityDetails,
  }) => TrainingPreferenceValues(
    showRir: showRir ?? this.showRir,
    weightUnit: weightUnit ?? this.weightUnit,
    liveActivityDetails: liveActivityDetails ?? this.liveActivityDetails,
  );

  Map<String, Object?> toJson() => {
    'showRir': showRir,
    'weightUnit': weightUnit.name,
    'liveActivityDetails': liveActivityDetails,
  };

  @override
  bool operator ==(Object other) =>
      other is TrainingPreferenceValues &&
      other.showRir == showRir &&
      other.weightUnit == weightUnit &&
      other.liveActivityDetails == liveActivityDetails;

  @override
  int get hashCode => Object.hash(showRir, weightUnit, liveActivityDetails);
}

/// Liest und schreibt die Trainingseinstellungen über die kontogebundenen
/// Metadaten des lokalen Sync-Speichers. Jedes Konto hat eine eigene Datenbank,
/// daher gelten die Werte nur für das Konto, das sie gespeichert hat.
class TrainingPreferences {
  TrainingPreferences({required this.store});

  final LocalSyncStore store;

  /// Aktueller Wert der Detailfreigabe. Die Live Activity beobachtet ihn, damit
  /// eine Änderung sofort ankommt.
  final ValueNotifier<bool> liveActivityDetails = ValueNotifier(false);

  Future<TrainingPreferenceValues> read() async {
    final raw = await store.readSyncMetadata(_preferencesKey);
    final values = _decode(raw);
    liveActivityDetails.value = values.liveActivityDetails;
    return values;
  }

  Future<void> write(TrainingPreferenceValues values) async {
    await store.writeSyncMetadata(_preferencesKey, values.toJson());
    liveActivityDetails.value = values.liveActivityDetails;
  }

  static TrainingPreferenceValues _decode(Object? raw) {
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
      liveActivityDetails: raw['liveActivityDetails'] == true,
    );
  }
}
