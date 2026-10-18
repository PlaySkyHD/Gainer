import 'dart:math' as math;

import 'cardio_session.dart';

/// Kennzahlen einer Einheit, deterministisch aus Pulsreihe und RR-Intervallen.
/// Werte ohne Signal (0) zählen bei Ø, Max und Zone nicht mit.
class CardioAnalysis {
  const CardioAnalysis({
    required this.activeDuration,
    required this.averageBpm,
    required this.maxBpm,
    required this.timeInZone,
    required this.zoneShare,
    required this.rmssdMs,
  });

  /// RR-Werte außerhalb dieses Bereichs sind Artefakte.
  static const minValidRrMs = 300;
  static const maxValidRrMs = 2000;
  static const maxRrJump = 0.2;
  static const minRmssdDifferences = 30;

  /// Analyse einer beendeten Einheit.
  factory CardioAnalysis.of(CardioSession session) => CardioAnalysis.fromSeries(
    heartRateBpm: session.heartRateBpm,
    rrIntervalsMs: session.rrIntervalsMs,
    sampleIntervalSeconds: session.sampleIntervalSeconds,
    zone: session.targetZone,
    activeDuration: session.endedAtUtc.difference(session.startedAtUtc),
  );

  /// Analyse beliebiger Reihen, z. B. der laufenden Einheit.
  factory CardioAnalysis.fromSeries({
    required List<int> heartRateBpm,
    List<int> rrIntervalsMs = const [],
    required int sampleIntervalSeconds,
    required CardioTargetZone? zone,
    required Duration activeDuration,
  }) {
    final withSignal = [
      for (final bpm in heartRateBpm)
        if (bpm > 0) bpm,
    ];
    final inZone = zone == null
        ? 0
        : withSignal.where((bpm) => zone.contains(bpm)).length;
    return CardioAnalysis(
      activeDuration: activeDuration.isNegative
          ? Duration.zero
          : activeDuration,
      averageBpm: withSignal.isEmpty
          ? null
          : withSignal.reduce((a, b) => a + b) / withSignal.length,
      maxBpm: withSignal.isEmpty ? null : withSignal.reduce(math.max),
      timeInZone: Duration(seconds: inZone * sampleIntervalSeconds),
      zoneShare: zone == null || withSignal.isEmpty
          ? null
          : inZone / withSignal.length,
      rmssdMs: rmssd(rrIntervalsMs),
    );
  }

  final Duration activeDuration;

  /// Mittel über alle Werte > 0; null ohne Signal.
  final double? averageBpm;
  final int? maxBpm;

  /// Werte im Zielbereich mal Intervall; ohne Zone [Duration.zero].
  final Duration timeInZone;

  /// Anteil der Werte mit Signal im Zielbereich (0 bis 1); null ohne Zone oder
  /// ohne Signal.
  final double? zoneShare;

  /// HRV in ms, auf ganze ms gerundet; null bei weniger als 30 gültigen
  /// Differenzen.
  final int? rmssdMs;

  /// RMSSD mit Artefaktfilter: Werte außerhalb 300–2000 ms sind ungültig; eine
  /// Differenz zählt nur, wenn beide Nachbarn gültig sind und sich um höchstens
  /// 20 % des Vorgängers unterscheiden.
  static int? rmssd(List<int> rrIntervalsMs) {
    bool valid(int rr) => rr >= minValidRrMs && rr <= maxValidRrMs;
    var count = 0;
    var sum = 0.0;
    for (var i = 1; i < rrIntervalsMs.length; i++) {
      final previous = rrIntervalsMs[i - 1];
      final current = rrIntervalsMs[i];
      if (!valid(previous) || !valid(current)) continue;
      final diff = current - previous;
      if (diff.abs() > previous * maxRrJump) continue;
      sum += diff * diff;
      count++;
    }
    if (count < minRmssdDifferences) return null;
    return math.sqrt(sum / count).round();
  }
}
