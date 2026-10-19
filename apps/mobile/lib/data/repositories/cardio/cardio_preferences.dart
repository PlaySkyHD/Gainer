import 'package:flutter/foundation.dart';

import '../../../domain/models/cardio/cardio_session.dart';
import '../../../domain/models/cardio/cardio_zones.dart';
import '../sync/local_sync_store.dart';

const _preferencesKey = 'cardioPreferences';

/// Einstellungen für Cardio. Gerätezustand des Kontos, keine Sync-Mutation.
final class CardioPreferenceValues {
  const CardioPreferenceValues({
    this.maxHeartRate,
    this.age,
    this.restingHeartRate,
    this.lastZoneLow = 120,
    this.lastZoneHigh = 140,
    this.warmupSeconds = 180,
    this.alertsEnabled = true,
    this.weeklyTargetMinutes = defaultWeeklyTargetMinutes,
    this.hrvMinutes = defaultHrvMinutes,
  });

  static const defaultWeeklyTargetMinutes = 150;
  static const minWeeklyTargetMinutes = 30;
  static const maxWeeklyTargetMinutes = 600;
  static const defaultHrvMinutes = 2;
  static const minHrvMinutes = 1;
  static const maxHrvMinutes = 5;

  /// Manuell angegebener Maximalpuls; hat Vorrang vor dem Alter.
  final int? maxHeartRate;
  final int? age;
  final int? restingHeartRate;

  /// Zuletzt genutzter Zielbereich, Vorbelegung im Start-Sheet.
  final int lastZoneLow;
  final int lastZoneHigh;

  /// Aufwärmzeit ohne Alarm (0–600 s).
  final int warmupSeconds;
  final bool alertsEnabled;

  /// Wochenziel in Minuten im Zielbereich (30–600).
  final int weeklyTargetMinutes;

  /// Messdauer der HRV-Messung in Minuten (1–5).
  final int hrvMinutes;

  /// Maximalpuls: angegebener Wert, sonst aus dem Alter, sonst null.
  int? get effectiveMaxHeartRate =>
      maxHeartRate ?? (age == null ? null : CardioZones.maxHeartRateFor(age!));

  /// Zonen 1–5 oder leer ohne Maximalpuls.
  List<CardioZone> get zones {
    final max = effectiveMaxHeartRate;
    return max == null ? const [] : CardioZones.compute(max, restingHeartRate);
  }

  CardioTargetZone get lastZone =>
      CardioTargetZone(lowBpm: lastZoneLow, highBpm: lastZoneHigh);

  /// Nullable Werte werden über Funktionen gesetzt (`age: () => null`).
  CardioPreferenceValues copyWith({
    int? Function()? maxHeartRate,
    int? Function()? age,
    int? Function()? restingHeartRate,
    int? lastZoneLow,
    int? lastZoneHigh,
    int? warmupSeconds,
    bool? alertsEnabled,
    int? weeklyTargetMinutes,
    int? hrvMinutes,
  }) => CardioPreferenceValues(
    maxHeartRate: maxHeartRate == null ? this.maxHeartRate : maxHeartRate(),
    age: age == null ? this.age : age(),
    restingHeartRate: restingHeartRate == null
        ? this.restingHeartRate
        : restingHeartRate(),
    lastZoneLow: lastZoneLow ?? this.lastZoneLow,
    lastZoneHigh: lastZoneHigh ?? this.lastZoneHigh,
    warmupSeconds: warmupSeconds ?? this.warmupSeconds,
    alertsEnabled: alertsEnabled ?? this.alertsEnabled,
    weeklyTargetMinutes: weeklyTargetMinutes ?? this.weeklyTargetMinutes,
    hrvMinutes: hrvMinutes ?? this.hrvMinutes,
  );

  Map<String, Object?> toJson() => {
    'maxHeartRate': maxHeartRate,
    'age': age,
    'restingHeartRate': restingHeartRate,
    'lastZoneLow': lastZoneLow,
    'lastZoneHigh': lastZoneHigh,
    'warmupSeconds': warmupSeconds,
    'alertsEnabled': alertsEnabled,
    'weeklyTargetMinutes': weeklyTargetMinutes,
    'hrvMinutes': hrvMinutes,
  };

  @override
  bool operator ==(Object other) =>
      other is CardioPreferenceValues &&
      other.maxHeartRate == maxHeartRate &&
      other.age == age &&
      other.restingHeartRate == restingHeartRate &&
      other.lastZoneLow == lastZoneLow &&
      other.lastZoneHigh == lastZoneHigh &&
      other.warmupSeconds == warmupSeconds &&
      other.alertsEnabled == alertsEnabled &&
      other.weeklyTargetMinutes == weeklyTargetMinutes &&
      other.hrvMinutes == hrvMinutes;

  @override
  int get hashCode => Object.hash(
    maxHeartRate,
    age,
    restingHeartRate,
    lastZoneLow,
    lastZoneHigh,
    warmupSeconds,
    alertsEnabled,
    weeklyTargetMinutes,
    hrvMinutes,
  );
}

/// Liest und schreibt die Cardio-Einstellungen über die kontogebundenen
/// Metadaten des lokalen Sync-Speichers (wie `TrainingPreferences`).
class CardioPreferences {
  CardioPreferences({required this.store});

  final LocalSyncStore store;

  /// Zuletzt gelesener oder geschriebener Stand; ändert sich bei jedem
  /// [read]/[write], damit Oberflächen sofort folgen.
  final ValueNotifier<CardioPreferenceValues> values = ValueNotifier(
    const CardioPreferenceValues(),
  );

  Future<CardioPreferenceValues> read() async {
    final decoded = _decode(await store.readSyncMetadata(_preferencesKey));
    values.value = decoded;
    return decoded;
  }

  Future<void> write(CardioPreferenceValues next) async {
    await store.writeSyncMetadata(_preferencesKey, next.toJson());
    values.value = next;
  }

  /// Liest, wendet [change] an und schreibt nur bei Änderung zurück.
  Future<CardioPreferenceValues> update(
    CardioPreferenceValues Function(CardioPreferenceValues current) change,
  ) async {
    final current = await read();
    final next = change(current);
    if (next != current) await write(next);
    return next;
  }

  static CardioPreferenceValues _decode(Object? raw) {
    if (raw == null) return const CardioPreferenceValues();
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Invalid cardio preferences.');
    }
    int? number(String key, int min, int max) {
      final value = raw[key];
      return value is num && value >= min && value <= max
          ? value.toInt()
          : null;
    }

    var low =
        number(
          'lastZoneLow',
          CardioTargetZone.minBpm,
          CardioTargetZone.maxBpm,
        ) ??
        120;
    var high =
        number(
          'lastZoneHigh',
          CardioTargetZone.minBpm,
          CardioTargetZone.maxBpm,
        ) ??
        140;
    if (low >= high) {
      low = 120;
      high = 140;
    }
    return CardioPreferenceValues(
      maxHeartRate: number('maxHeartRate', 100, 250),
      age: number('age', 10, 100),
      restingHeartRate: number('restingHeartRate', 30, 120),
      lastZoneLow: low,
      lastZoneHigh: high,
      warmupSeconds: number('warmupSeconds', 0, 600) ?? 180,
      alertsEnabled: raw['alertsEnabled'] is bool
          ? raw['alertsEnabled'] as bool
          : true,
      weeklyTargetMinutes:
          number(
            'weeklyTargetMinutes',
            CardioPreferenceValues.minWeeklyTargetMinutes,
            CardioPreferenceValues.maxWeeklyTargetMinutes,
          ) ??
          CardioPreferenceValues.defaultWeeklyTargetMinutes,
      hrvMinutes:
          number(
            'hrvMinutes',
            CardioPreferenceValues.minHrvMinutes,
            CardioPreferenceValues.maxHrvMinutes,
          ) ??
          CardioPreferenceValues.defaultHrvMinutes,
    );
  }
}
