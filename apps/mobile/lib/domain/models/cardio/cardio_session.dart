/// Sportart einer Cardio-Einheit. [wireName] ist der Wert im Sync-Vertrag.
enum CardioActivityType {
  indoorCycling('IndoorCycling', 'Rad-Ergometer');

  const CardioActivityType(this.wireName, this.label);

  final String wireName;

  /// Anzeigename in der Oberfläche.
  final String label;

  static CardioActivityType fromWireName(Object? value) => values.firstWhere(
    (type) => type.wireName == value,
    orElse: () => throw FormatException('Unbekannte Sportart: $value.'),
  );
}

/// Zielbereich in bpm: 40 <= [lowBpm] < [highBpm] <= 230.
class CardioTargetZone {
  const CardioTargetZone({required this.lowBpm, required this.highBpm});

  static const minBpm = 40;
  static const maxBpm = 230;

  factory CardioTargetZone.fromJson(Map<String, dynamic> json) =>
      CardioTargetZone(
        lowBpm: (json['lowBpm'] as num).toInt(),
        highBpm: (json['highBpm'] as num).toInt(),
      );

  final int lowBpm;
  final int highBpm;

  bool get isValid => lowBpm >= minBpm && lowBpm < highBpm && highBpm <= maxBpm;

  bool contains(int bpm) => bpm >= lowBpm && bpm <= highBpm;

  Map<String, Object?> toJson() => {'lowBpm': lowBpm, 'highBpm': highBpm};

  @override
  bool operator ==(Object other) =>
      other is CardioTargetZone &&
      other.lowBpm == lowBpm &&
      other.highBpm == highBpm;

  @override
  int get hashCode => Object.hash(lowBpm, highBpm);

  @override
  String toString() => '$lowBpm–$highBpm';
}

/// Beendete Cardio-Einheit. Pulsreihe und RR-Intervalle sind Rohdaten; alle
/// Kennzahlen berechnet `CardioAnalysis` daraus.
class CardioSession {
  CardioSession({
    required this.sessionId,
    this.activityType = CardioActivityType.indoorCycling,
    required this.startedAtUtc,
    required this.endedAtUtc,
    this.targetZone,
    this.sampleIntervalSeconds = defaultSampleIntervalSeconds,
    required List<int> heartRateBpm,
    required List<int> rrIntervalsMs,
    this.sensorName,
    this.distanceKm,
    this.averagePowerWatts,
    this.energyKcal,
    this.notes,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    this.deletedAtUtc,
  }) : heartRateBpm = List.unmodifiable(heartRateBpm),
       rrIntervalsMs = List.unmodifiable(rrIntervalsMs);

  static const defaultSampleIntervalSeconds = 5;

  factory CardioSession.fromJson(Map<String, dynamic> json) => CardioSession(
    sessionId: json['sessionId'] as String,
    activityType: CardioActivityType.fromWireName(json['activityType']),
    startedAtUtc: DateTime.parse(json['startedAtUtc'] as String).toUtc(),
    endedAtUtc: DateTime.parse(json['endedAtUtc'] as String).toUtc(),
    targetZone: json['targetZone'] is Map<String, dynamic>
        ? CardioTargetZone.fromJson(json['targetZone'] as Map<String, dynamic>)
        : null,
    sampleIntervalSeconds: (json['sampleIntervalSeconds'] as num).toInt(),
    heartRateBpm: [
      for (final value in json['heartRateBpm'] as List) (value as num).toInt(),
    ],
    rrIntervalsMs: [
      for (final value in (json['rrIntervalsMs'] as List?) ?? const [])
        (value as num).toInt(),
    ],
    sensorName: json['sensorName'] as String?,
    distanceKm: (json['distanceKm'] as num?)?.toDouble(),
    averagePowerWatts: (json['averagePowerWatts'] as num?)?.toDouble(),
    energyKcal: (json['energyKcal'] as num?)?.toDouble(),
    notes: json['notes'] as String?,
    createdAtUtc: DateTime.parse(json['createdAtUtc'] as String).toUtc(),
    updatedAtUtc: DateTime.parse(json['updatedAtUtc'] as String).toUtc(),
    deletedAtUtc: json['deletedAtUtc'] == null
        ? null
        : DateTime.parse(json['deletedAtUtc'] as String).toUtc(),
  );

  final String sessionId;
  final CardioActivityType activityType;
  final DateTime startedAtUtc;
  final DateTime endedAtUtc;
  final CardioTargetZone? targetZone;
  final int sampleIntervalSeconds;

  /// Ein Wert je Intervall ab Start; 0 = kein Signal.
  final List<int> heartRateBpm;
  final List<int> rrIntervalsMs;
  final String? sensorName;
  final double? distanceKm;
  final double? averagePowerWatts;
  final double? energyKcal;
  final String? notes;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;

  /// Nur lokal: gelöscht, bis der Server die Löschung bestätigt.
  final DateTime? deletedAtUtc;

  Duration get duration => endedAtUtc.difference(startedAtUtc);

  /// Nullable Felder werden über Funktionen gesetzt, damit `null` übergeben
  /// werden kann (`notes: () => null`).
  CardioSession copyWith({
    DateTime? startedAtUtc,
    DateTime? endedAtUtc,
    CardioTargetZone? Function()? targetZone,
    List<int>? heartRateBpm,
    List<int>? rrIntervalsMs,
    String? Function()? sensorName,
    double? Function()? distanceKm,
    double? Function()? averagePowerWatts,
    double? Function()? energyKcal,
    String? Function()? notes,
    DateTime? updatedAtUtc,
    DateTime? Function()? deletedAtUtc,
  }) => CardioSession(
    sessionId: sessionId,
    activityType: activityType,
    startedAtUtc: startedAtUtc ?? this.startedAtUtc,
    endedAtUtc: endedAtUtc ?? this.endedAtUtc,
    targetZone: targetZone == null ? this.targetZone : targetZone(),
    sampleIntervalSeconds: sampleIntervalSeconds,
    heartRateBpm: heartRateBpm ?? this.heartRateBpm,
    rrIntervalsMs: rrIntervalsMs ?? this.rrIntervalsMs,
    sensorName: sensorName == null ? this.sensorName : sensorName(),
    distanceKm: distanceKm == null ? this.distanceKm : distanceKm(),
    averagePowerWatts: averagePowerWatts == null
        ? this.averagePowerWatts
        : averagePowerWatts(),
    energyKcal: energyKcal == null ? this.energyKcal : energyKcal(),
    notes: notes == null ? this.notes : notes(),
    createdAtUtc: createdAtUtc,
    updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
    deletedAtUtc: deletedAtUtc == null ? this.deletedAtUtc : deletedAtUtc(),
  );

  /// Arbeitskopie im Sync-Format (camelCase); fehlende optionale Werte entfallen.
  Map<String, Object?> toJson() => {
    'sessionId': sessionId,
    'activityType': activityType.wireName,
    'startedAtUtc': startedAtUtc.toUtc().toIso8601String(),
    'endedAtUtc': endedAtUtc.toUtc().toIso8601String(),
    'targetZone': targetZone?.toJson(),
    'sampleIntervalSeconds': sampleIntervalSeconds,
    'heartRateBpm': heartRateBpm,
    'rrIntervalsMs': rrIntervalsMs,
    'sensorName': ?sensorName,
    'distanceKm': ?distanceKm,
    'averagePowerWatts': ?averagePowerWatts,
    'energyKcal': ?energyKcal,
    'notes': ?notes,
    'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
    'updatedAtUtc': updatedAtUtc.toUtc().toIso8601String(),
    if (deletedAtUtc != null)
      'deletedAtUtc': deletedAtUtc!.toUtc().toIso8601String(),
  };
}
