import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../../data/models/api/api_models.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import '../../core/view_models/mobile_shell_view_model.dart';
import 'bodyweight_missing_hint.dart';
import 'progress_view_model.dart';

const _weekdays = [
  'Montag',
  'Dienstag',
  'Mittwoch',
  'Donnerstag',
  'Freitag',
  'Samstag',
  'Sonntag',
];

const _months = [
  'Januar',
  'Februar',
  'März',
  'April',
  'Mai',
  'Juni',
  'Juli',
  'August',
  'September',
  'Oktober',
  'November',
  'Dezember',
];

/// Übersicht „Heute“: drei Karten für Ernährung, Gewicht und Training.
/// Jede Karte öffnet über [onOpenArea] den passenden Tab.
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({
    required this.viewModel,
    this.onOpenArea,
    this.today,
    super.key,
  });

  final ProgressViewModel viewModel;

  /// Wechselt in den Tab des gewählten Bereichs.
  final ValueChanged<MobileArea>? onOpenArea;

  /// Heutiges Datum für die Anzeige; Standard ist die aktuelle Systemzeit.
  final DateTime Function()? today;

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.viewModel.load(),
    );
  }

  String get _todayLabel {
    final date = (widget.today ?? DateTime.now)();
    return '${_weekdays[date.weekday - 1]}, ${date.day}. ${_months[date.month - 1]}';
  }

  void _open(MobileArea area) => widget.onOpenArea?.call(area);

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
    value: widget.viewModel,
    child: Consumer<ProgressViewModel>(
      builder: (context, model, _) {
        final colors = GainerDesign.colorsOf(context);
        final data = model.dashboard;
        return KeyedSubtree(
          key: const ValueKey('progress-overview-scroll'),
          child: GainerScaffold(
            title: 'Heute',
            onRefresh: model.load,
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  left: GainerSpacing.xs,
                  bottom: GainerSpacing.m,
                ),
                child: Text(
                  _todayLabel,
                  style: GainerTypography.body.copyWith(
                    color: colors.secondaryText,
                  ),
                ),
              ),
              if (model.isLoading && data == null)
                const Center(child: CupertinoActivityIndicator()),
              if (model.errorMessage case final error?)
                _Notice(text: error, action: model.load),
              if (data != null) ...[
                _NutritionCard(
                  data: data,
                  onTap: () => _open(MobileArea.nutrition),
                ),
                const SizedBox(height: GainerSpacing.m),
                _WeightCard(data: data, onTap: () => _open(MobileArea.body)),
                const SizedBox(height: GainerSpacing.m),
                _TrainingCard(
                  data: data,
                  onTap: () => _open(MobileArea.training),
                ),
                if (data.training.bodyweightMissing) ...[
                  const SizedBox(height: GainerSpacing.m),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: GainerSpacing.xs),
                    child: BodyweightMissingHint(),
                  ),
                ],
                if (model.dashboardIsStale) ...[
                  const SizedBox(height: GainerSpacing.m),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: GainerSpacing.xs,
                    ),
                    child: Text(
                      'Gespeicherte Fortschrittsdaten · möglicherweise veraltet',
                      style: GainerTypography.label.copyWith(
                        color: colors.warning,
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    ),
  );
}

/// Deutsche Zahl mit Komma und Tausenderpunkt, z. B. 2350 → „2.350“.
String _formatNumber(double value, {int digits = 0}) {
  final fixed = value.abs().toStringAsFixed(digits);
  final parts = fixed.split('.');
  final grouped = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
  final text = parts.length > 1 ? '$grouped,${parts[1]}' : grouped;
  return value < 0 && double.parse(fixed) != 0 ? '−$text' : text;
}

String _formatTrend(double kgPerWeek) {
  final sign = kgPerWeek > 0 ? '+' : '';
  return '$sign${_formatNumber(kgPerWeek, digits: 1)} kg/Woche';
}

/// Antippbare Karte mit Titel und Chevron oben rechts.
class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.title,
    required this.onTap,
    required this.children,
  });

  final String title;
  final VoidCallback onTap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      pressedOpacity: .7,
      alignment: Alignment.topLeft,
      onPressed: onTap,
      child: SizedBox(
        width: double.infinity,
        child: GainerCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: GainerTypography.cardTitle.copyWith(
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                  Icon(
                    CupertinoIcons.chevron_forward,
                    size: 16,
                    color: colors.placeholderText,
                  ),
                ],
              ),
              const SizedBox(height: GainerSpacing.xs),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// Große Kennzahl mit kleiner Einheit daneben.
class _BigFigure extends StatelessWidget {
  const _BigFigure({required this.value, this.unit});

  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Text.rich(
      TextSpan(
        text: value,
        style: GainerTypography.largeTitle.copyWith(color: colors.primaryText),
        children: [
          if (unit != null)
            TextSpan(
              text: ' $unit',
              style: GainerTypography.body.copyWith(
                color: colors.secondaryText,
              ),
            ),
        ],
      ),
    );
  }
}

class _SecondaryText extends StatelessWidget {
  const _SecondaryText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: GainerTypography.body.copyWith(
      color: GainerDesign.colorsOf(context).secondaryText,
    ),
  );
}

class _NutritionCard extends StatelessWidget {
  const _NutritionCard({required this.data, required this.onTap});

  final ApiDashboardInsights data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final calories = data.nutrition.caloriesKcal.value;
    final protein = data.nutrition.proteinGrams.value;
    return _OverviewCard(
      title: 'Ernährung',
      onTap: onTap,
      children: [
        if (calories == null)
          const _SecondaryText('Noch nichts erfasst')
        else ...[
          _BigFigure(value: _formatNumber(calories), unit: 'kcal pro Tag'),
          if (protein != null) ...[
            const SizedBox(height: GainerSpacing.xxs),
            _SecondaryText('Protein ${_formatNumber(protein)} g'),
          ],
        ],
      ],
    );
  }
}

class _WeightCard extends StatelessWidget {
  const _WeightCard({required this.data, required this.onTap});

  final ApiDashboardInsights data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final latest = data.latestWeight;
    final trend = data.weight.trendKgPerWeek;
    final goal = data.activeGoal;
    return _OverviewCard(
      title: 'Gewicht',
      onTap: onTap,
      children: [
        if (latest == null) ...[
          const _SecondaryText('Noch kein Gewicht'),
          const SizedBox(height: GainerSpacing.xxs),
          Text(
            'Check-in eintragen',
            style: GainerTypography.body.copyWith(color: colors.accent),
          ),
        ] else ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              _BigFigure(
                value: _formatNumber(latest.weightKg, digits: 1),
                unit: 'kg',
              ),
              if (trend != null)
                Expanded(
                  child: Text(
                    _formatTrend(trend),
                    textAlign: TextAlign.end,
                    style: GainerTypography.label.copyWith(
                      color: colors.secondaryText,
                    ),
                  ),
                ),
            ],
          ),
          if (data.weightSeries.length > 1) ...[
            const SizedBox(height: GainerSpacing.s),
            _WeightChart(points: data.weightSeries),
          ],
          if (goal != null) ...[
            const SizedBox(height: GainerSpacing.xs),
            Text(
              'Ziel ${_formatNumber(goal.targetWeightKg, digits: 1)} kg',
              style: GainerTypography.label.copyWith(
                color: colors.secondaryText,
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _TrainingCard extends StatelessWidget {
  const _TrainingCard({required this.data, required this.onTap});

  final ApiDashboardInsights data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final count = data.workoutsLast7Days;
    return _OverviewCard(
      title: 'Training',
      onTap: onTap,
      children: [
        if (count == 0)
          const _SecondaryText('Noch kein Training diese Woche')
        else ...[
          _BigFigure(
            value: '$count',
            unit: count == 1 ? 'Training in 7 Tagen' : 'Trainings in 7 Tagen',
          ),
          const SizedBox(height: GainerSpacing.xxs),
          _SecondaryText(
            'Volumen ${_formatNumber(data.training.volumeKgRepetitions)} kg · 30 Tage',
          ),
        ],
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.action});
  final String text;
  final VoidCallback action;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(text, textAlign: TextAlign.center),
      GainerPillButton(
        label: 'Erneut versuchen',
        variant: GainerPillVariant.tonal,
        expand: true,
        onPressed: action,
      ),
    ],
  );
}

class _WeightChart extends StatelessWidget {
  const _WeightChart({required this.points});
  final List<ApiWeightPoint> points;
  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final accessible = points
        .map((item) => '${item.date}: ${item.weightKg.toStringAsFixed(1)} kg')
        .join(', ');
    return Semantics(
      label: 'Gewichtsverlauf. $accessible',
      child: SizedBox(
        height: 80,
        child: CustomPaint(
          painter: _WeightChartPainter(points, colors.accent),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _WeightChartPainter extends CustomPainter {
  _WeightChartPainter(this.points, this.color);
  final List<ApiWeightPoint> points;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) {
      return;
    }
    final values = points.map((e) => e.weightKg).toList();
    final minValue = values.reduce((a, b) => a < b ? a : b);
    final range = (values.reduce((a, b) => a > b ? a : b) - minValue).abs();
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = _linePath(values, size, minValue, range);
    final gridPaint = Paint()
      ..color = color.withValues(alpha: .14)
      ..strokeWidth = 1;
    for (final fraction in [0.2, 0.5, 0.8]) {
      final y = size.height * fraction;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    if (values.length == 1) {
      canvas.drawCircle(
        path.getBounds().topLeft,
        4,
        paint..style = PaintingStyle.fill,
      );
      return;
    }
    canvas.drawPath(path, paint);
    _drawPointMarkers(canvas, path, paint, values.length);
  }

  Path _linePath(
    List<double> values,
    Size size,
    double minValue,
    double range,
  ) {
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? size.width / 2
          : size.width * i / (values.length - 1);
      final y =
          size.height -
          12 -
          (range == 0
              ? size.height / 2
              : ((values[i] - minValue) / range) * (size.height - 24));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path;
  }

  void _drawPointMarkers(Canvas canvas, Path path, Paint paint, int count) {
    for (final point in path.computeMetrics()) {
      for (
        var distance = 0.0;
        distance <= point.length;
        distance += point.length / (count - 1)
      ) {
        final tangent = point.getTangentForOffset(distance);
        if (tangent != null) {
          canvas.drawCircle(
            tangent.position,
            3.5,
            paint..style = PaintingStyle.fill,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WeightChartPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.color != color;
}
