import 'package:flutter/foundation.dart';

import '../../../domain/models/cardio/cardio_session.dart';
import '../../../domain/models/cardio/cardio_template.dart';
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
    this.templates = const [],
    this.lastTemplateId,
    this.offerAfterStrength = true,
    this.voiceEnabled = false,
    this.voiceIntervalMinutes = 0,
  });

  static const defaultWeeklyTargetMinutes = 150;
  static const minWeeklyTargetMinutes = 30;
  static const maxWeeklyTargetMinutes = 600;
  static const defaultHrvMinutes = 2;
  static const minHrvMinutes = 1;
  static const maxHrvMinutes = 5;
  static const maxTemplates = 50;

  /// Erlaubte Intervalle der Sprachansage in Minuten; 0 = aus.
  static const voiceIntervalOptions = [0, 1, 2, 5, 10];

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

  /// Eigene Vorlagen; die mitgelieferten kommen über [allTemplates] dazu.
  final List<CardioTemplate> templates;

  /// Zuletzt genutzte Vorlage; null = zuletzt freie Einheit mit Zielbereich.
  final String? lastTemplateId;

  /// Nach dem Krafttraining „Cardio anhängen“ anbieten.
  final bool offerAfterStrength;

  /// Sprachansagen (Standard aus) und Intervall der Zeitansage (0 = aus).
  final bool voiceEnabled;
  final int voiceIntervalMinutes;

  /// Mitgelieferte Vorlagen zuerst, dann eigene.
  List<CardioTemplate> get allTemplates => [
    ...CardioTemplate.builtIns,
    ...templates,
  ];

  CardioTemplate? templateById(String? id) {
    if (id == null) return null;
    for (final template in allTemplates) {
      if (template.id == id) return template;
    }
    return null;
  }

  /// Zuletzt genutzte Vorlage, falls sie noch existiert.
  CardioTemplate? get lastTemplate => templateById(lastTemplateId);

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
    List<CardioTemplate>? templates,
    String? Function()? lastTemplateId,
    bool? offerAfterStrength,
    bool? voiceEnabled,
    int? voiceIntervalMinutes,
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
    templates: templates ?? this.templates,
    lastTemplateId: lastTemplateId == null
        ? this.lastTemplateId
        : lastTemplateId(),
    offerAfterStrength: offerAfterStrength ?? this.offerAfterStrength,
    voiceEnabled: voiceEnabled ?? this.voiceEnabled,
    voiceIntervalMinutes: voiceIntervalMinutes ?? this.voiceIntervalMinutes,
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
    'templates': [for (final t in templates) t.toJson()],
    'lastTemplateId': lastTemplateId,
    'offerAfterStrength': offerAfterStrength,
    'voiceEnabled': voiceEnabled,
    'voiceIntervalMinutes': voiceIntervalMinutes,
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
      other.hrvMinutes == hrvMinutes &&
      listEquals(other.templates, templates) &&
      other.lastTemplateId == lastTemplateId &&
      other.offerAfterStrength == offerAfterStrength &&
      other.voiceEnabled == voiceEnabled &&
      other.voiceIntervalMinutes == voiceIntervalMinutes;

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
    Object.hashAll(templates),
    lastTemplateId,
    offerAfterStrength,
    voiceEnabled,
    voiceIntervalMinutes,
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

  Future<void> _queue = Future.value();

  /// Liest, wendet [change] an und schreibt nur bei Änderung zurück.
  /// Änderungen laufen nacheinander, damit zwei schnelle Eingaben nicht vom
  /// selben alten Stand ausgehen und sich überschreiben.
  Future<CardioPreferenceValues> update(
    CardioPreferenceValues Function(CardioPreferenceValues current) change,
  ) {
    final result = _queue.then((_) async {
      final current = await read();
      final next = change(current);
      if (next != current) await write(next);
      return next;
    });
    _queue = result.then((_) {}, onError: (_) {});
    return result;
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
      templates: _decodeTemplates(raw['templates']),
      lastTemplateId: raw['lastTemplateId'] is String
          ? raw['lastTemplateId'] as String
          : null,
      offerAfterStrength: raw['offerAfterStrength'] is bool
          ? raw['offerAfterStrength'] as bool
          : true,
      voiceEnabled: raw['voiceEnabled'] is bool
          ? raw['voiceEnabled'] as bool
          : false,
      voiceIntervalMinutes:
          CardioPreferenceValues.voiceIntervalOptions.contains(
            raw['voiceIntervalMinutes'],
          )
          ? (raw['voiceIntervalMinutes'] as num).toInt()
          : 0,
    );
  }

  /// Ungültige oder doppelte Vorlagen entfallen einzeln, statt alle zu
  /// verwerfen.
  static List<CardioTemplate> _decodeTemplates(Object? raw) {
    if (raw is! List) return const [];
    final result = <CardioTemplate>[];
    final seen = <String>{
      for (final builtIn in CardioTemplate.builtIns) builtIn.id,
    };
    for (final entry in raw) {
      try {
        if (entry is! Map<String, dynamic>) continue;
        final template = CardioTemplate.fromJson(entry);
        if (template.validate() != null || !seen.add(template.id)) continue;
        result.add(template);
      } on Object {
        continue;
      }
    }
    return result.take(CardioPreferenceValues.maxTemplates).toList();
  }
}
