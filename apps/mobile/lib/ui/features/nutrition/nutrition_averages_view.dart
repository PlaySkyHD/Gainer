import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../../data/repositories/nutrition/nutrition_repository.dart';
import '../../../domain/models/nutrition/nutrition_averages.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';

/// Anzeige-Format: deutsches Komma, Tausenderpunkt, keine Nullen am Ende.
String formatNutritionNumber(double value, {int decimals = 0}) {
  final fixed = value.abs().toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final digits = parts.first;
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write('.');
    grouped.write(digits[i]);
  }
  final fraction = parts.length > 1
      ? parts[1].replaceFirst(RegExp(r'0+$'), '')
      : '';
  final isZero = double.parse(fixed) == 0;
  return '${value < 0 && !isZero ? '-' : ''}$grouped'
      '${fraction.isEmpty ? '' : ',$fraction'}';
}

String _kcal(double value) => formatNutritionNumber(value);
String _grams(double? value) =>
    value == null ? '–' : '${formatNutritionNumber(value)} g';

const _months = [
  'Jan.',
  'Feb.',
  'März',
  'Apr.',
  'Mai',
  'Juni',
  'Juli',
  'Aug.',
  'Sept.',
  'Okt.',
  'Nov.',
  'Dez.',
];

String _shortDate(String localDate) {
  final date = DateTime.parse(localDate);
  return '${date.day}. ${_months[date.month - 1]}';
}

/// Kompakte Zeile unter der Tageskarte: „Ø 7 Tage 2.140 kcal · Protein 150 g“.
///
/// Lädt die Werte lokal und neu, sobald sich der Tagesstand ([refreshKey])
/// ändert, damit neue Einträge sofort im Schnitt landen.
class NutritionAveragesEntry extends StatefulWidget {
  const NutritionAveragesEntry({
    required this.repository,
    required this.refreshKey,
    super.key,
  });

  final NutritionRepository repository;

  /// Wechselt, wenn sich Tagebuch oder Zielplan geändert haben.
  final Object refreshKey;

  @override
  State<NutritionAveragesEntry> createState() => _NutritionAveragesEntryState();
}

class _NutritionAveragesEntryState extends State<NutritionAveragesEntry> {
  NutritionAveragesOverview? _overview;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(NutritionAveragesEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.refreshKey, widget.refreshKey)) _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      final overview = await widget.repository.readAverages(
        _today(widget.repository.clock()),
      );
      if (!mounted || generation != _generation) return;
      setState(() => _overview = overview);
    } catch (_) {
      // Der Schnitt ist eine Zusatzansicht; ohne Werte bleibt die Zeile leer.
    }
  }

  @override
  Widget build(BuildContext context) {
    final overview = _overview;
    if (overview == null) return const SizedBox.shrink();
    final colors = GainerDesign.colorsOf(context);
    final shown = overview.week.hasData ? overview.week : overview.month;
    final hasData = shown.hasData;
    final summary = hasData
        ? 'Ø ${shown.windowDays} Tage ${_kcal(shown.averageKilocalories!)} kcal'
              '${shown.averageProteinGrams == null ? '' : ' · Protein ${_grams(shown.averageProteinGrams)}'}'
        : 'Noch keine Einträge';
    return Padding(
      padding: const EdgeInsets.only(top: GainerSpacing.s),
      child: Semantics(
        button: hasData,
        label: 'Durchschnitt, $summary',
        excludeSemantics: true,
        child: GestureDetector(
          key: const ValueKey('nutrition-averages-entry'),
          behavior: HitTestBehavior.opaque,
          onTap: hasData
              ? () => showNutritionAverages(context, overview)
              : null,
          child: GainerCard(
            child: Row(
              children: [
                Icon(CupertinoIcons.chart_bar_alt_fill, color: colors.accent),
                const SizedBox(width: GainerSpacing.s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Durchschnitt',
                        style: GainerTypography.body.copyWith(
                          color: colors.primaryText,
                        ),
                      ),
                      Text(
                        summary,
                        style: GainerTypography.label.copyWith(
                          color: colors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasData)
                  Icon(
                    CupertinoIcons.chevron_forward,
                    size: 16,
                    color: colors.secondaryText,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _today(DateTime now) =>
    '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

Future<void> showNutritionAverages(
  BuildContext context,
  NutritionAveragesOverview overview,
) => showGainerSheet<void>(
  context: context,
  heightFactor: 0.9,
  builder: (_) => NutritionAveragesSheet(overview: overview),
);

/// Sheet „Durchschnitt“ mit Umschalter 7 Tage / 30 Tage.
class NutritionAveragesSheet extends StatefulWidget {
  const NutritionAveragesSheet({
    required this.overview,
    this.initialDays = 7,
    super.key,
  });

  final NutritionAveragesOverview overview;
  final int initialDays;

  @override
  State<NutritionAveragesSheet> createState() => _NutritionAveragesSheetState();
}

class _NutritionAveragesSheetState extends State<NutritionAveragesSheet> {
  late int _days = widget.initialDays;

  @override
  Widget build(BuildContext context) {
    final averages = _days == 7 ? widget.overview.week : widget.overview.month;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const GainerSheetHeader(title: 'Durchschnitt'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              GainerSpacing.m,
              GainerSpacing.m,
              GainerSpacing.m,
              GainerSpacing.l,
            ),
            children: [
              GainerSegmentedControl<int>(
                options: const {7: '7 Tage', 30: '30 Tage'},
                value: _days,
                onChanged: (value) => setState(() => _days = value),
              ),
              const SizedBox(height: GainerSpacing.m),
              if (!averages.hasData)
                _EmptyCard(days: averages.windowDays)
              else ...[
                _FigureCard(averages: averages),
                const SizedBox(height: GainerSpacing.m),
                GainerGroupedSection(
                  header: 'Ø pro erfasstem Tag',
                  children: [
                    GainerListRow(
                      title: 'Protein',
                      value: _grams(averages.averageProteinGrams),
                    ),
                    GainerListRow(
                      title: 'Kohlenhydrate',
                      value: _grams(averages.averageCarbohydrateGrams),
                    ),
                    GainerListRow(
                      title: 'Fett',
                      value: _grams(averages.averageFatGrams),
                    ),
                  ],
                ),
                const SizedBox(height: GainerSpacing.m),
                _ChartCard(averages: averages),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.days});
  final int days;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return GainerCard(
      child: Text(
        'Noch keine Einträge in den letzten $days Tagen.',
        style: GainerTypography.body.copyWith(color: colors.secondaryText),
      ),
    );
  }
}

class _FigureCard extends StatelessWidget {
  const _FigureCard({required this.averages});
  final NutritionAverages averages;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final kcal = _kcal(averages.averageKilocalories!);
    final secondary = GainerTypography.label.copyWith(
      color: colors.secondaryText,
    );
    return GainerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label: 'Durchschnitt $kcal Kilokalorien pro erfasstem Tag',
            excludeSemantics: true,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Ø $kcal',
                    style: GainerTypography.largeTitle.copyWith(
                      color: colors.primaryText,
                    ),
                  ),
                  TextSpan(
                    text: ' kcal',
                    style: GainerTypography.body.copyWith(
                      color: colors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Text('pro erfasstem Tag', style: secondary),
          const SizedBox(height: GainerSpacing.xs),
          Text(
            '${averages.loggedDays} von ${averages.windowDays} Tagen erfasst',
            style: GainerTypography.body.copyWith(color: colors.primaryText),
          ),
          if (averages.hasTarget) ...[
            const SizedBox(height: GainerSpacing.xs),
            Text(
              'Ziel Ø ${_kcal(averages.averageTargetKilocalories!)} kcal',
              style: GainerTypography.body.copyWith(color: colors.primaryText),
            ),
            Text(
              '${averages.daysWithinTarget} von ${averages.daysWithTarget} '
              'Tagen im Zielbereich ±10 %',
              style: secondary,
            ),
          ],
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.averages});
  final NutritionAverages averages;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final secondary = GainerTypography.label.copyWith(
      color: colors.secondaryText,
    );
    final first = averages.days.first.localDate;
    final last = averages.days.last.localDate;
    final empty = averages.windowDays - averages.loggedDays;
    return GainerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Kalorien pro Tag',
            style: GainerTypography.cardTitle.copyWith(
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: GainerSpacing.s),
          Semantics(
            label:
                'Kalorien pro Tag, ${averages.loggedDays} von '
                '${averages.windowDays} Tagen erfasst',
            excludeSemantics: true,
            child: SizedBox(
              height: 140,
              width: double.infinity,
              child: CustomPaint(
                key: const ValueKey('nutrition-averages-chart'),
                painter: NutritionDailyBarsPainter(
                  days: averages.days,
                  barColor: colors.accent,
                  emptyColor: colors.separator,
                  targetColor: colors.secondaryText,
                ),
              ),
            ),
          ),
          const SizedBox(height: GainerSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text(_shortDate(first), style: secondary)),
              Flexible(child: Text(_shortDate(last), style: secondary)),
            ],
          ),
          const SizedBox(height: GainerSpacing.xs),
          Wrap(
            spacing: GainerSpacing.m,
            runSpacing: GainerSpacing.xxs,
            children: [
              _LegendItem(color: colors.accent, label: 'Kalorien'),
              if (averages.hasTarget)
                _LegendItem(
                  color: colors.secondaryText,
                  label: 'Ziel',
                  dashed: true,
                ),
              if (empty > 0)
                _LegendItem(
                  color: colors.separator,
                  label: empty == 1
                      ? '1 Tag nichts erfasst'
                      : '$empty Tage nichts erfasst',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
    this.dashed = false,
  });

  final Color color;
  final String label;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: dashed ? 2 : 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: GainerSpacing.xs),
        Flexible(
          child: Text(
            label,
            style: GainerTypography.caption.copyWith(
              color: colors.secondaryText,
            ),
          ),
        ),
      ],
    );
  }
}

/// Balken je Kalendertag. Tage ohne Einträge bekommen keinen Nullbalken,
/// sondern nur einen blassen Strich an der Grundlinie. Das Tagesziel ist eine
/// gestrichelte Linie je Tag und folgt Zielwechseln im Zeitraum.
class NutritionDailyBarsPainter extends CustomPainter {
  const NutritionDailyBarsPainter({
    required this.days,
    required this.barColor,
    required this.emptyColor,
    required this.targetColor,
  });

  final List<NutritionAverageDay> days;
  final Color barColor;
  final Color emptyColor;
  final Color targetColor;

  /// Obere Grenze der y-Achse: größter Wert oder Ziel, mit Luft darüber.
  static double maxOf(List<NutritionAverageDay> days) {
    var maxValue = 0.0;
    for (final day in days) {
      maxValue = math.max(maxValue, day.kilocalories ?? 0);
      maxValue = math.max(maxValue, day.targetKilocalories ?? 0);
    }
    return maxValue <= 0 ? 1 : maxValue * 1.15;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || days.isEmpty) return;
    final gap = days.length > 14 ? 2.0 : 8.0;
    final barWidth = (size.width - gap * (days.length - 1)) / days.length;
    final maxValue = maxOf(days);
    double yOf(double value) => size.height - size.height * value / maxValue;
    final bar = Paint()..color = barColor;
    final empty = Paint()..color = emptyColor;
    final target = Paint()
      ..color = targetColor
      ..strokeWidth = 1.5;
    for (var i = 0; i < days.length; i++) {
      final x = i * (barWidth + gap);
      final kcal = days[i].kilocalories;
      if (kcal == null) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, size.height - 3, barWidth, 3),
            const Radius.circular(1.5),
          ),
          empty,
        );
      } else {
        final top = math.min(yOf(kcal), size.height - 2);
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTRB(x, top, x + barWidth, size.height),
            topLeft: const Radius.circular(3),
            topRight: const Radius.circular(3),
          ),
          bar,
        );
      }
      if (days[i].targetKilocalories case final goal?) {
        final y = yOf(goal);
        // Gestrichelt: Strichlänge passt sich der Balkenbreite an.
        final dash = math.max(2.0, math.min(4.0, barWidth / 3));
        for (var dx = x; dx < x + barWidth; dx += dash * 2) {
          canvas.drawLine(
            Offset(dx, y),
            Offset(math.min(dx + dash, x + barWidth), y),
            target,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant NutritionDailyBarsPainter old) =>
      old.days != days ||
      old.barColor != barColor ||
      old.emptyColor != emptyColor ||
      old.targetColor != targetColor;
}
