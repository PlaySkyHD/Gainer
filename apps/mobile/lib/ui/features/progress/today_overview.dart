import 'package:flutter/cupertino.dart';

import '../../../data/models/api/api_models.dart';
import '../../../domain/models/training/workout_input.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import '../training/training_format.dart';
import 'bodyweight_missing_hint.dart';
import 'progress_view_model.dart';
import 'weight_age.dart';

/// Inhalte des früheren Tabs „Heute“ für die Tagesansicht von heute im
/// Kalender: Gewichtsverlauf und Trainingsübersicht aus dem Dashboard
/// ([ProgressViewModel]). Die Ernährung von heute zeigt der Kalender selbst.
class TodayWeightOverview extends StatelessWidget {
  const TodayWeightOverview({
    required this.viewModel,
    required this.today,
    this.todayWeightKg,
    this.onTap,
    super.key,
  });

  final ProgressViewModel viewModel;
  final DateTime today;

  /// Lokal erfasstes Gewicht von heute. Es ersetzt den Dashboard-Wert, der
  /// erst nach dem nächsten Abruf aktuell wäre.
  final double? todayWeightKg;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final data = viewModel.dashboard;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (viewModel.isLoading && data == null)
          const Center(child: CupertinoActivityIndicator()),
        if (viewModel.errorMessage case final error?) ...[
          _Notice(text: error, action: viewModel.load),
          if (data != null) const SizedBox(height: GainerSpacing.m),
        ],
        if (data != null)
          _WeightCard(
            data: data,
            today: today,
            todayWeightKg: todayWeightKg,
            onTap: onTap ?? _noop,
          ),
      ],
    );
  }
}

/// Trainingsübersicht der letzten Tage mit Hinweisen zum Dashboard-Stand.
/// Ohne Dashboard-Daten bleibt sie leer.
class TodayTrainingOverview extends StatelessWidget {
  const TodayTrainingOverview({
    required this.viewModel,
    this.weightUnit = WeightUnit.kg,
    this.onTap,
    super.key,
  });

  final ProgressViewModel viewModel;

  /// Gewichtseinheit des Kontos für das Trainingsvolumen.
  final WeightUnit weightUnit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final data = viewModel.dashboard;
    if (data == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TrainingCard(data: data, unit: weightUnit, onTap: onTap ?? _noop),
        if (data.training.bodyweightMissing) ...[
          const SizedBox(height: GainerSpacing.m),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: GainerSpacing.xs),
            child: BodyweightMissingHint(),
          ),
        ],
        if (viewModel.dashboardIsStale) ...[
          const SizedBox(height: GainerSpacing.m),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: GainerSpacing.xs),
            child: Text(
              'Gespeicherte Fortschrittsdaten · möglicherweise veraltet',
              style: GainerTypography.label.copyWith(color: colors.warning),
            ),
          ),
        ],
      ],
    );
  }
}

void _noop() {}

String _isoDate(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// Deutsche Zahl mit Komma und Tausenderpunkt, z. B. 2350 → „2.350“.
String formatGermanNumber(double value, {int digits = 0}) {
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
  return '$sign${formatGermanNumber(kgPerWeek, digits: 1)} kg/Woche';
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

class _WeightCard extends StatelessWidget {
  const _WeightCard({
    required this.data,
    required this.today,
    required this.onTap,
    this.todayWeightKg,
  });

  final ApiDashboardInsights data;
  final DateTime today;
  final double? todayWeightKg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final local = todayWeightKg;
    final latest = local == null
        ? data.latestWeight
        : ApiWeightPoint(date: _isoDate(today), weightKg: local);
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
          // Bei großer Schrift rutscht der Trend unter die Zahl, statt sie
          // umzubrechen.
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: GainerSpacing.xs,
              children: [
                _BigFigure(
                  value: formatGermanNumber(latest.weightKg, digits: 1),
                  unit: 'kg',
                ),
                if (trend != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: GainerSpacing.xxs),
                    child: Text(
                      _formatTrend(trend),
                      style: GainerTypography.label.copyWith(
                        color: colors.secondaryText,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: GainerSpacing.xxs),
          _WeightAgeLabel(age: WeightAge.fromDate(latest.date, today)),
          if (data.weightSeries.length > 1) ...[
            const SizedBox(height: GainerSpacing.s),
            _WeightChart(points: data.weightSeries),
          ],
          if (goal != null) ...[
            const SizedBox(height: GainerSpacing.xs),
            Text(
              'Ziel ${formatGermanNumber(goal.targetWeightKg, digits: 1)} kg',
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

class _WeightAgeLabel extends StatelessWidget {
  const _WeightAgeLabel({required this.age});

  final WeightAge age;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final color = switch (age.severity) {
      WeightAgeSeverity.fresh => colors.secondaryText,
      WeightAgeSeverity.aging => colors.warning,
      WeightAgeSeverity.stale => colors.destructive,
    };
    return Semantics(
      label: 'Letztes Gewicht: ${age.label}',
      excludeSemantics: true,
      child: Text(
        age.label,
        style: GainerTypography.body.copyWith(color: color),
      ),
    );
  }
}

class _TrainingCard extends StatelessWidget {
  const _TrainingCard({
    required this.data,
    required this.unit,
    required this.onTap,
  });

  final ApiDashboardInsights data;
  final WeightUnit unit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final count = data.workoutsLast7Days;
    return _OverviewCard(
      title: 'Trainingsübersicht',
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
            'Volumen ${formatStatisticsVolume(data.training.volumeKgRepetitions, unit)} · 30 Tage',
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

/// Sprechbarer Text je Messpunkt, z. B. „20.10.2026: 80,5 kg“.
String weightPointLabel(ApiWeightPoint point) {
  final day = _calendarDay(point.date);
  final date = day == null ? point.date : formatGermanDate(day);
  return '$date: ${formatGermanNumber(point.weightKg, digits: 1)} kg';
}

final _datePart = RegExp(r'^(\d{4})-(\d{2})-(\d{2})');

/// Kalendertag aus dem Datumsteil `yyyy-MM-dd`, ohne Uhrzeit und Offset.
DateTime? _calendarDay(String date) {
  final match = _datePart.firstMatch(date);
  if (match == null) return null;
  return DateTime.utc(
    int.parse(match[1]!),
    int.parse(match[2]!),
    int.parse(match[3]!),
  );
}

/// Abstand der Marker vom Rand: Radius plus halbe Strichbreite.
const _markerInset = 5.0;

/// Bildschirmposition je Messpunkt. x folgt dem Datum, y dem Gewicht.
/// Fehlen gültige oder verschiedene Daten, verteilt x nach Index.
List<Offset> weightChartPositions(List<ApiWeightPoint> points, Size size) {
  if (points.isEmpty) return const [];
  final xAt = _weightChartX(points, size.width);
  final yAt = _weightChartY(points, size.height);
  return [for (var i = 0; i < points.length; i++) Offset(xAt(i), yAt(i))];
}

/// x-Position je Messpunkt: nach Datum, sonst gleichmäßig nach Index.
double Function(int index) _weightChartX(
  List<ApiWeightPoint> points,
  double width,
) {
  final days = _leadingCalendarDays(points);
  final byDate = days.length == points.length && points.length > 1;
  final (firstDay, dateSpan) = byDate ? _dayRange(days) : (0, 0);
  final inset = width < 2 * _markerInset ? width / 2 : _markerInset;
  final usable = width - 2 * inset;
  return (index) => points.length == 1
      ? width / 2
      : inset +
            usable * _xShare(index, points.length, days, firstDay, dateSpan);
}

/// Tagesnummern der Messpunkte bis zum ersten ungültigen Datum.
List<int> _leadingCalendarDays(List<ApiWeightPoint> points) {
  final days = <int>[];
  for (final point in points) {
    final day = _calendarDay(point.date);
    if (day == null) break;
    days.add(day.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay);
  }
  return days;
}

/// Erster Tag und Spannweite in Tagen.
(int, int) _dayRange(List<int> days) {
  final first = days.reduce((a, b) => a < b ? a : b);
  final last = days.reduce((a, b) => a > b ? a : b);
  return (first, last - first);
}

/// Anteil (0 bis 1) der Achse: nach Datum, ohne Datumsspanne nach Index.
double _xShare(int index, int count, List<int> days, int firstDay, int span) =>
    span > 0 ? (days[index] - firstDay) / span : index / (count - 1);

/// y-Position je Messpunkt: höheres Gewicht weiter oben.
double Function(int index) _weightChartY(
  List<ApiWeightPoint> points,
  double height,
) {
  var minValue = points.first.weightKg;
  var maxValue = minValue;
  for (final point in points) {
    if (point.weightKg < minValue) minValue = point.weightKg;
    if (point.weightKg > maxValue) maxValue = point.weightKg;
  }
  final range = maxValue - minValue;
  return (index) {
    if (range == 0) return height / 2;
    return height -
        12 -
        ((points[index].weightKg - minValue) / range) * (height - 24);
  };
}

class _WeightChart extends StatelessWidget {
  const _WeightChart({required this.points});
  final List<ApiWeightPoint> points;
  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final accessible = points.map(weightPointLabel).join(', ');
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
    final positions = weightChartPositions(points, size);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final gridPaint = Paint()
      ..color = color.withValues(alpha: .14)
      ..strokeWidth = 1;
    for (final fraction in [0.2, 0.5, 0.8]) {
      final y = size.height * fraction;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    if (positions.length > 1) {
      final path = Path()..moveTo(positions.first.dx, positions.first.dy);
      for (final position in positions.skip(1)) {
        path.lineTo(position.dx, position.dy);
      }
      canvas.drawPath(path, paint);
    }
    final markerPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    for (final position in positions) {
      canvas.drawCircle(position, positions.length == 1 ? 4 : 3.5, markerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WeightChartPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.color != color;
}
