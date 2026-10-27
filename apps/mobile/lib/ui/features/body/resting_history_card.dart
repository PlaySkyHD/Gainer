import 'package:flutter/cupertino.dart';

import '../../../domain/models/body/body_tracking.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import '../cardio/cardio_progress_charts.dart';
import '../training/training_format.dart';

/// Ruhepuls und HRV der letzten 30 Tage als eine kompakte Gruppe im Körper-Tab:
/// Liniendiagramm mit den letzten Werten und, wenn möglich, dem Einstieg in die
/// HRV-Messung.
class RestingHistoryCard extends StatelessWidget {
  const RestingHistoryCard({
    required this.entries,
    required this.today,
    this.onMeasure,
    this.days = 30,
    super.key,
  });

  /// Ruhewerte mit Datum, ältester zuerst (`BodyTrackingSnapshot.restingEntries`).
  final List<RestingEntry> entries;

  /// Heutiges Datum (lokal); das Diagramm reicht [days] Tage zurück.
  final DateTime today;
  final VoidCallback? onMeasure;
  final int days;

  @override
  Widget build(BuildContext context) {
    final from = DateTime(today.year, today.month, today.day - (days - 1));
    final visible = [
      for (final entry in entries)
        if (_date(entry.localDate) case final date?
            when !date.isBefore(from) && !date.isAfter(today))
          (date: date, entry: entry),
    ];
    return GainerGroupedSection(
      header: 'Ruhepuls und HRV',
      footer: visible.isEmpty
          ? 'Eine HRV-Messung mit Pulsgurt zeigt hier deinen Verlauf der '
                'letzten $days Tage.'
          : null,
      children: [
        if (visible.isNotEmpty) _history(context, from, visible),
        if (onMeasure != null)
          GainerListRow(
            key: const ValueKey('body-open-hrv'),
            title: 'HRV-Messung',
            subtitle: 'Mit Pulsgurt, 1 bis 5 Minuten',
            leadingIcon: CupertinoIcons.waveform_path_ecg,
            showChevron: true,
            onTap: onMeasure,
          ),
      ],
    );
  }

  Widget _history(
    BuildContext context,
    DateTime from,
    List<({DateTime date, RestingEntry entry})> visible,
  ) {
    final colors = GainerDesign.colorsOf(context);
    final brightness = MediaQuery.platformBrightnessOf(context);
    final hrvColor = colors.accent;
    final rateColor = GainerStatusColors.info(brightness);
    double x(DateTime date) =>
        date.difference(from).inDays.clamp(0, days - 1) / (days - 1);
    final hrv = [
      for (final item in visible)
        if (item.entry.restingHrvMs != null)
          ChartPoint(x(item.date), item.entry.restingHrvMs!.toDouble()),
    ];
    final rate = [
      for (final item in visible)
        if (item.entry.restingHeartRateBpm != null)
          ChartPoint(x(item.date), item.entry.restingHeartRateBpm!.toDouble()),
    ];
    final latest = visible.last;
    final labelStyle = GainerTypography.caption.copyWith(
      color: colors.secondaryText,
    );
    final latestHrv = latest.entry.restingHrvMs;
    final latestRate = latest.entry.restingHeartRateBpm;
    return Padding(
      key: const ValueKey('resting-history'),
      padding: const EdgeInsets.all(GainerSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: GainerSpacing.m,
            runSpacing: GainerSpacing.xxs,
            children: [
              _Legend(
                color: hrvColor,
                text: latestHrv == null ? 'HRV –' : 'HRV $latestHrv ms',
              ),
              _Legend(
                color: rateColor,
                text: latestRate == null
                    ? 'Ruhepuls –'
                    : 'Ruhepuls $latestRate bpm',
              ),
            ],
          ),
          const SizedBox(height: GainerSpacing.s),
          CardioLineChart(
            height: 120,
            series: [
              if (hrv.isNotEmpty) ChartSeries(points: hrv, color: hrvColor),
              if (rate.isNotEmpty) ChartSeries(points: rate, color: rateColor),
            ],
            gridColor: colors.separator,
            labelStyle: labelStyle,
            semanticLabel:
                'Verlauf von HRV und Ruhepuls der letzten $days Tage',
          ),
          const SizedBox(height: GainerSpacing.xxs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text(formatShortDate(from), style: labelStyle)),
              Flexible(
                child: Text(
                  latest.entry.isPending
                      ? 'wartet auf Check-in'
                      : 'zuletzt ${formatShortDate(latest.date)}',
                  textAlign: TextAlign.right,
                  style: labelStyle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

DateTime? _date(String localDate) {
  final parsed = DateTime.tryParse(localDate);
  return parsed == null
      ? null
      : DateTime(parsed.year, parsed.month, parsed.day);
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: const SizedBox(width: 10, height: 10),
        ),
        const SizedBox(width: GainerSpacing.xxs),
        Flexible(
          child: Text(
            text,
            style: GainerTypography.label.copyWith(color: colors.primaryText),
          ),
        ),
      ],
    );
  }
}
