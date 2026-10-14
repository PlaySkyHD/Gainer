import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../../data/models/api/api_models.dart';
import '../../core/theme.dart';
import 'exercise_progress_section.dart';
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
        final data = model.dashboard;
        return CupertinoPageScaffold(
          navigationBar: const CupertinoNavigationBar(middle: Text('Heute')),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  key: const ValueKey('progress-overview-scroll'),
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    Text(
                      'Heute',
                      style: CupertinoTheme.of(context)
                          .textTheme
                          .navLargeTitleTextStyle,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Dein Fortschritt aus deinen Einträgen',
                      style: TextStyle(
                        color: GainerTheme.secondaryText(context),
                      ),
                    ),
                    if (model.dashboardIsStale) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Gespeicherte Fortschrittsdaten · möglicherweise veraltet',
                        style: TextStyle(
                          fontSize: 13,
                          color: GainerTheme.secondaryText(context),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    if (model.isLoading && data == null)
                      const Center(child: CupertinoActivityIndicator()),
                    if (model.errorMessage case final error?)
                      _Notice(text: error, action: model.load),
                    if (data != null) ...[
                      _Card(
                        title: 'Gewicht',
                        subtitle:
                            '${data.weight.observedDays} von ${data.weight.expectedDays} Tagen mit Eintrag',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (data.latestWeight case final latest?) ...[
                              Text(
                                'Letzter Eintrag · ${_dateLabel(latest.date)}',
                                style: TextStyle(
                                  color: GainerTheme.secondaryText(context),
                                ),
                              ),
                              Text(
                                '${latest.weightKg.toStringAsFixed(1)} kg',
                                style: CupertinoTheme.of(context)
                                    .textTheme
                                    .navTitleTextStyle,
                              ),
                              const SizedBox(height: 8),
                            ],
                            Text(
                              data.sevenDayWeight.averageKg == null
                                  ? 'Noch keine Gewichtsdaten der letzten ${data.sevenDayWeight.expectedDays} Tage'
                                  : 'Ø ${data.sevenDayWeight.expectedDays} Tage · ${data.sevenDayWeight.averageKg!.toStringAsFixed(1)} kg',
                              style: TextStyle(
                                color: GainerTheme.secondaryText(context),
                              ),
                            ),
                            Text(
                              data.weight.averageKg == null
                                  ? 'Ø ${data.weight.expectedDays} Tage · Noch keine Gewichtsdaten'
                                  : 'Ø ${data.weight.expectedDays} Tage · ${data.weight.averageKg!.toStringAsFixed(1)} kg',
                              style: CupertinoTheme.of(context)
                                  .textTheme
                                  .navTitleTextStyle,
                            ),
                            if (data.weight.trendKgPerWeek case final trend?)
                              Text(
                                '${trend >= 0 ? '+' : ''}${trend.toStringAsFixed(2)} kg pro Woche',
                                style: TextStyle(
                                  color: GainerTheme.secondaryText(context),
                                ),
                              ),
                            const SizedBox(height: 14),
                            if (data.weightSeries.isNotEmpty)
                              _WeightChart(points: data.weightSeries),
                            if (data.weightSeries.isEmpty)
                              const Text(
                                'Nach dem ersten Check-in erscheint hier dein Verlauf.',
                              ),
                          ],
                        ),
                      ),
                      ExerciseProgressSection(viewModel: model),
                      _Card(
                        title: 'Training',
                        subtitle:
                            '${data.workoutsLast7Days} Workouts in den letzten 7 Tagen',
                        child: _MetricRow(
                          metrics: [
                            (
                              'Workouts gesamt',
                              '${data.training.workoutCount}',
                            ),
                            (
                              'Trainingsvolumen',
                              '${data.training.volumeKgRepetitions.toStringAsFixed(0)} kg × Wdh.',
                            ),
                          ],
                        ),
                      ),
                      _Card(
                        title: 'Ernährung',
                        subtitle:
                            'Abdeckung ${((data.nutrition.coverage * 100).clamp(0, 100)).round()}% · ${data.nutrition.mealDiaryDays} Tage im Ernährungstagebuch',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data.nutrition.caloriesKcal.value == null
                                  ? 'Noch keine Kalorienwerte erfasst.'
                                  : '${data.nutrition.caloriesKcal.value!.toStringAsFixed(0)} kcal pro erfasstem Tag',
                            ),
                            const SizedBox(height: 4),
                            Text(
                              data.nutrition.proteinGrams.value == null
                                  ? 'Noch keine Proteinwerte erfasst.'
                                  : '${data.nutrition.proteinGrams.value!.toStringAsFixed(0)} g Protein pro erfasstem Tag',
                              style: TextStyle(
                                color: GainerTheme.secondaryText(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (data.activeGoal case final goal?)
                        _Card(
                          title: 'Aktives Ziel',
                          subtitle: _goalLabel(goal.kind),
                          child: Text(
                            '${goal.startWeightKg.toStringAsFixed(1)} kg  →  ${goal.targetWeightKg.toStringAsFixed(1)} kg',
                          ),
                        ),
                      Text(
                        'Die Werte beruhen auf deinen gespeicherten Einträgen.',
                        style: CupertinoTheme.of(context).textTheme.textStyle
                            .copyWith(
                              color: GainerTheme.secondaryText(context),
                            ),
                      ),
                      CupertinoButton(
                        minimumSize: const Size(double.infinity, 48),
                        onPressed: model.isLoading ? null : model.load,
                        child: const Text('Aktualisieren'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final String title, subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
        context,
      ),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: CupertinoColors.separator
            .resolveFrom(context)
            .withValues(alpha: .25),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: TextStyle(color: GainerTheme.secondaryText(context)),
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
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
      CupertinoButton(
        minimumSize: const Size(double.infinity, 48),
        onPressed: action,
        child: const Text('Erneut versuchen'),
      ),
    ],
  );
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.metrics});
  final List<(String, String)> metrics;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 18,
    runSpacing: 14,
    children: [
      for (final (label, value) in metrics)
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 115),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: CupertinoTheme.of(context).textTheme.navTitleTextStyle
                    .copyWith(fontSize: 20),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(color: GainerTheme.secondaryText(context)),
              ),
            ],
          ),
        ),
    ],
  );
}

class _WeightChart extends StatelessWidget {
  const _WeightChart({required this.points});
  final List<ApiWeightPoint> points;
  @override
  Widget build(BuildContext context) {
    final accessible = points
        .map((item) => '${item.date}: ${item.weightKg.toStringAsFixed(1)} kg')
        .join(', ');
    return Semantics(
      label: 'Gewichtsverlauf. $accessible',
      child: SizedBox(
        height: 130,
        child: CustomPaint(
          painter: _WeightChartPainter(
            points,
            CupertinoTheme.of(context).primaryColor,
          ),
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
    for (final point in path.computeMetrics()) {
      for (
        var distance = 0.0;
        distance <= point.length;
        distance += point.length / (values.length - 1)
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
