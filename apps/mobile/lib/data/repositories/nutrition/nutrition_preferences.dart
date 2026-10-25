import 'package:flutter/foundation.dart';

import '../../../domain/models/nutrition/water_intake.dart';
import '../sync/local_sync_store.dart';

const _preferencesKey = 'nutritionPreferences';

/// Einstellungen der Ernährung. Gerätezustand des Kontos, keine
/// Sync-Mutation (D7).
@immutable
final class NutritionPreferenceValues {
  const NutritionPreferenceValues({
    this.waterEnabled = false,
    this.waterGoalMl = WaterIntakeLimits.defaultGoalMl,
  });

  /// Zeigt die Wasser-Karte im Ernährungstag; standardmäßig aus.
  final bool waterEnabled;

  /// Tagesziel in ml (250–10.000).
  final int waterGoalMl;

  NutritionPreferenceValues copyWith({bool? waterEnabled, int? waterGoalMl}) =>
      NutritionPreferenceValues(
        waterEnabled: waterEnabled ?? this.waterEnabled,
        waterGoalMl: waterGoalMl ?? this.waterGoalMl,
      );

  Map<String, Object?> toJson() => {
    'waterEnabled': waterEnabled,
    'waterGoalMl': waterGoalMl,
  };

  /// Ungültige oder fehlende Werte fallen einzeln auf den Standard zurück.
  factory NutritionPreferenceValues.fromJson(Object? raw) {
    if (raw is! Map) return const NutritionPreferenceValues();
    final enabled = raw['waterEnabled'];
    final goal = raw['waterGoalMl'];
    return NutritionPreferenceValues(
      waterEnabled: enabled is bool && enabled,
      waterGoalMl: goal is int && WaterIntakeLimits.isValidGoal(goal)
          ? goal
          : WaterIntakeLimits.defaultGoalMl,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NutritionPreferenceValues &&
      other.waterEnabled == waterEnabled &&
      other.waterGoalMl == waterGoalMl;

  @override
  int get hashCode => Object.hash(waterEnabled, waterGoalMl);
}

/// Liest und schreibt die Ernährungs-Einstellungen über die kontogebundenen
/// Metadaten des lokalen Sync-Speichers. Jedes Konto hat eine eigene
/// Datenbank, daher gelten die Werte nur für das Konto, das sie gespeichert hat.
class NutritionPreferences {
  NutritionPreferences({required this.store});

  final LocalSyncStore store;

  /// Zuletzt gelesener oder geschriebener Stand, damit Oberflächen sofort
  /// folgen.
  final ValueNotifier<NutritionPreferenceValues> values = ValueNotifier(
    const NutritionPreferenceValues(),
  );

  Future<NutritionPreferenceValues> read() async {
    final decoded = NutritionPreferenceValues.fromJson(
      await store.readSyncMetadata(_preferencesKey),
    );
    values.value = decoded;
    return decoded;
  }

  Future<void> _queue = Future.value();

  /// Liest, wendet [change] an und schreibt nur bei Änderung zurück.
  /// Änderungen laufen nacheinander, damit zwei schnelle Eingaben (Schalter
  /// und Ziel) nicht vom selben alten Stand ausgehen und sich überschreiben.
  Future<NutritionPreferenceValues> update(
    NutritionPreferenceValues Function(NutritionPreferenceValues current)
    change,
  ) {
    final result = _queue.then((_) async {
      final current = await read();
      final next = change(current);
      if (next != current) {
        await store.writeSyncMetadata(_preferencesKey, next.toJson());
        values.value = next;
      }
      return next;
    });
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }
}
