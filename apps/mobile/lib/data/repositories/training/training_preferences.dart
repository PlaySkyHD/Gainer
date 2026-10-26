import 'package:flutter/foundation.dart';

import '../../../domain/models/timer/rest_timer_sound.dart';
import '../../../domain/models/training/warmup.dart';
import '../../../domain/models/training/workout_input.dart';
import '../sync/local_sync_store.dart';

const _preferencesKey = 'trainingPreferences';

/// Anzeigeeinstellungen des Trainings. Gerätezustand des Kontos: keine
/// Sync-Mutation und keine Workout-Version.
final class TrainingPreferenceValues {
  const TrainingPreferenceValues({
    this.showRir = false,
    this.weightUnit = WeightUnit.kg,
    this.liveActivityDetails = true,
    this.timerSoundId = RestTimerSound.defaultId,
    this.autoStartRestTimer = false,
    this.warmup = const WarmupSettings(),
    this.warmupOverrides = const {},
  });

  final bool showRir;
  final WeightUnit weightUnit;

  /// Training, Übung und Satzposition auf dem Sperrbildschirm. Gewichte und
  /// Wiederholungen erscheinen dort nie.
  final bool liveActivityDetails;

  /// Ablaufton des Pausentimers (Id aus [RestTimerSound]).
  final String timerSoundId;

  /// Startet den Pausentimer, sobald ein Satz erfasst ist.
  final bool autoStartRestTimer;

  /// Globale Aufwärmhinweis-Einstellungen.
  final WarmupSettings warmup;

  /// Abweichungen je Übungs-ID; Übungen ohne Eintrag erben [warmup].
  final Map<String, ExerciseWarmupOverride> warmupOverrides;

  TrainingPreferenceValues copyWith({
    bool? showRir,
    WeightUnit? weightUnit,
    bool? liveActivityDetails,
    String? timerSoundId,
    bool? autoStartRestTimer,
    WarmupSettings? warmup,
    Map<String, ExerciseWarmupOverride>? warmupOverrides,
  }) => TrainingPreferenceValues(
    showRir: showRir ?? this.showRir,
    weightUnit: weightUnit ?? this.weightUnit,
    liveActivityDetails: liveActivityDetails ?? this.liveActivityDetails,
    timerSoundId: timerSoundId ?? this.timerSoundId,
    autoStartRestTimer: autoStartRestTimer ?? this.autoStartRestTimer,
    warmup: warmup ?? this.warmup,
    warmupOverrides: warmupOverrides ?? this.warmupOverrides,
  );

  Map<String, Object?> toJson() => {
    'showRir': showRir,
    'weightUnit': weightUnit.name,
    'liveActivityDetails': liveActivityDetails,
    'timerSoundId': timerSoundId,
    'autoStartRestTimer': autoStartRestTimer,
    'warmup': warmup.toJson(),
    'warmupOverrides': {
      for (final entry in warmupOverrides.entries)
        entry.key: entry.value.toJson(),
    },
  };

  @override
  bool operator ==(Object other) =>
      other is TrainingPreferenceValues &&
      other.showRir == showRir &&
      other.weightUnit == weightUnit &&
      other.liveActivityDetails == liveActivityDetails &&
      other.timerSoundId == timerSoundId &&
      other.autoStartRestTimer == autoStartRestTimer &&
      other.warmup == warmup &&
      mapEquals(other.warmupOverrides, warmupOverrides);

  @override
  int get hashCode => Object.hash(
    showRir,
    weightUnit,
    liveActivityDetails,
    timerSoundId,
    autoStartRestTimer,
    warmup,
    Object.hashAllUnordered(
      warmupOverrides.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}

/// Liest und schreibt die Trainingseinstellungen über die kontogebundenen
/// Metadaten des lokalen Sync-Speichers. Jedes Konto hat eine eigene Datenbank,
/// daher gelten die Werte nur für das Konto, das sie gespeichert hat.
class TrainingPreferences {
  TrainingPreferences({required this.store});

  final LocalSyncStore store;

  /// Aktueller Wert der Detailfreigabe. Die Live Activity beobachtet ihn, damit
  /// eine Änderung sofort ankommt.
  final ValueNotifier<bool> liveActivityDetails = ValueNotifier(true);

  /// Aktuelle Gewichtseinheit. Die Live Activity zeigt Zielwerte darin an und
  /// folgt Änderungen sofort.
  final ValueNotifier<WeightUnit> weightUnit = ValueNotifier(WeightUnit.kg);

  /// Gewählter Timerton. Der Pausentimer liest ihn beim Planen der
  /// Benachrichtigung und beim Ablauf.
  final ValueNotifier<String> timerSoundId = ValueNotifier(
    RestTimerSound.defaultId,
  );

  /// Automatischer Start des Pausentimers nach einem erfassten Satz.
  final ValueNotifier<bool> autoStartRestTimer = ValueNotifier(false);

  Future<TrainingPreferenceValues> read() async {
    final raw = await store.readSyncMetadata(_preferencesKey);
    final values = _decode(raw);
    _publish(values);
    return values;
  }

  Future<void> write(TrainingPreferenceValues values) async {
    await store.writeSyncMetadata(_preferencesKey, values.toJson());
    _publish(values);
  }

  Future<void> _queue = Future.value();

  /// Liest die gespeicherten Werte, wendet [change] an und schreibt sie zurück.
  /// Änderungen laufen nacheinander: Zwei schnelle Eingaben gehen sonst vom
  /// selben alten Stand aus, und die zweite verwirft die erste.
  Future<void> update(
    TrainingPreferenceValues Function(TrainingPreferenceValues current) change,
  ) {
    final result = _queue.then((_) async {
      final current = await read();
      final next = change(current);
      if (next != current) await write(next);
    });
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  void _publish(TrainingPreferenceValues values) {
    liveActivityDetails.value = values.liveActivityDetails;
    weightUnit.value = values.weightUnit;
    timerSoundId.value = values.timerSoundId;
    autoStartRestTimer.value = values.autoStartRestTimer;
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
      liveActivityDetails: raw['liveActivityDetails'] is bool
          ? raw['liveActivityDetails'] as bool
          : true,
      timerSoundId: RestTimerSound.resolveId(raw['timerSoundId']),
      autoStartRestTimer: raw['autoStartRestTimer'] == true,
      warmup: WarmupSettings.fromJson(raw['warmup']),
      warmupOverrides: _decodeOverrides(raw['warmupOverrides']),
    );
  }

  static Map<String, ExerciseWarmupOverride> _decodeOverrides(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.key is String)
          entry.key as String: ?ExerciseWarmupOverride.tryFromJson(
            entry.key as String,
            entry.value,
          ),
    };
  }
}
