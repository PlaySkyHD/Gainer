import 'cardio_session.dart';
import 'cardio_template.dart';

/// Ein Messwert des Pulsgurts (Domänentyp, unabhängig von der Plattform).
class CardioSample {
  const CardioSample({
    required this.sequence,
    required this.atUtc,
    required this.bpm,
    this.rrIntervalsMs = const [],
  });

  final int sequence;
  final DateTime atUtc;

  /// 0 = kein gültiger Messwert.
  final int bpm;
  final List<int> rrIntervalsMs;
}

/// Laufende Cardio-Einheit, nur lokal als Sync-Metadatum gesichert. Enthält die
/// schon zu Intervall-Werten verdichteten Pulswerte, die RR-Werte, die letzte
/// gelesene Sequenz und den Zwischenstand des noch offenen Intervalls.
class CardioDraft {
  CardioDraft({
    required this.sessionId,
    this.activityType = CardioActivityType.indoorCycling,
    required this.startedAtUtc,
    this.targetZone,
    required this.warmupSeconds,
    this.sensorId,
    this.sensorName,
    this.templateName,
    List<CardioPhase> phases = const [],
    this.sampleIntervalSeconds = CardioSession.defaultSampleIntervalSeconds,
    List<int> buckets = const [],
    List<int> rrIntervalsMs = const [],
    this.lastSequence = 0,
    this.openSum = 0,
    this.openCount = 0,
  }) : buckets = List.unmodifiable(buckets),
       rrIntervalsMs = List.unmodifiable(rrIntervalsMs),
       phases = List.unmodifiable(phases);

  factory CardioDraft.fromJson(Map<String, dynamic> json) => CardioDraft(
    sessionId: json['sessionId'] as String,
    activityType: CardioActivityType.fromWireName(json['activityType']),
    startedAtUtc: DateTime.parse(json['startedAtUtc'] as String).toUtc(),
    targetZone: json['targetZone'] is Map<String, dynamic>
        ? CardioTargetZone.fromJson(json['targetZone'] as Map<String, dynamic>)
        : null,
    warmupSeconds: (json['warmupSeconds'] as num).toInt(),
    sensorId: json['sensorId'] as String?,
    sensorName: json['sensorName'] as String?,
    templateName: json['templateName'] as String?,
    phases: [
      for (final phase in (json['phases'] as List?) ?? const [])
        CardioPhase.fromJson(phase as Map<String, dynamic>),
    ],
    sampleIntervalSeconds: (json['sampleIntervalSeconds'] as num).toInt(),
    buckets: [for (final v in json['buckets'] as List) (v as num).toInt()],
    rrIntervalsMs: [
      for (final v in json['rrIntervalsMs'] as List) (v as num).toInt(),
    ],
    lastSequence: (json['lastSequence'] as num).toInt(),
    openSum: (json['openSum'] as num).toInt(),
    openCount: (json['openCount'] as num).toInt(),
  );

  final String sessionId;
  final CardioActivityType activityType;
  final DateTime startedAtUtc;
  final CardioTargetZone? targetZone;
  final int warmupSeconds;
  final String? sensorId;
  final String? sensorName;

  /// Vorlage der Einheit und deren aufgelöste Phasen (leer: freie Einheit).
  final String? templateName;
  final List<CardioPhase> phases;
  final int sampleIntervalSeconds;

  /// Abgeschlossene Intervalle ab Start (0 = kein Signal).
  final List<int> buckets;
  final List<int> rrIntervalsMs;

  /// Höchste verarbeitete Sequenz der nativen Überwachung.
  final int lastSequence;

  /// Summe und Anzahl der Messwerte im offenen Intervall `buckets.length`.
  final int openSum;
  final int openCount;

  CardioDraft copyWith({
    CardioTargetZone? Function()? targetZone,
    String? Function()? sensorId,
    String? Function()? sensorName,
    List<int>? buckets,
    List<int>? rrIntervalsMs,
    int? lastSequence,
    int? openSum,
    int? openCount,
  }) => CardioDraft(
    sessionId: sessionId,
    activityType: activityType,
    startedAtUtc: startedAtUtc,
    targetZone: targetZone == null ? this.targetZone : targetZone(),
    warmupSeconds: warmupSeconds,
    sensorId: sensorId == null ? this.sensorId : sensorId(),
    sensorName: sensorName == null ? this.sensorName : sensorName(),
    templateName: templateName,
    phases: phases,
    sampleIntervalSeconds: sampleIntervalSeconds,
    buckets: buckets ?? this.buckets,
    rrIntervalsMs: rrIntervalsMs ?? this.rrIntervalsMs,
    lastSequence: lastSequence ?? this.lastSequence,
    openSum: openSum ?? this.openSum,
    openCount: openCount ?? this.openCount,
  );

  Map<String, Object?> toJson() => {
    'sessionId': sessionId,
    'activityType': activityType.wireName,
    'startedAtUtc': startedAtUtc.toUtc().toIso8601String(),
    'targetZone': targetZone?.toJson(),
    'warmupSeconds': warmupSeconds,
    'sensorId': sensorId,
    'sensorName': sensorName,
    'templateName': templateName,
    if (phases.isNotEmpty) 'phases': [for (final p in phases) p.toJson()],
    'sampleIntervalSeconds': sampleIntervalSeconds,
    'buckets': buckets,
    'rrIntervalsMs': rrIntervalsMs,
    'lastSequence': lastSequence,
    'openSum': openSum,
    'openCount': openCount,
  };
}

/// Reine Verdichtung von Messwerten zu Intervall-Werten relativ zum Start.
/// Ein Intervall wird erst abgeschlossen, wenn die Zeit darüber hinaus ist;
/// Intervalle ohne Messwert ergeben 0.
abstract final class CardioBucketer {
  /// Nimmt [samples] (aufsteigend nach Sequenz) und den Zeitpunkt [nowUtc] in
  /// den Entwurf auf. Bereits verarbeitete Sequenzen und Messwerte vor dem
  /// Start werden ignoriert, Messwerte für schon abgeschlossene Intervalle
  /// ebenso (RR-Werte bleiben erhalten).
  static CardioDraft fold(
    CardioDraft draft,
    List<CardioSample> samples, {
    required DateTime nowUtc,
  }) {
    final intervalMs = draft.sampleIntervalSeconds * 1000;
    final buckets = [...draft.buckets];
    final rr = [...draft.rrIntervalsMs];
    var sum = draft.openSum;
    var count = draft.openCount;
    var lastSequence = draft.lastSequence;

    void closeThrough(int index) {
      // Schließt alle Intervalle mit Index < [index].
      while (buckets.length < index) {
        buckets.add(_mean(sum, count));
        sum = 0;
        count = 0;
      }
    }

    for (final sample in samples) {
      if (sample.sequence <= lastSequence) continue;
      lastSequence = sample.sequence;
      final offset = sample.atUtc.difference(draft.startedAtUtc);
      if (offset.isNegative) continue;
      rr.addAll(sample.rrIntervalsMs);
      final index = offset.inMilliseconds ~/ intervalMs;
      closeThrough(index);
      if (index == buckets.length && sample.bpm > 0) {
        sum += sample.bpm;
        count++;
      }
    }
    final nowOffset = nowUtc.difference(draft.startedAtUtc);
    if (!nowOffset.isNegative) {
      closeThrough(nowOffset.inMilliseconds ~/ intervalMs);
    }
    return draft.copyWith(
      buckets: buckets,
      rrIntervalsMs: rr,
      lastSequence: lastSequence,
      openSum: sum,
      openCount: count,
    );
  }

  /// Pulsreihe für die fertige Einheit: alle Intervalle vor [endedAtUtc] und das
  /// angebrochene Intervall, falls es Messwerte enthält.
  static List<int> finish(CardioDraft draft, DateTime endedAtUtc) {
    final closed = fold(draft, const [], nowUtc: endedAtUtc);
    return [
      ...closed.buckets,
      if (closed.openCount > 0) _mean(closed.openSum, closed.openCount),
    ];
  }

  /// Mittel des offenen Intervalls für die Live-Auswertung; null ohne Werte.
  static int? openBucketMean(CardioDraft draft) =>
      draft.openCount == 0 ? null : (draft.openSum / draft.openCount).round();
}

/// Mittel eines Intervalls; Werte außerhalb 25–250 gelten als kein Signal (0),
/// weil der Server sie ablehnt.
int _mean(int sum, int count) {
  if (count == 0) return 0;
  final mean = (sum / count).round();
  return mean >= 25 && mean <= 250 ? mean : 0;
}
