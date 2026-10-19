import 'package:flutter/cupertino.dart';

import '../../../data/repositories/cardio/cardio_repository.dart';
import '../../../domain/models/cardio/cardio_progress.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import '../training/training_format.dart';
import 'cardio_format.dart';
import 'cardio_progress_charts.dart';

/// Auswahl der Wochenbalken.
enum CardioWeekMetric { target, zone2 }

/// Lädt die lokalen Cardio-Einheiten und berechnet [CardioProgress].
class CardioStatisticsViewModel extends ChangeNotifier {
  CardioStatisticsViewModel({
    required this.repository,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final CardioRepository repository;
  final DateTime Function() _clock;

  CardioProgress? progress;
  CardioWeekMetric metric = CardioWeekMetric.target;
  bool _disposed = false;

  Future<void> load() async {
    try {
      final sessions = await repository.readSessions();
      final prefs = await repository.preferences.read();
      if (_disposed) return;
      progress = CardioProgress.compute(
        sessions,
        now: _clock(),
        weeklyTargetMinutes: prefs.weeklyTargetMinutes,
        zones: prefs.zones,
      );
      if (!progress!.hasZone2) metric = CardioWeekMetric.target;
    } on Object {
      if (_disposed) return;
      progress = null;
    }
    if (!_disposed) notifyListeners();
  }

  void selectMetric(CardioWeekMetric value) {
    metric = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Bereich „Cardio“ im Statistik-Segment: Wochenbalken, aerobe Form und
/// Erholungspuls. Ohne Cardio-Einheiten ein Hinweis zum Starten.
class CardioStatisticsArea extends StatefulWidget {
  const CardioStatisticsArea({required this.repository, this.clock, super.key});

  final CardioRepository repository;
  final DateTime Function()? clock;

  @override
  State<CardioStatisticsArea> createState() => _CardioStatisticsAreaState();
}

class _CardioStatisticsAreaState extends State<CardioStatisticsArea> {
  late final CardioStatisticsViewModel _model = CardioStatisticsViewModel(
    repository: widget.repository,
    clock: widget.clock,
  )..load();

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _model,
    builder: (context, _) {
      final progress = _model.progress;
      if (progress == null) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GainerSectionHeader(title: 'Cardio'),
          const SizedBox(height: GainerSpacing.xs),
          if (!progress.hasSessions)
            const _CardioEmptyHint()
          else ...[
            _WeeksCard(model: _model, progress: progress),
            const SizedBox(height: GainerSpacing.s),
            _FitnessCard(progress: progress),
            if (progress.recoveryAverageBpm case final drop?) ...[
              const SizedBox(height: GainerSpacing.s),
              GainerGroupedSection(
                children: [
                  GainerListRow(
                    key: const ValueKey('cardio-stats-recovery'),
                    title:
                        'Ø Erholung ${formatBpmChange(drop)} '
                        '(letzte ${progress.recoverySampleCount})',
                  ),
                ],
              ),
            ],
          ],
          const SizedBox(height: GainerSpacing.l),
        ],
      );
    },
  );
}

class _CardioEmptyHint extends StatelessWidget {
  const _CardioEmptyHint();

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return GainerCard(
      key: const ValueKey('cardio-stats-empty'),
      padding: const EdgeInsets.all(GainerSpacing.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Noch kein Cardio',
            textAlign: TextAlign.center,
            style: GainerTypography.cardTitle.copyWith(
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: GainerSpacing.xs),
          Text(
            'Starte im Tagebuch eine Cardio-Einheit mit Pulsgurt. Danach '
            'siehst du hier deine Wochen und deine Form.',
            textAlign: TextAlign.center,
            style: GainerTypography.body.copyWith(color: colors.secondaryText),
          ),
        ],
      ),
    );
  }
}

class _WeeksCard extends StatelessWidget {
  const _WeeksCard({required this.model, required this.progress});

  final CardioStatisticsViewModel model;
  final CardioProgress progress;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final zone2 = model.metric == CardioWeekMetric.zone2 && progress.hasZone2;
    final weeks = progress.weeks;
    final values = [
      for (final week in weeks)
        zone2 ? (week.zone2Minutes ?? 0) : week.targetMinutes,
    ];
    final labelStyle = GainerTypography.caption.copyWith(
      color: colors.secondaryText,
    );
    return GainerCard(
      key: const ValueKey('cardio-stats-weeks'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // „Diese Woche 95 / 150 min“ als Titel, Einheiten und Dauer
          // darunter, damit die Zeile nicht mitten im Wert umbricht.
          ...() {
            final parts = progress
                .currentWeekSummary(zone2: zone2)
                .split(' · ');
            return [
              Text(
                parts.first,
                key: const ValueKey('cardio-stats-summary'),
                style: GainerTypography.cardTitle.copyWith(
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: GainerSpacing.xxs),
              Text(
                [
                  ...parts.skip(1),
                  zone2 ? 'Minuten in Zone 2' : 'Minuten im Zielbereich',
                ].join(' · '),
                style: labelStyle,
              ),
            ];
          }(),
          if (progress.hasZone2) ...[
            const SizedBox(height: GainerSpacing.s),
            GainerSegmentedControl<CardioWeekMetric>(
              options: const {
                CardioWeekMetric.target: 'Zielbereich',
                CardioWeekMetric.zone2: 'Zone 2',
              },
              value: model.metric,
              onChanged: model.selectMetric,
            ),
          ],
          const SizedBox(height: GainerSpacing.m),
          CardioWeeklyBars(
            values: values,
            goal: progress.weeklyTargetMinutes,
            barColor: colors.accent.withValues(alpha: .45),
            currentColor: colors.accent,
            goalColor: colors.secondaryText,
            labelStyle: labelStyle,
            semanticLabel:
                'Minuten pro Woche, letzte ${weeks.length} Wochen: '
                '${values.join(', ')}. Wochenziel '
                '${progress.weeklyTargetMinutes} Minuten.',
          ),
          const SizedBox(height: GainerSpacing.xxs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  formatShortDate(weeks.first.start),
                  style: labelStyle,
                ),
              ),
              Text('Diese Woche', style: labelStyle),
            ],
          ),
        ],
      ),
    );
  }
}

class _FitnessCard extends StatelessWidget {
  const _FitnessCard({required this.progress});

  final CardioProgress progress;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final labelStyle = GainerTypography.caption.copyWith(
      color: colors.secondaryText,
    );
    final points = progress.efficiency;
    final comparison = progress.samePower;
    final hint = points.isEmpty
        ? 'Trage die Ø-Leistung vom Ergometer ein, um deine Form zu sehen.'
        : null;
    return GainerCard(
      key: const ValueKey('cardio-stats-fitness'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Aerobe Form',
            style: GainerTypography.cardTitle.copyWith(
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: GainerSpacing.xxs),
          Text('Effizienzfaktor (Watt ÷ Puls)', style: labelStyle),
          const SizedBox(height: GainerSpacing.s),
          if (hint != null)
            Text(
              hint,
              key: const ValueKey('cardio-stats-power-hint'),
              style: GainerTypography.body.copyWith(
                color: colors.secondaryText,
              ),
            )
          else ...[
            if (points.length >= 2)
              CardioLineChart(
                series: [
                  ChartSeries(
                    points: [
                      for (var i = 0; i < points.length; i++)
                        ChartPoint(
                          i / (points.length - 1),
                          points[i].efficiency,
                        ),
                    ],
                    color: colors.accent,
                  ),
                ],
                gridColor: colors.separator,
                labelStyle: labelStyle,
                axisFormat: (value) =>
                    formatCardioNumber(value, maxDecimals: 2),
                semanticLabel:
                    'Effizienzfaktor der letzten ${points.length} Einheiten, '
                    'zuletzt ${formatCardioNumber(points.last.efficiency, maxDecimals: 2)}',
              )
            else
              Text(
                'EF ${formatCardioNumber(points.single.efficiency, maxDecimals: 2)} · '
                'Ab zwei Einheiten mit Leistung erscheint der Verlauf.',
                style: GainerTypography.body.copyWith(
                  color: colors.secondaryText,
                ),
              ),
            const SizedBox(height: GainerSpacing.s),
            Text(
              comparison == null
                  ? 'Der Vergleich bei gleicher Leistung erscheint ab '
                        '${CardioProgress.minSamePowerSessions} Einheiten '
                        'mit ähnlicher Leistung.'
                  : 'bei ${comparison.powerWatts} W: '
                        '${comparison.firstBpm} → ${comparison.lastBpm} bpm',
              key: const ValueKey('cardio-stats-same-power'),
              style: GainerTypography.body.copyWith(
                color: comparison == null
                    ? colors.secondaryText
                    : colors.primaryText,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
