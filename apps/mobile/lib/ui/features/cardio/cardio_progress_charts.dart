import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

/// Ein Punkt einer Linie: [x] von 0 (links) bis 1 (rechts), [y] in Messeinheit.
class ChartPoint {
  const ChartPoint(this.x, this.y);

  final double x;
  final double y;
}

/// Eine Linie mit eigener y-Skala.
class ChartSeries {
  const ChartSeries({required this.points, required this.color});

  final List<ChartPoint> points;
  final Color color;
}

/// Liniendiagramm mit einer oder mehreren Reihen. Jede Reihe nutzt ihre eigene
/// y-Skala (Minimum bis Maximum mit Rand). Nur die erste Reihe beschriftet die
/// y-Achse, wenn [axisFormat] gesetzt ist.
class CardioLineChart extends StatelessWidget {
  const CardioLineChart({
    required this.series,
    required this.gridColor,
    required this.labelStyle,
    this.axisFormat,
    this.height = 140,
    this.semanticLabel,
    super.key,
  });

  final List<ChartSeries> series;
  final Color gridColor;
  final TextStyle labelStyle;
  final String Function(double value)? axisFormat;
  final double height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    excludeSemantics: semanticLabel != null,
    child: SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: CardioLinePainter(
          series: series,
          gridColor: gridColor,
          labelStyle: labelStyle,
          axisFormat: axisFormat,
        ),
      ),
    ),
  );
}

class CardioLinePainter extends CustomPainter {
  const CardioLinePainter({
    required this.series,
    required this.gridColor,
    required this.labelStyle,
    required this.axisFormat,
  });

  /// Breite der y-Achsenbeschriftung links (nur mit [axisFormat]).
  static const axisWidth = 40.0;

  final List<ChartSeries> series;
  final Color gridColor;
  final TextStyle labelStyle;
  final String Function(double value)? axisFormat;

  /// Wertebereich einer Reihe mit etwas Rand; bei konstanten Werten ±1.
  static ({double low, double high}) rangeOf(List<ChartPoint> points) {
    final values = [for (final point in points) point.y];
    if (values.isEmpty) return (low: 0, high: 1);
    final min = values.reduce(math.min);
    final max = values.reduce(math.max);
    final pad = max == min ? math.max(1, max.abs() * .05) : (max - min) * .15;
    return (low: min - pad, high: max + pad);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    const vertical = 8.0;
    final left = axisFormat == null ? 6.0 : axisWidth;
    final plot = Rect.fromLTRB(
      left,
      vertical,
      size.width - 6,
      size.height - vertical,
    );
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;
    for (final fraction in [0.0, 0.5, 1.0]) {
      final y = plot.bottom - plot.height * fraction;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
    }
    for (var index = 0; index < series.length; index++) {
      final line = series[index];
      if (line.points.isEmpty) continue;
      final range = rangeOf(line.points);
      Offset at(ChartPoint point) => Offset(
        plot.left + plot.width * point.x,
        plot.bottom -
            plot.height * (point.y - range.low) / (range.high - range.low),
      );
      if (index == 0 && axisFormat != null) {
        for (final fraction in [0.0, 0.5, 1.0]) {
          final value = range.low + (range.high - range.low) * fraction;
          final label = TextPainter(
            text: TextSpan(text: axisFormat!(value), style: labelStyle),
            textDirection: TextDirection.ltr,
          )..layout();
          label.paint(
            canvas,
            Offset(
              axisWidth - label.width - 6,
              plot.bottom - plot.height * fraction - label.height / 2,
            ),
          );
        }
      }
      final stroke = Paint()
        ..color = line.color
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final path = Path();
      for (var i = 0; i < line.points.length; i++) {
        final offset = at(line.points[i]);
        if (i == 0) {
          path.moveTo(offset.dx, offset.dy);
        } else {
          path.lineTo(offset.dx, offset.dy);
        }
      }
      if (line.points.length > 1) canvas.drawPath(path, stroke);
      final dot = Paint()..color = line.color;
      for (final point in line.points) {
        canvas.drawCircle(at(point), 3, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CardioLinePainter old) =>
      old.series != series ||
      old.gridColor != gridColor ||
      old.axisFormat != axisFormat;
}

/// Balken je Woche mit gestrichelter Ziellinie.
class CardioWeeklyBars extends StatelessWidget {
  const CardioWeeklyBars({
    required this.values,
    required this.goal,
    required this.barColor,
    required this.currentColor,
    required this.goalColor,
    required this.labelStyle,
    this.height = 140,
    this.semanticLabel,
    super.key,
  });

  /// Minuten je Woche, älteste zuerst; der letzte Balken ist die laufende Woche.
  final List<int> values;
  final int goal;
  final Color barColor;
  final Color currentColor;
  final Color goalColor;
  final TextStyle labelStyle;
  final double height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    excludeSemantics: semanticLabel != null,
    child: SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: CardioWeeklyBarsPainter(
          values: values,
          goal: goal,
          barColor: barColor,
          currentColor: currentColor,
          goalColor: goalColor,
          labelStyle: labelStyle,
        ),
      ),
    ),
  );
}

class CardioWeeklyBarsPainter extends CustomPainter {
  const CardioWeeklyBarsPainter({
    required this.values,
    required this.goal,
    required this.barColor,
    required this.currentColor,
    required this.goalColor,
    required this.labelStyle,
  });

  final List<int> values;
  final int goal;
  final Color barColor;
  final Color currentColor;
  final Color goalColor;
  final TextStyle labelStyle;

  /// Obere Grenze der y-Achse: Ziel oder größter Balken, mit Luft darüber.
  static double maxOf(List<int> values, int goal) =>
      math.max(goal, values.isEmpty ? 0 : values.reduce(math.max)) * 1.2;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || values.isEmpty) return;
    const gap = 8.0;
    final top = labelStyle.fontSize ?? 12;
    final plot = Rect.fromLTRB(0, top + 2, size.width, size.height);
    final maxValue = maxOf(values, goal);
    final barWidth = (plot.width - gap * (values.length - 1)) / values.length;
    for (var i = 0; i < values.length; i++) {
      final barHeight = plot.height * values[i] / maxValue;
      final x = plot.left + i * (barWidth + gap);
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(
          x,
          plot.bottom - math.max(barHeight, values[i] > 0 ? 2 : 0),
          barWidth,
          math.max(barHeight, values[i] > 0 ? 2 : 0),
        ),
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      );
      canvas.drawRRect(
        rect,
        Paint()..color = i == values.length - 1 ? currentColor : barColor,
      );
    }
    // Ziellinie gestrichelt mit Beschriftung.
    final y = plot.bottom - plot.height * goal / maxValue;
    final dash = Paint()
      ..color = goalColor
      ..strokeWidth = 1.5;
    for (var x = plot.left; x < plot.right; x += 8) {
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(x + 4, plot.right), y),
        dash,
      );
    }
    final label = TextPainter(
      text: TextSpan(text: 'Ziel $goal min', style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, Offset(plot.left, math.max(0, y - label.height - 2)));
  }

  @override
  bool shouldRepaint(covariant CardioWeeklyBarsPainter old) =>
      old.values != values ||
      old.goal != goal ||
      old.barColor != barColor ||
      old.currentColor != currentColor ||
      old.goalColor != goalColor;
}
