import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_session.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_format.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_heart_rate_chart.dart';
import 'package:gainer_mobile/ui/features/training/training_format.dart';

void main() {
  test('Zahlen deutsch formatieren', () {
    expect(formatCardioNumber(14.2), '14,2');
    expect(formatCardioNumber(165.0), '165');
    expect(formatCardioNumber(128.5), '128,5');
    expect(formatCardioNumber(1234.56, maxDecimals: 0), '1.235');
    expect(formatCardioNumber(20000), '20.000');
    expect(formatCardioNumber(0.04), '0');
    expect(formatBpm(132), '132 bpm');
    expect(formatAverageBpm(128.5), '128,5 bpm');
    expect(formatPercent(0.78), '78 %');
    expect(
      formatCardioDuration(const Duration(minutes: 18, seconds: 20)),
      '18:20 min',
    );
    expect(
      formatCardioDuration(const Duration(hours: 1, minutes: 5)),
      '1:05 h',
    );
    expect(formatCardioDuration(const Duration(seconds: 80)), '1:20 min');
    expect(formatCardioDuration(const Duration(seconds: 5)), '0:05 min');
    expect(
      formatCardioDuration(const Duration(hours: 1, minutes: 2, seconds: 40)),
      '1:02 h',
    );
  });

  test('Tagebuchdauer rundet auf die nächste Minute', () {
    expect(formatDurationMinutes(const Duration(seconds: 80)), '1 min');
    expect(formatDurationMinutes(const Duration(seconds: 100)), '2 min');
    expect(formatDurationMinutes(const Duration(seconds: 29)), '0 min');
  });

  test('Diagrammbereich enthält Zielbereich und rundet auf 10 bpm', () {
    expect(
      cardioChartRange(const [
        118,
        0,
        141,
      ], const CardioTargetZone(lowBpm: 120, highBpm: 140)),
      (low: 110, high: 150),
    );
    expect(cardioChartRange(const [0, 0], null), (low: 60, high: 180));
    expect(cardioChartRange(const [100], null), (low: 90, high: 110));
  });
}
