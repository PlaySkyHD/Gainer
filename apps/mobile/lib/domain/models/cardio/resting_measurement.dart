import 'cardio_analysis.dart';
import 'cardio_draft.dart';

/// Auswertung einer geführten Ruhemessung (Ruhepuls und HRV).
class RestingMeasurement {
  const RestingMeasurement({
    required this.restingHeartRateBpm,
    required this.rmssdMs,
    required this.validRrCount,
    required this.rrCount,
    required this.artifactRatio,
  });

  /// Obergrenze des Artefaktanteils, ab der die App nachfragt.
  static const maxArtifactRatio = 0.2;

  /// Gültige Bereiche laut Check-in-Vertrag.
  static const minRestingHeartRate = 25;
  static const maxRestingHeartRate = 150;
  static const minHrv = 1;
  static const maxHrv = 300;

  /// Median der Pulswerte; null ohne Signal.
  final int? restingHeartRateBpm;

  /// RMSSD nach `CardioAnalysis.rmssd`, auf 1–300 ms begrenzt; null bei zu
  /// wenigen gültigen Differenzen.
  final int? rmssdMs;

  /// RR-Werte im Wertebereich 300–2000 ms und gesamt.
  final int validRrCount;
  final int rrCount;

  /// Anteil verworfener RR-Differenzen (0 bis 1).
  final double artifactRatio;

  /// Mehr als 20 % verworfen: die Messung war unruhig.
  bool get isNoisy => artifactRatio > maxArtifactRatio;

  /// Ruhepuls und HRV liegen in den Bereichen des Check-ins und können
  /// gespeichert werden.
  bool get isStorable =>
      restingHeartRateBpm != null &&
      restingHeartRateBpm! >= minRestingHeartRate &&
      restingHeartRateBpm! <= maxRestingHeartRate &&
      rmssdMs != null;

  /// Wertet die Messwerte des Messfensters aus.
  factory RestingMeasurement.of(List<CardioSample> samples) {
    final bpm = [
      for (final sample in samples)
        if (sample.bpm >= 25 && sample.bpm <= 250) sample.bpm,
    ];
    final rr = [for (final sample in samples) ...sample.rrIntervalsMs];
    final rmssd = CardioAnalysis.rmssd(rr);
    return RestingMeasurement(
      restingHeartRateBpm: median(bpm),
      rmssdMs: rmssd?.clamp(minHrv, maxHrv),
      validRrCount: rr
          .where(
            (value) =>
                value >= CardioAnalysis.minValidRrMs &&
                value <= CardioAnalysis.maxValidRrMs,
          )
          .length,
      rrCount: rr.length,
      artifactRatio: rrArtifactRatio(rr),
    );
  }

  /// Anteil der RR-Differenzen, die der RMSSD-Filter verwirft (ungültiger
  /// Nachbar oder Sprung über 20 %). 0 bei weniger als zwei Werten.
  static double rrArtifactRatio(List<int> rrIntervalsMs) {
    if (rrIntervalsMs.length < 2) return 0;
    bool valid(int rr) =>
        rr >= CardioAnalysis.minValidRrMs && rr <= CardioAnalysis.maxValidRrMs;
    var rejected = 0;
    for (var i = 1; i < rrIntervalsMs.length; i++) {
      final previous = rrIntervalsMs[i - 1];
      final current = rrIntervalsMs[i];
      if (!valid(previous) ||
          !valid(current) ||
          (current - previous).abs() > previous * CardioAnalysis.maxRrJump) {
        rejected++;
      }
    }
    return rejected / (rrIntervalsMs.length - 1);
  }

  /// Median ganzer Zahlen; bei gerader Anzahl der gerundete Mittelwert der
  /// beiden mittleren Werte. Null bei leerer Liste.
  static int? median(List<int> values) {
    if (values.isEmpty) return null;
    final sorted = [...values]..sort();
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[middle]
        : ((sorted[middle - 1] + sorted[middle]) / 2).round();
  }
}
