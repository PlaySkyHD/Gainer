import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../../data/models/api/api_models.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'exercise_progress_section.dart';
import 'progress_group.dart';
import 'progress_view_model.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({required this.viewModel, super.key});
  final ProgressViewModel viewModel;

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  String _goalLabel(String kind) => switch (kind.toLowerCase()) {
    'bulk' => 'Muskelaufbau',
    'maintain' => 'Gewicht halten',
    'cut' => 'Gewicht reduzieren',
    _ => 'Körperziel',
  };

  String _dateLabel(String value) {
    final date = DateTime.tryParse(value);
    if (date == null) {
      return value;
    }
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.viewModel.load(),
    );
  }

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
            trailing: [
              if (data != null)
                GainerPillButton(
                  label: 'Aktualisieren',
                  variant: GainerPillVariant.tonal,
                  onPressed: model.isLoading ? null : model.load,
                ),
            ],
            children: [
              if (model.dashboardIsStale) ...[
                Text(
                  'Gespeicherte Fortschrittsdaten · möglicherweise veraltet',
                  style: GainerTypography.label.copyWith(color: colors.warning),
                ),
                const SizedBox(height: GainerSpacing.s),
              ],
              if (model.isLoading && data == null)
                const Center(child: CupertinoActivityIndicator()),
              if (model.errorMessage case final error?)
                _Notice(text: error, action: model.load),
              if (data != null) ...[
                _weightGroup(context, data),
                ExerciseProgressSection(viewModel: model),
                _trainingGroup(context, data),
                _nutritionGroup(context, data),
                if (data.activeGoal case final goal?)
                  ProgressGroup(
                    header: 'Aktives Ziel',
                    children: [
                      GainerListRow(
                        title: _goalLabel(goal.kind),
                        value:
                            '${goal.startWeightKg.toStringAsFixed(1)} kg  →  ${goal.targetWeightKg.toStringAsFixed(1)} kg',
                      ),
                    ],
                  ),
                Text(
                  'Die Werte beruhen auf deinen gespeicherten Einträgen.',
                  style: GainerTypography.label.copyWith(
                    color: colors.secondaryText,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    ),
  );

  Widget _weightGroup(BuildContext context, ApiDashboardInsights data) {
    final latest = data.latestWeight;
    return ProgressGroup(
      header: 'Gewicht',
      footer:
          '${data.weight.observedDays} von ${data.weight.expectedDays} Tagen mit Eintrag',
      children: [
        if (latest case final entry?)
          ProgressFigure(
            label: 'Letzter Eintrag · ${_dateLabel(entry.date)}',
            value: '${entry.weightKg.toStringAsFixed(1)} kg',
            padding: const EdgeInsets.all(GainerSpacing.m),
          ),
        GainerListRow(
          title: data.sevenDayWeight.averageKg == null
              ? 'Noch keine Gewichtsdaten der letzten ${data.sevenDayWeight.expectedDays} Tage'
              : 'Ø ${data.sevenDayWeight.expectedDays} Tage · ${data.sevenDayWeight.averageKg!.toStringAsFixed(1)} kg',
        ),
        GainerListRow(
          title: data.weight.averageKg == null
              ? 'Ø ${data.weight.expectedDays} Tage · Noch keine Gewichtsdaten'
              : 'Ø ${data.weight.expectedDays} Tage · ${data.weight.averageKg!.toStringAsFixed(1)} kg',
        ),
        if (data.weight.trendKgPerWeek case final trend?)
          GainerListRow(
            title:
                '${trend >= 0 ? '+' : ''}${trend.toStringAsFixed(2)} kg pro Woche',
          ),
        Padding(
          padding: const EdgeInsets.all(GainerSpacing.m),
          child: data.weightSeries.isEmpty
              ? Text(
                  'Nach dem ersten Check-in erscheint hier dein Verlauf.',
                  style: GainerTypography.body.copyWith(
                    color: GainerDesign.colorsOf(context).secondaryText,
                  ),
                )
              : _WeightChart(points: data.weightSeries),
        ),
      ],
    );
  }

  Widget _trainingGroup(
    BuildContext context,
    ApiDashboardInsights data,
  ) => ProgressGroup(
    header: 'Training',
    footer: '${data.workoutsLast7Days} Workouts in den letzten 7 Tagen',
    children: [
      GainerListRow(
        title: 'Workouts gesamt',
        value: '${data.training.workoutCount}',
      ),
      GainerListRow(
        title: 'Trainingsvolumen',
        value:
            '${data.training.volumeKgRepetitions.toStringAsFixed(0)} kg × Wdh.',
      ),
      if (data.training.bodyweightMissing)
        const Padding(
          padding: EdgeInsets.all(GainerSpacing.m),
          child: BodyweightMissingHint(),
        ),
    ],
  );

  Widget _nutritionGroup(
    BuildContext context,
    ApiDashboardInsights data,
  ) => ProgressGroup(
    header: 'Ernährung',
    footer:
        'Abdeckung ${((data.nutrition.coverage * 100).clamp(0, 100)).round()}% · ${data.nutrition.mealDiaryDays} Tage im Ernährungstagebuch',
    children: [
      GainerListRow(
        title: data.nutrition.caloriesKcal.value == null
            ? 'Noch keine Kalorienwerte erfasst.'
            : '${data.nutrition.caloriesKcal.value!.toStringAsFixed(0)} kcal pro erfasstem Tag',
      ),
      GainerListRow(
        title: data.nutrition.proteinGrams.value == null
            ? 'Noch keine Proteinwerte erfasst.'
            : '${data.nutrition.proteinGrams.value!.toStringAsFixed(0)} g Protein pro erfasstem Tag',
      ),
    ],
  );
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
        height: 130,
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
