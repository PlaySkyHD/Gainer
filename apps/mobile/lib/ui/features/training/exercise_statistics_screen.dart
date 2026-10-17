import 'package:flutter/cupertino.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../../domain/models/training/training_statistics.dart';
import '../../../domain/models/training/workout_model.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import '../progress/exercise_progress_section.dart' show BodyweightMissingHint;
import 'exercise_statistics_view_model.dart';
import 'warmup_sets_row.dart';

/// Tab der Übungsstatistik. Die Übungskarte öffnet den passenden Tab direkt.
enum ExerciseStatisticsTab { history, chart, records }

/// Öffnet die Statistik einer Übung. Der Aufruf ist stabil, weil die Übungskarten
/// im Training darüber auf Verlauf, Graph und Rekorde verweisen.
Future<void> openExerciseStatistics(
  BuildContext context, {
  required TrainingLogRepository repository,
  required String exerciseId,
  ExerciseStatisticsTab initialTab = ExerciseStatisticsTab.chart,
}) {
  return Navigator.of(context).push<void>(
    CupertinoPageRoute<void>(
      builder: (_) => ExerciseStatisticsScreen(
        repository: repository,
        exerciseId: exerciseId,
        initialTab: initialTab,
      ),
    ),
  );
}

const _maxWeightLabel = 'Max. Gewicht';

class ExerciseStatisticsScreen extends StatefulWidget {
  const ExerciseStatisticsScreen({
    required this.repository,
    required this.exerciseId,
    this.initialTab = ExerciseStatisticsTab.chart,
    super.key,
  });

  final TrainingLogRepository repository;
  final String exerciseId;
  final ExerciseStatisticsTab initialTab;

  @override
  State<ExerciseStatisticsScreen> createState() =>
      _ExerciseStatisticsScreenState();
}

class _ExerciseStatisticsScreenState extends State<ExerciseStatisticsScreen> {
  late final ExerciseStatisticsViewModel _viewModel;
  late ExerciseStatisticsTab _tab;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    _viewModel = ExerciseStatisticsViewModel(
      repository: widget.repository,
      exerciseId: widget.exerciseId,
    )..load();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final model = _viewModel;
        return GainerScaffold(
          title: model.exerciseName ?? 'Statistik',
          children: [
            GainerSegmentedControl<ExerciseStatisticsTab>(
              options: const {
                ExerciseStatisticsTab.history: 'Verlauf',
                ExerciseStatisticsTab.chart: 'Graph',
                ExerciseStatisticsTab.records: 'Rekorde',
              },
              value: _tab,
              onChanged: (tab) => setState(() => _tab = tab),
            ),
            const SizedBox(height: GainerSpacing.s),
            WarmupSetsRow(
              value: model.includeWarmups,
              onChanged: model.setIncludeWarmups,
            ),
            const SizedBox(height: GainerSpacing.s),
            ..._body(context, model),
          ],
        );
      },
    );
  }

  List<Widget> _body(BuildContext context, ExerciseStatisticsViewModel model) {
    final colors = GainerDesign.colorsOf(context);
    if (model.isLoading && !model.hasLoaded) {
      return const [
        SizedBox(
          height: 160,
          child: Center(child: CupertinoActivityIndicator()),
        ),
      ];
    }
    if (model.errorMessage case final message?) {
      return [
        GainerCard(
          child: Text(
            message,
            style: GainerTypography.body.copyWith(color: colors.destructive),
          ),
        ),
      ];
    }
    if (model.sessions.isEmpty) {
      return [
        GainerCard(
          padding: const EdgeInsets.all(GainerSpacing.l),
          child: Text(
            'Für diese Übung gibt es noch keine erfassten Sätze.',
            textAlign: TextAlign.center,
            style: GainerTypography.body.copyWith(color: colors.secondaryText),
          ),
        ),
      ];
    }
    return [
      if (model.bodyweightMissing) ...[
        const GainerCard(child: BodyweightMissingHint()),
        const SizedBox(height: GainerSpacing.s),
      ],
      switch (_tab) {
        ExerciseStatisticsTab.history => _HistoryBody(model: model),
        ExerciseStatisticsTab.chart => _ChartBody(model: model),
        ExerciseStatisticsTab.records => _RecordsBody(model: model),
      },
    ];
  }
}

class _HistoryBody extends StatelessWidget {
  const _HistoryBody({required this.model});

  final ExerciseStatisticsViewModel model;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final sessions = model.sessions.reversed.toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Gewichte sind effektiv, bei Körpergewichtsübungen inklusive Körpergewicht.',
          style: GainerTypography.label.copyWith(color: colors.secondaryText),
        ),
        const SizedBox(height: GainerSpacing.s),
        for (final session in sessions) ...[
          GainerCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        model.titleOf(session.workoutId),
                        style: GainerTypography.cardTitle.copyWith(
                          color: colors.primaryText,
                        ),
                      ),
                    ),
                    Text(
                      _formatDate(session.startedAtUtc),
                      style: GainerTypography.label.copyWith(
                        color: colors.secondaryText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: GainerSpacing.xs),
                for (var i = 0; i < session.sets.length; i++)
                  _SetLine(index: i + 1, result: session.sets[i]),
                const SizedBox(height: GainerSpacing.xs),
                Text(
                  'Volumen ${session.volumeKg.toStringAsFixed(0)} kg · '
                  'Max. ${_formatKg(session.maxWeightKg)}',
                  style: GainerTypography.label.copyWith(
                    color: colors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: GainerSpacing.s),
        ],
      ],
    );
  }
}

class _SetLine extends StatelessWidget {
  const _SetLine({required this.index, required this.result});

  final int index;
  final SetResult result;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final typeLabel = switch (result.set.setType) {
      SetType.normal => null,
      SetType.warmup => 'Aufwärmen',
      SetType.dropset => 'Dropsatz',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              'Satz $index',
              style: TextStyle(color: colors.secondaryText),
            ),
          ),
          Expanded(
            child: Text(
              typeLabel ?? '',
              style: GainerTypography.label.copyWith(
                color: colors.secondaryText,
              ),
            ),
          ),
          Text(
            '${_formatKg(result.effectiveWeightKg)} × ${result.repetitions}',
            style: GainerTypography.body.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.primaryText,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartBody extends StatelessWidget {
  const _ChartBody({required this.model});

  final ExerciseStatisticsViewModel model;

  static const _metricLabels = <ChartMetric, String>{
    ChartMetric.estimatedOneRepMax: '1RM',
    ChartMetric.maxWeight: _maxWeightLabel,
    ChartMetric.volume: 'Volumen',
  };

  static const _periodLabels = <ChartPeriod, String>{
    ChartPeriod.threeMonths: '3 Monate',
    ChartPeriod.oneYear: '1 Jahr',
    ChartPeriod.all: 'Alles',
  };

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final points = model.chartPoints;
    return GainerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GainerSegmentedControl<ChartMetric>(
            options: _metricLabels,
            value: model.metric,
            onChanged: model.selectMetric,
          ),
          const SizedBox(height: GainerSpacing.xs),
          GainerSegmentedControl<ChartPeriod>(
            options: _periodLabels,
            value: model.period,
            onChanged: model.selectPeriod,
          ),
          const SizedBox(height: GainerSpacing.m),
          if (points.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Für diesen Zeitraum gibt es keine Werte.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.secondaryText),
              ),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Min. ${_formatValue(model.metric, _minOf(points))}',
                    style: TextStyle(color: colors.secondaryText, fontSize: 12),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Max. ${_formatValue(model.metric, _maxValueOf(points))}',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: colors.secondaryText, fontSize: 12),
                  ),
                ),
              ],
            ),
            Semantics(
              label: _chartDescription(model.metric, points),
              child: SizedBox(
                height: 160,
                width: double.infinity,
                child: CustomPaint(
                  painter: _TrendChartPainter(
                    points: points,
                    color: colors.accent,
                    labelColor: colors.secondaryText,
                  ),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _formatDate(points.first.startedAtUtc),
                    style: TextStyle(color: colors.secondaryText, fontSize: 12),
                  ),
                ),
                Expanded(
                  child: Text(
                    _formatDate(points.last.startedAtUtc),
                    textAlign: TextAlign.right,
                    style: TextStyle(color: colors.secondaryText, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: GainerSpacing.m),
            Row(
              children: [
                Expanded(
                  child: _Figure(
                    label: 'Aktuell',
                    value: _formatValue(model.metric, points.last.value),
                  ),
                ),
                Expanded(
                  child: _Figure(
                    label: 'Bestwert',
                    value: _formatValue(model.metric, _maxValueOf(points)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RecordsBody extends StatelessWidget {
  const _RecordsBody({required this.model});

  final ExerciseStatisticsViewModel model;

  static const _kindLabels = <RecordKind, String>{
    RecordKind.maxWeight: _maxWeightLabel,
    RecordKind.estimatedOneRepMax: 'Geschätztes 1RM',
    RecordKind.volume: 'Volumen',
    RecordKind.maxRepetitions: 'Max. Wdh.',
  };

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final records = model.records;
    final history = _historyNewestFirst(records);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GainerCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Aktuelle Rekorde',
                style: GainerTypography.cardTitle.copyWith(
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: GainerSpacing.xs),
              for (final kind in RecordKind.values)
                _RecordRow(
                  label: _kindLabels[kind]!,
                  value: _current(records, kind),
                  date: _currentDate(records, kind),
                ),
            ],
          ),
        ),
        const SizedBox(height: GainerSpacing.s),
        GainerCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Wiederholungsrekorde',
                style: GainerTypography.cardTitle.copyWith(
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Höchstes Gewicht für mindestens so viele Wiederholungen',
                style: GainerTypography.label.copyWith(
                  color: colors.secondaryText,
                ),
              ),
              const SizedBox(height: GainerSpacing.xs),
              for (final threshold in repetitionRecordThresholds)
                _RecordRow(
                  label: '$threshold Wdh.',
                  value: _formatKg(records?.repRecords[threshold]),
                ),
            ],
          ),
        ),
        const SizedBox(height: GainerSpacing.s),
        GainerCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Rekordverlauf',
                style: GainerTypography.cardTitle.copyWith(
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: GainerSpacing.xs),
              if (history.isEmpty)
                Text(
                  'Noch keine Rekorde.',
                  style: TextStyle(color: colors.secondaryText),
                )
              else
                for (final entry in history)
                  _RecordRow(
                    label: _kindLabels[entry.kind]!,
                    value: _recordValue(entry.kind, entry.event.value),
                    date: model.recordDate(entry.event.workoutId),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  String _current(ExerciseRecords? records, RecordKind kind) {
    final events = records?.eventsOf(kind) ?? const <RecordEvent>[];
    return events.isEmpty ? '–' : _recordValue(kind, events.last.value);
  }

  DateTime? _currentDate(ExerciseRecords? records, RecordKind kind) {
    final events = records?.eventsOf(kind) ?? const <RecordEvent>[];
    return events.isEmpty ? null : model.recordDate(events.last.workoutId);
  }

  List<_HistoryRecord> _historyNewestFirst(ExerciseRecords? records) {
    if (records == null) return const [];
    final all = [
      for (final kind in RecordKind.values)
        for (final event in records.eventsOf(kind)) _HistoryRecord(kind, event),
    ];
    all.sort((a, b) {
      final dateA = model.recordDate(a.event.workoutId);
      final dateB = model.recordDate(b.event.workoutId);
      if (dateA == null || dateB == null) return 0;
      return dateB.compareTo(dateA);
    });
    return all;
  }
}

class _HistoryRecord {
  const _HistoryRecord(this.kind, this.event);

  final RecordKind kind;
  final RecordEvent event;
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.label, required this.value, this.date});

  final String label;
  final String value;
  final DateTime? date;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: colors.secondaryText)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: GainerTypography.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.primaryText,
                ),
              ),
              if (date case final day?)
                Text(
                  _formatDate(day),
                  style: GainerTypography.label.copyWith(
                    color: colors.secondaryText,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GainerTypography.label.copyWith(color: colors.secondaryText),
        ),
        Text(
          value,
          style: GainerTypography.value.copyWith(color: colors.primaryText),
        ),
      ],
    );
  }
}

/// Zeichnet den Verlauf mit Gitterlinien ohne zusätzliche Chart-Abhängigkeit.
/// Die x-Achse ist nach Zeit skaliert, die y-Achse nach dem Wertebereich.
class _TrendChartPainter extends CustomPainter {
  const _TrendChartPainter({
    required this.points,
    required this.color,
    required this.labelColor,
  });

  final List<ChartPoint> points;
  final Color color;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.isEmpty) return;
    final offsets = _offsetsFor(size);
    _paintGrid(canvas, size);
    final dot = Paint()..color = color;
    if (offsets.length == 1) {
      canvas.drawCircle(offsets.single, 4, dot);
      return;
    }
    _paintLine(canvas, offsets);
    for (final point in offsets) {
      canvas.drawCircle(point, 4, dot);
    }
  }

  List<Offset> _offsetsFor(Size size) {
    const inset = 12.0;
    final values = [for (final point in points) point.value];
    final minValue = values.reduce((a, b) => a < b ? a : b);
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final range = maxValue - minValue;
    final height = size.height - inset * 2;
    final firstTime = points.first.startedAtUtc.millisecondsSinceEpoch;
    final span = points.last.startedAtUtc.millisecondsSinceEpoch - firstTime;
    return <Offset>[
      for (final point in points)
        Offset(
          span == 0
              ? size.width / 2
              : size.width *
                    (point.startedAtUtc.millisecondsSinceEpoch - firstTime) /
                    span,
          inset +
              height * (range == 0 ? .5 : 1 - (point.value - minValue) / range),
        ),
    ];
  }

  void _paintGrid(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = labelColor.withValues(alpha: .16)
      ..strokeWidth = 1;
    for (final fraction in [.25, .5, .75]) {
      final y = size.height * fraction;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
  }

  void _paintLine(Canvas canvas, List<Offset> offsets) {
    final line = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (final point in offsets.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant _TrendChartPainter old) =>
      old.points != points ||
      old.color != color ||
      old.labelColor != labelColor;
}

String _chartDescription(ChartMetric metric, List<ChartPoint> points) {
  final name = switch (metric) {
    ChartMetric.estimatedOneRepMax => 'Geschätztes 1RM',
    ChartMetric.maxWeight => _maxWeightLabel,
    ChartMetric.volume => 'Volumen',
  };
  return '$name im Verlauf. ${points.map((point) => '${_formatDate(point.startedAtUtc)}: ${_formatValue(metric, point.value)}').join(', ')}';
}

double _minOf(List<ChartPoint> points) =>
    points.map((point) => point.value).reduce((a, b) => a < b ? a : b);

double _maxValueOf(List<ChartPoint> points) =>
    points.map((point) => point.value).reduce((a, b) => a > b ? a : b);

String _formatValue(ChartMetric metric, double value) => switch (metric) {
  ChartMetric.volume => '${value.toStringAsFixed(0)} kg',
  _ => _formatKg(value),
};

String _recordValue(RecordKind kind, double value) => switch (kind) {
  RecordKind.maxRepetitions => '${value.toInt()} Wdh.',
  RecordKind.volume => '${value.toStringAsFixed(0)} kg',
  _ => _formatKg(value),
};

String _formatKg(double? value) =>
    value == null ? '–' : '${value.toStringAsFixed(1)} kg';

String _formatDate(DateTime utc) {
  final local = utc.toLocal();
  return '${local.day.toString().padLeft(2, '0')}.'
      '${local.month.toString().padLeft(2, '0')}.${local.year}';
}
