import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../../data/models/api/api_models.dart';
import 'progress_view_model.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({required this.viewModel, super.key});
  final ProgressViewModel viewModel;

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

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
    value: widget.viewModel,
    child: Consumer<ProgressViewModel>(
      builder: (context, model, _) {
        final data = model.dashboard;
        return CupertinoPageScaffold(
          navigationBar: const CupertinoNavigationBar(
            middle: Text('Fortschritt'),
          ),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (model.isLoading && data == null)
                      const Center(child: CupertinoActivityIndicator()),
                    if (model.errorMessage case final error?)
                      _Notice(text: error, action: model.load),
                    if (data != null) ...[
                      _Card(
                        title: 'Gewicht',
                        subtitle:
                            'Serverauswertung · ${data.weight.observedDays}/${data.weight.expectedDays} erfasste Tage',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data.weight.averageKg == null
                                  ? 'Noch keine Gewichtsdaten'
                                  : '${data.weight.averageKg!.toStringAsFixed(1)} kg im Durchschnitt',
                              style: CupertinoTheme.of(context)
                                  .textTheme
                                  .navTitleTextStyle,
                            ),
                            if (data.weight.trendKgPerWeek case final trend?)
                              Text(
                                '${trend >= 0 ? '+' : ''}${trend.toStringAsFixed(2)} kg pro Woche',
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
                      _Card(
                        title: 'Training',
                        subtitle:
                            'Letzte 7 Tage: ${data.workoutsLast7Days} Workouts',
                        child: Text(
                          '${data.training.workoutCount} ausgewertete Workouts · ${data.training.volumeKgRepetitions.toStringAsFixed(0)} kg·Wiederholungen',
                        ),
                      ),
                      _Card(
                        title: 'Ernährung',
                        subtitle:
                            'Abdeckung ${((data.nutrition.coverage * 100).clamp(0, 100)).round()}% · ${data.nutrition.mealDiaryDays} Tage im Ernährungstagebuch',
                        child: Text(
                          data.nutrition.caloriesKcal.value == null
                              ? 'Noch keine ausreichenden Tage für einen Mittelwert.'
                              : '${data.nutrition.caloriesKcal.value!.toStringAsFixed(0)} kcal pro erfasstem Tag',
                        ),
                      ),
                      if (data.activeGoal case final goal?)
                        _Card(
                          title: 'Aktives Ziel',
                          subtitle: goal.kind,
                          child: Text(
                            '${goal.startWeightKg} kg → ${goal.targetWeightKg} kg',
                          ),
                        ),
                      Text(
                        'Stand der Serverauswertung: Revision ${data.asOfRevision}',
                        style: CupertinoTheme.of(context).textTheme.textStyle
                            .copyWith(color: CupertinoColors.secondaryLabel),
                      ),
                      CupertinoButton(
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
      color: CupertinoTheme.of(context).barBackgroundColor,
      borderRadius: BorderRadius.circular(18),
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
          style: const TextStyle(color: CupertinoColors.secondaryLabel),
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
      CupertinoButton(onPressed: action, child: const Text('Erneut versuchen')),
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
    if (points.length < 2) return;
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
      final x = size.width * i / (values.length - 1);
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
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WeightChartPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.color != color;
}
