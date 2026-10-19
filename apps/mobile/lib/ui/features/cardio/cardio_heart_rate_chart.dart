import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../../domain/models/cardio/cardio_session.dart';
import '../../../domain/models/cardio/cardio_template.dart';
import '../../core/theme.dart';
import '../training/training_format.dart';

/// Pulskurve einer Einheit mit Zielbereich als Band, bei einer Vorlage als
/// Stufen je Phase ([phases] ersetzt dann [zone]). Werte ohne Signal (0)
/// unterbrechen die Linie.
class CardioHeartRateChart extends StatelessWidget {
  const CardioHeartRateChart({
    required this.heartRateBpm,
    required this.sampleIntervalSeconds,
    required this.zone,
    this.phases = const [],
    this.height = 180,
    super.key,
  });

  final List<int> heartRateBpm;
  final int sampleIntervalSeconds;
  final CardioTargetZone? zone;
  final List<CardioPhase> phases;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final total = Duration(
      seconds: math.max(0, heartRateBpm.length - 1) * sampleIntervalSeconds,
    );
    final labelStyle = GainerTypography.caption.copyWith(
      color: colors.secondaryText,
    );
    return Semantics(
      label: 'Pulskurve der Einheit',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: height,
            child: CustomPaint(
              painter: CardioChartPainter(
                heartRateBpm: heartRateBpm,
                zone: zone,
                phases: phases,
                sampleIntervalSeconds: sampleIntervalSeconds,
                lineColor: colors.accent,
                gridColor: colors.separator,
                labelColor: colors.secondaryText,
                labelStyle: labelStyle,
              ),
            ),
          ),
          const SizedBox(height: GainerSpacing.xxs),
          Padding(
            padding: const EdgeInsets.only(left: CardioChartPainter.axisWidth),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('0:00', style: labelStyle),
                Text(formatElapsed(total), style: labelStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Wertebereich der y-Achse in vollen 10 bpm, inklusive Zielbereich.
({int low, int high}) cardioChartRange(
  List<int> heartRateBpm,
  CardioTargetZone? zone, [
  List<CardioPhase> phases = const [],
]) {
  final values = [
    for (final bpm in heartRateBpm)
      if (bpm > 0) bpm,
    ?zone?.lowBpm,
    ?zone?.highBpm,
    for (final phase in phases) ...[?phase.lowBpm, ?phase.highBpm],
  ];
  if (values.isEmpty) return (low: 60, high: 180);
  var low = (values.reduce(math.min) - 5) ~/ 10 * 10;
  var high = ((values.reduce(math.max) + 5) / 10).ceil() * 10;
  if (high - low < 20) high = low + 20;
  low = math.max(0, low);
  return (low: low, high: high);
}

class CardioChartPainter extends CustomPainter {
  const CardioChartPainter({
    required this.heartRateBpm,
    required this.zone,
    this.phases = const [],
    this.sampleIntervalSeconds = 5,
    required this.lineColor,
    required this.gridColor,
    required this.labelColor,
    required this.labelStyle,
  });

  /// Breite der y-Achsenbeschriftung links.
  static const axisWidth = 34.0;

  final List<int> heartRateBpm;
  final CardioTargetZone? zone;
  final List<CardioPhase> phases;
  final int sampleIntervalSeconds;
  final Color lineColor;
  final Color gridColor;
  final Color labelColor;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    const top = 6.0;
    final plot = Rect.fromLTRB(axisWidth, top, size.width, size.height - top);
    final range = cardioChartRange(heartRateBpm, zone, phases);
    double yOf(num bpm) =>
        plot.bottom -
        plot.height * (bpm - range.low) / (range.high - range.low);

    final bandPaint = Paint()..color = lineColor.withValues(alpha: .16);
    if (phases.isNotEmpty) {
      // Stufen: je Phase ein Band über deren Zeitraum, am Ende der Kurve
      // abgeschnitten.
      final totalSeconds = math.max(
        1,
        (heartRateBpm.length - 1) * sampleIntervalSeconds,
      );
      for (final phase in phases) {
        final phaseZone = phase.zone;
        if (phaseZone == null || phase.startOffsetSeconds >= totalSeconds) {
          continue;
        }
        final end = math.min(phase.endOffsetSeconds, totalSeconds);
        canvas.drawRect(
          Rect.fromLTRB(
            plot.left + plot.width * phase.startOffsetSeconds / totalSeconds,
            yOf(phaseZone.highBpm),
            plot.left + plot.width * end / totalSeconds,
            yOf(phaseZone.lowBpm),
          ),
          bandPaint,
        );
      }
    }
    final band = phases.isEmpty ? zone : null;
    if (band != null) {
      canvas.drawRect(
        Rect.fromLTRB(
          plot.left,
          yOf(band.highBpm),
          plot.right,
          yOf(band.lowBpm),
        ),
        bandPaint,
      );
    }

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;
    final middle = (range.low + range.high) ~/ 2;
    for (final value in {range.low, middle, range.high}) {
      final y = yOf(value);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      final label = TextPainter(
        text: TextSpan(text: '$value', style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
        canvas,
        Offset(axisWidth - label.width - 6, y - label.height / 2),
      );
    }

    final count = heartRateBpm.length;
    if (count == 0) return;
    double xOf(int index) => count == 1
        ? plot.center.dx
        : plot.left + plot.width * index / (count - 1);
    final line = Paint()
      ..color = lineColor
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final dot = Paint()..color = lineColor;
    canvas.save();
    canvas.clipRect(plot.inflate(4));
    Path? path;
    var segmentLength = 0;
    void flush(int lastIndex) {
      if (path != null && segmentLength == 1) {
        canvas.drawCircle(
          Offset(xOf(lastIndex), yOf(heartRateBpm[lastIndex])),
          2.5,
          dot,
        );
      } else if (path != null) {
        canvas.drawPath(path!, line);
      }
      path = null;
      segmentLength = 0;
    }

    for (var i = 0; i < count; i++) {
      final bpm = heartRateBpm[i];
      if (bpm <= 0) {
        flush(i - 1);
        continue;
      }
      final point = Offset(xOf(i), yOf(bpm));
      if (path == null) {
        path = Path()..moveTo(point.dx, point.dy);
      } else {
        path!.lineTo(point.dx, point.dy);
      }
      segmentLength++;
    }
    flush(count - 1);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CardioChartPainter old) =>
      old.heartRateBpm != heartRateBpm ||
      old.zone != zone ||
      old.phases != phases ||
      old.lineColor != lineColor ||
      old.gridColor != gridColor ||
      old.labelColor != labelColor;
}
