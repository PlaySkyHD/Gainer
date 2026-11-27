import 'package:flutter/cupertino.dart';

import '../../../domain/models/training/training_trends.dart';
import '../../../domain/models/training/workout_input.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import '../cardio/cardio_format.dart' show formatCardioNumber;
import '../cardio/cardio_progress_charts.dart';
import '../progress/today_overview.dart' show formatGermanNumber;
import 'training_format.dart';
import 'training_statistics_view_model.dart' show formatStatisticsWeight;

/// Bereich „Verlauf“: Zeitraum-Umschalter und eine Kachel je Kennzahl mit Wert
/// für den Zeitraum und Linie je Woche oder Monat.
class TrainingTrendTiles extends StatelessWidget {
  const TrainingTrendTiles({
    required this.trends,
    required this.weightUnit,
    required this.onPeriodChanged,
    super.key,
  });

  final TrainingTrends trends;
  final WeightUnit weightUnit;
  final ValueChanged<TrendPeriod> onPeriodChanged;

  /// Ab dieser Textgröße eine Kachel je Zeile.
  static const stackScale = 1.5;

  @override
  Widget build(BuildContext context) {
    final stacked = MediaQuery.textScalerOf(context).scale(1) >= stackScale;
    final tiles = [
      for (final metric in TrendMetric.values)
        _TrendTile(
          fillHeight: !stacked,
          key: ValueKey('trend-${metric.name}'),
          title: _titleOf(metric),
          value: _valueOf(metric),
          points: trends.series[metric]!,
          startLabel: _startLabel(),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const GainerSectionHeader(title: 'Verlauf'),
        const SizedBox(height: GainerSpacing.xs),
        GainerSegmentedControl<TrendPeriod>(
          options: {
            for (final period in TrendPeriod.values) period: period.label,
          },
          value: trends.period,
          onChanged: onPeriodChanged,
        ),
        const SizedBox(height: GainerSpacing.s),
        if (stacked)
          for (final tile in tiles) ...[
            tile,
            const SizedBox(height: GainerSpacing.s),
          ]
        else
          for (var i = 0; i < tiles.length; i += 2) ...[
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: tiles[i]),
                  const SizedBox(width: GainerSpacing.s),
                  Expanded(
                    child: i + 1 < tiles.length
                        ? tiles[i + 1]
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: GainerSpacing.s),
          ],
      ],
    );
  }

  String _startLabel() {
    final start = trends.start;
    if (trends.period.weekly) {
      return formatShortDate(DateTime(start.year, start.month, start.day));
    }
    return '${formatMonthShort(start.month)} ${start.year}';
  }

  static String _titleOf(TrendMetric metric) => switch (metric) {
    TrendMetric.workoutsPerWeek => 'Trainings',
    TrendMetric.averageDuration => 'Trainingsdauer',
    TrendMetric.totalDuration => 'Gesamtzeit',
    TrendMetric.volume => 'Volumen',
    TrendMetric.sets => 'Sätze',
    TrendMetric.repetitions => 'Wiederholungen',
    TrendMetric.repetitionsPerSet => 'Wdh. pro Satz',
    TrendMetric.bodyweight => 'Körpergewicht',
  };

  String _valueOf(TrendMetric metric) {
    final trained = trends.workoutCount > 0;
    if (!trained && metric != TrendMetric.bodyweight) return '–';
    return switch (metric) {
      TrendMetric.workoutsPerWeek =>
        'Ø ${formatCardioNumber(trends.workoutsPerWeek)} pro Woche',
      TrendMetric.averageDuration =>
        'Ø ${formatDurationMinutes(trends.averageDuration!)}',
      TrendMetric.totalDuration => formatTotalDuration(trends.totalDuration),
      TrendMetric.volume => formatStatisticsVolume(trends.volumeKg, weightUnit),
      TrendMetric.sets => formatGermanNumber(trends.setCount.toDouble()),
      TrendMetric.repetitions => formatGermanNumber(
        trends.repetitions.toDouble(),
      ),
      TrendMetric.repetitionsPerSet => switch (trends.repetitionsPerSet) {
        final value? => 'Ø ${formatCardioNumber(value)}',
        null => '–',
      },
      TrendMetric.bodyweight => formatStatisticsWeight(
        trends.latestBodyweightKg,
        weightUnit,
      ),
    };
  }
}

/// Gesamtdauer auf ganze Minuten: „45 min“, ab einer Stunde „12 h 5 min“.
String formatTotalDuration(Duration duration) {
  final minutes = (duration.inSeconds + 30) ~/ 60;
  if (minutes < 60) return '$minutes min';
  final rest = minutes % 60;
  final hours = formatGermanNumber((minutes ~/ 60).toDouble());
  return rest == 0 ? '$hours h' : '$hours h $rest min';
}

class _TrendTile extends StatelessWidget {
  const _TrendTile({
    required this.title,
    required this.value,
    required this.points,
    required this.startLabel,
    required this.fillHeight,
    super.key,
  });

  /// Nebeneinander gleich hoch: Linie und Beschriftung unten bündig.
  final bool fillHeight;
  final String title;
  final String value;

  /// Ein Wert je Abschnitt, `null` ohne Daten.
  final List<double?> points;
  final String startLabel;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final labelStyle = GainerTypography.caption.copyWith(
      color: colors.secondaryText,
    );
    final last = points.length - 1;
    final chartPoints = [
      for (var i = 0; i < points.length; i++)
        if (points[i] case final y?) ChartPoint(last == 0 ? .5 : i / last, y),
    ];
    return Semantics(
      container: true,
      label: '$title: $value',
      excludeSemantics: true,
      child: GainerCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: labelStyle),
            const SizedBox(height: GainerSpacing.xxs),
            Text(
              value,
              style: GainerTypography.cardTitle.copyWith(
                color: colors.primaryText,
              ),
            ),
            if (fillHeight) const Spacer(),
            const SizedBox(height: GainerSpacing.xs),
            CardioLineChart(
              height: 44,
              series: [ChartSeries(points: chartPoints, color: colors.accent)],
              gridColor: const Color(0x00000000),
              labelStyle: labelStyle,
            ),
            const SizedBox(height: GainerSpacing.xxs),
            Row(
              children: [
                Expanded(child: Text(startLabel, style: labelStyle)),
                Text('Heute', style: labelStyle),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
