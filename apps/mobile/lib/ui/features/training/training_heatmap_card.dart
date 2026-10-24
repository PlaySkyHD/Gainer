import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../../domain/models/training/training_heatmap.dart';
import '../../../domain/models/training/training_schedule.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'training_format.dart';

/// Kleinster Abstand von Spalte zu Spalte. Passt die Heatmap damit nicht in
/// die Breite, scrollt sie waagerecht und beginnt rechts bei heute.
const _minStep = 6.0;

/// Größter Abstand, damit die Kästchen auf breiten Geräten klein bleiben.
const _maxStep = 16.0;

/// „142 Trainingstage in den letzten 12 Monaten“.
String trainingHeatmapSummary(int trainingDays) =>
    '$trainingDays ${trainingDays == 1 ? 'Trainingstag' : 'Trainingstage'} '
    'in den letzten 12 Monaten';

/// Ein gewählter Tag: „Mo, 12. Okt. · 45 min“ oder „Di, 13. Okt. · kein
/// Training“.
String trainingHeatmapDayText(TrainingHeatmapDay day) {
  final date = day.date.toDateTime();
  final amount = day.hasTraining ? '${day.minutes} min' : 'kein Training';
  return '${formatWeekdayShort(date)}, ${formatShortDate(date)} · $amount';
}

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

/// Karte mit der Heatmap der Trainingstage der letzten 12 Monate. Tippen
/// wählt den nächstgelegenen Tag und zeigt ihn unter dem Raster; erst die
/// Schaltfläche „Im Kalender öffnen“ ruft [onOpenDay] auf. Für VoiceOver ist
/// das Raster einstellbar: Wischen nach oben oder unten springt zum nächsten
/// oder vorigen Trainingstag.
class TrainingHeatmapCard extends StatefulWidget {
  const TrainingHeatmapCard({required this.heatmap, this.onOpenDay, super.key});

  final TrainingHeatmap heatmap;

  /// Öffnet einen Tag im Kalender; ohne Wert entfällt die Schaltfläche.
  final ValueChanged<LocalDay>? onOpenDay;

  @override
  State<TrainingHeatmapCard> createState() => _TrainingHeatmapCardState();
}

class _TrainingHeatmapCardState extends State<TrainingHeatmapCard> {
  LocalDay? _selected;
  _MonthLabels? _labels;

  @override
  void didUpdateWidget(TrainingHeatmapCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Nach dem Neuladen bleibt die Auswahl, solange der Tag im Zeitraum liegt.
    if (_selected case final day? when !widget.heatmap.contains(day)) {
      _selected = null;
    }
  }

  @override
  void dispose() {
    _labels?.dispose();
    super.dispose();
  }

  void _select(LocalDay day) => setState(() => _selected = day);

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final heatmap = widget.heatmap;
    final summary = trainingHeatmapSummary(heatmap.trainingDays);
    final selected = switch (_selected) {
      final day? => heatmap.dayOn(day),
      null => null,
    };
    final next = heatmap.nextTrainingDay(selected?.date);
    final previous = heatmap.previousTrainingDay(selected?.date);
    final labelStyle = GainerTypography.caption.copyWith(
      color: colors.secondaryText,
    );
    final labels = _labels = _MonthLabels.reuse(
      _labels,
      heatmap: heatmap,
      style: labelStyle,
      scaler: MediaQuery.textScalerOf(context),
    );
    final onOpenDay = widget.onOpenDay;
    return GainerCard(
      key: const ValueKey('training-heatmap'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            key: const ValueKey('training-heatmap-semantics'),
            container: true,
            label: summary,
            value: selected == null
                ? 'Kein Tag gewählt'
                : trainingHeatmapDayText(selected),
            increasedValue: next == null ? null : trainingHeatmapDayText(next),
            decreasedValue: previous == null
                ? null
                : trainingHeatmapDayText(previous),
            onIncrease: next == null ? null : () => _select(next.date),
            onDecrease: previous == null ? null : () => _select(previous.date),
            child: ExcludeSemantics(
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
                  _HeatmapGrid(
                    heatmap: heatmap,
                    labels: labels,
                    selected: selected?.date,
                    onSelect: _select,
                  ),
                  const SizedBox(height: GainerSpacing.xs),
                  const _Legend(),
                ],
              ),
            ),
          ),
          if (selected != null) ...[
            const SizedBox(height: GainerSpacing.s),
            Text(
              trainingHeatmapDayText(selected),
              key: const ValueKey('training-heatmap-selection'),
              style: GainerTypography.body.copyWith(color: colors.primaryText),
            ),
            if (onOpenDay != null) ...[
              const SizedBox(height: GainerSpacing.xs),
              GainerPillButton(
                key: const ValueKey('training-heatmap-open'),
                label: 'Im Kalender öffnen',
                icon: CupertinoIcons.calendar,
                variant: GainerPillVariant.tonal,
                expand: true,
                onPressed: () => onOpenDay(selected.date),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _HeatmapGrid extends StatelessWidget {
  const _HeatmapGrid({
    required this.heatmap,
    required this.labels,
    required this.selected,
    required this.onSelect,
  });

  final TrainingHeatmap heatmap;
  final _MonthLabels labels;
  final LocalDay? selected;
  final ValueChanged<LocalDay> onSelect;

  void _tap(Offset position, double step) {
    final day = heatmap.nearestDay(position.dx / step, position.dy / step);
    if (day != null) onSelect(day.date);
  }

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
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
                size: Size(width, labels.height),
                painter: _MonthLabelPainter(labels: labels, step: step),
              ),
              const SizedBox(height: GainerSpacing.xxs),
              GestureDetector(
                key: const ValueKey('training-heatmap-grid'),
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) => _tap(details.localPosition, step),
                child: CustomPaint(
                  size: Size(width, step * 7),
                  painter: _CellPainter(
                    heatmap: heatmap,
                    step: step,
                    colors: colors,
                    selected: switch (selected) {
                      final day? => heatmap.cellOf(day),
                      null => null,
                    },
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

/// Fertig gesetzte Monatsbeschriftungen. Sie entstehen nur neu, wenn sich
/// Heatmap, Stil oder Textgröße ändern, nicht bei jedem Build oder Paint.
class _MonthLabels {
  _MonthLabels({
    required this.heatmap,
    required this.style,
    required this.scaler,
  }) {
    for (var week = 0; week < heatmap.weeks.length; week++) {
      final first = heatmap.weeks[week].firstWhere(
        (day) => day != null && day.date.day == 1,
        orElse: () => null,
      );
      if (first == null) continue;
      entries.add((
        week: week,
        painter: TextPainter(
          text: TextSpan(
            text: formatMonthLabel(first.date.month),
            style: style,
          ),
          textScaler: scaler,
          textDirection: TextDirection.ltr,
        )..layout(),
      ));
    }
    height = entries.fold<double>(
      0,
      (height, entry) => math.max(height, entry.painter.height),
    );
  }

  /// [previous], wenn es zu den Eingaben passt; sonst neue Beschriftungen.
  static _MonthLabels reuse(
    _MonthLabels? previous, {
    required TrainingHeatmap heatmap,
    required TextStyle style,
    required TextScaler scaler,
  }) {
    if (previous != null &&
        identical(previous.heatmap, heatmap) &&
        previous.style == style &&
        previous.scaler == scaler) {
      return previous;
    }
    previous?.dispose();
    return _MonthLabels(heatmap: heatmap, style: style, scaler: scaler);
  }

  final TrainingHeatmap heatmap;
  final TextStyle style;
  final TextScaler scaler;
  final entries = <({int week, TextPainter painter})>[];
  late final double height;

  void dispose() {
    for (final entry in entries) {
      entry.painter.dispose();
    }
  }
}

class _MonthLabelPainter extends CustomPainter {
  _MonthLabelPainter({required this.labels, required this.step});

  final _MonthLabels labels;
  final double step;

  @override
  void paint(Canvas canvas, Size size) {
    var free = 0.0;
    for (final (:week, :painter) in labels.entries) {
      final x = week * step;
      // Bei großer Schrift entfallen Beschriftungen, die sich überlappen.
      if (x >= free && x + painter.width <= size.width) {
        painter.paint(canvas, Offset(x, 0));
        free = x + painter.width + GainerSpacing.xxs;
      }
    }
  }

  @override
  bool shouldRepaint(_MonthLabelPainter oldDelegate) =>
      !identical(oldDelegate.labels, labels) || oldDelegate.step != step;
}

class _CellPainter extends CustomPainter {
  _CellPainter({
    required this.heatmap,
    required this.step,
    required this.colors,
    required this.selected,
  });

  final TrainingHeatmap heatmap;
  final double step;
  final GainerColors colors;
  final ({int week, int weekday})? selected;

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
    if (selected case (:final week, :final weekday)) {
      // Ring um das gewählte Kästchen, auch bei Tagen ohne Training sichtbar.
      final stroke = math.max(1.5, gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            week * step,
            weekday * step,
            cell,
            cell,
          ).inflate(stroke / 2),
          radius + Radius.circular(stroke / 2),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = colors.primaryText,
      );
    }
  }

  @override
  bool shouldRepaint(_CellPainter oldDelegate) =>
      !identical(oldDelegate.heatmap, heatmap) ||
      oldDelegate.step != step ||
      !identical(oldDelegate.colors, colors) ||
      oldDelegate.selected != selected;
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
