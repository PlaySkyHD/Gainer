import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../../domain/models/training/training_heatmap.dart';
import '../../../domain/models/training/training_schedule.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';

const _monthLabels = [
  'Jan',
  'Feb',
  'Mär',
  'Apr',
  'Mai',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Okt',
  'Nov',
  'Dez',
];

/// Kleinster Abstand von Spalte zu Spalte. Passt die Heatmap damit nicht in
/// die Breite, scrollt sie waagerecht und beginnt rechts bei heute.
const _minStep = 6.0;

/// Größter Abstand, damit die Kästchen auf breiten Geräten klein bleiben.
const _maxStep = 16.0;

/// „142 Trainingstage in den letzten 12 Monaten“.
String trainingHeatmapSummary(int trainingDays) =>
    '$trainingDays ${trainingDays == 1 ? 'Trainingstag' : 'Trainingstage'} '
    'in den letzten 12 Monaten';

/// Farbe einer Stufe: 0 neutral, 1–4 zunehmend Akzent.
Color trainingHeatmapColor(GainerColors colors, int level) {
  if (level <= 0) return colors.elevatedSurface;
  const strength = [0.3, 0.55, 0.8, 1.0];
  return Color.lerp(
    colors.elevatedSurface,
    colors.accent,
    strength[math.min(level, 4) - 1],
  )!;
}

/// Karte mit der Heatmap der Trainingstage der letzten 12 Monate. Tippen auf
/// einen Tag mit Training ruft [onOpenDay] auf.
class TrainingHeatmapCard extends StatelessWidget {
  const TrainingHeatmapCard({required this.heatmap, this.onOpenDay, super.key});

  final TrainingHeatmap heatmap;
  final ValueChanged<LocalDay>? onOpenDay;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final summary = trainingHeatmapSummary(heatmap.trainingDays);
    return Semantics(
      container: true,
      label: summary,
      child: ExcludeSemantics(
        child: GainerCard(
          key: const ValueKey('training-heatmap'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                summary,
                style: GainerTypography.label.copyWith(
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: GainerSpacing.s),
              _HeatmapGrid(heatmap: heatmap, onOpenDay: onOpenDay),
              const SizedBox(height: GainerSpacing.xs),
              const _Legend(),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeatmapGrid extends StatelessWidget {
  const _HeatmapGrid({required this.heatmap, required this.onOpenDay});

  final TrainingHeatmap heatmap;
  final ValueChanged<LocalDay>? onOpenDay;

  void _tap(Offset position, double step) {
    final day = heatmap.dayAt(
      (position.dx / step).floor(),
      (position.dy / step).floor(),
    );
    if (day != null && day.hasTraining) onOpenDay?.call(day.date);
  }

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final scaler = MediaQuery.textScalerOf(context);
    final labelStyle = GainerTypography.caption.copyWith(
      color: colors.secondaryText,
    );
    final measure = TextPainter(
      text: TextSpan(text: 'Mär', style: labelStyle),
      textScaler: scaler,
      textDirection: TextDirection.ltr,
    )..layout();
    final labelHeight = measure.height;
    measure.dispose();
    final weeks = heatmap.weeks.length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final step = (available / weeks).clamp(_minStep, _maxStep);
        final width = step * weeks;
        final content = SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomPaint(
                size: Size(width, labelHeight),
                painter: _MonthLabelPainter(
                  heatmap: heatmap,
                  step: step,
                  style: labelStyle,
                  scaler: scaler,
                ),
              ),
              const SizedBox(height: GainerSpacing.xxs),
              GestureDetector(
                key: const ValueKey('training-heatmap-grid'),
                behavior: HitTestBehavior.opaque,
                onTapUp: onOpenDay == null
                    ? null
                    : (details) => _tap(details.localPosition, step),
                child: CustomPaint(
                  size: Size(width, step * 7),
                  painter: _CellPainter(
                    heatmap: heatmap,
                    step: step,
                    colors: colors,
                  ),
                ),
              ),
            ],
          ),
        );
        if (width <= available) {
          return Align(alignment: Alignment.centerLeft, child: content);
        }
        return SingleChildScrollView(
          key: const ValueKey('training-heatmap-scroll'),
          scrollDirection: Axis.horizontal,
          reverse: true,
          child: content,
        );
      },
    );
  }
}

class _MonthLabelPainter extends CustomPainter {
  _MonthLabelPainter({
    required this.heatmap,
    required this.step,
    required this.style,
    required this.scaler,
  });

  final TrainingHeatmap heatmap;
  final double step;
  final TextStyle style;
  final TextScaler scaler;

  @override
  void paint(Canvas canvas, Size size) {
    var free = 0.0;
    for (var week = 0; week < heatmap.weeks.length; week++) {
      final first = heatmap.weeks[week].firstWhere(
        (day) => day != null && day.date.day == 1,
        orElse: () => null,
      );
      if (first == null) continue;
      final x = week * step;
      final label = TextPainter(
        text: TextSpan(text: _monthLabels[first.date.month - 1], style: style),
        textScaler: scaler,
        textDirection: TextDirection.ltr,
      )..layout();
      // Bei großer Schrift entfallen Beschriftungen, die sich überlappen.
      if (x >= free && x + label.width <= size.width) {
        label.paint(canvas, Offset(x, 0));
        free = x + label.width + GainerSpacing.xxs;
      }
      label.dispose();
    }
  }

  @override
  bool shouldRepaint(_MonthLabelPainter oldDelegate) =>
      !identical(oldDelegate.heatmap, heatmap) ||
      oldDelegate.step != step ||
      oldDelegate.style != style ||
      oldDelegate.scaler != scaler;
}

class _CellPainter extends CustomPainter {
  _CellPainter({
    required this.heatmap,
    required this.step,
    required this.colors,
  });

  final TrainingHeatmap heatmap;
  final double step;
  final GainerColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final gap = math.max(1.0, step * 0.2);
    final cell = step - gap;
    final radius = Radius.circular(cell * 0.25);
    final paint = Paint();
    for (var week = 0; week < heatmap.weeks.length; week++) {
      for (var weekday = 0; weekday < 7; weekday++) {
        final day = heatmap.weeks[week][weekday];
        if (day == null) continue;
        paint.color = trainingHeatmapColor(colors, day.level);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(week * step, weekday * step, cell, cell),
            radius,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CellPainter oldDelegate) =>
      !identical(oldDelegate.heatmap, heatmap) ||
      oldDelegate.step != step ||
      !identical(oldDelegate.colors, colors);
}

/// „Weniger ▢▢▢▢▢ Mehr“, rechtsbündig.
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final style = GainerTypography.caption.copyWith(
      color: colors.secondaryText,
    );
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: GainerSpacing.xxs,
      runSpacing: GainerSpacing.xxs,
      children: [
        Text('Weniger', style: style),
        for (var level = 0; level <= 4; level++)
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: trainingHeatmapColor(colors, level),
              borderRadius: BorderRadius.circular(2.5),
            ),
          ),
        Text('Mehr', style: style),
      ],
    );
  }
}
