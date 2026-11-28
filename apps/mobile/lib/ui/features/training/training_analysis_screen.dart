import 'package:flutter/cupertino.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../../domain/models/training/training_analysis.dart';
import '../../../domain/models/training/training_trends.dart';
import '../../../domain/models/training/workout_input.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import '../cardio/cardio_format.dart' show formatCardioNumber;
import 'training_analysis_view_model.dart';
import 'training_format.dart';
import 'training_statistics_view_model.dart' show formatStatisticsWeight;

Future<void> openTrainingAnalysis(
  BuildContext context, {
  required TrainingLogRepository repository,
}) {
  return Navigator.of(context).push<void>(
    CupertinoPageRoute<void>(
      builder: (_) => TrainingAnalysisScreen(repository: repository),
    ),
  );
}

/// Ab dieser Textgröße steht der Status in der Unterzeile statt als Badge.
const _stackScale = 1.5;

String analysisStatusLabel(ExerciseProgressStatus status) => switch (status) {
  ExerciseProgressStatus.progressing => 'Steigt',
  ExerciseProgressStatus.stagnating => 'Stagniert',
  ExerciseProgressStatus.regressing => 'Sinkt',
  ExerciseProgressStatus.insufficientData => 'Zu wenig Daten',
};

String recommendationLabel(RecommendationKind kind) => switch (kind) {
  RecommendationKind.increaseWeight => 'Gewicht erhöhen',
  RecommendationKind.increaseReps => 'Wiederholungen steigern',
  RecommendationKind.keepWeight => 'Gewicht halten',
  RecommendationKind.deload => 'Deload',
  RecommendationKind.changeStimulus => 'Reiz wechseln',
  RecommendationKind.noRecommendation => 'Keine Empfehlung',
};

/// Änderung mit Vorzeichen und einer Nachkommastelle: „+17,9 %“, „−3,6 %“.
String formatAnalysisPercent(double? value) {
  if (value == null) return '–';
  final rounded = (value * 10).round() / 10;
  final sign = rounded > 0 ? '+' : (rounded < 0 ? '−' : '');
  return '$sign${formatCardioNumber(rounded.abs())} %';
}

/// Begründung in der Kontoeinheit; in kg exakt wie auf dem Server.
String recommendationText(
  TrainingRecommendation recommendation,
  WeightUnit unit,
) => recommendation.text(
  formatWeight: unit == WeightUnit.kg
      ? null
      : (kg) => formatStatisticsWeight(kg, unit),
);

/// Trainingsanalyse: je Übung Entwicklung, Ermüdungshinweise und ein
/// regelbasierter Vorschlag für das nächste Training.
class TrainingAnalysisScreen extends StatefulWidget {
  const TrainingAnalysisScreen({required this.repository, super.key});

  final TrainingLogRepository repository;

  @override
  State<TrainingAnalysisScreen> createState() => _TrainingAnalysisScreenState();
}

class _TrainingAnalysisScreenState extends State<TrainingAnalysisScreen> {
  late final TrainingAnalysisViewModel _viewModel = TrainingAnalysisViewModel(
    repository: widget.repository,
  )..load();

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  void _open(ExerciseAnalysis exercise) {
    Navigator.of(context).push<void>(
      CupertinoPageRoute<void>(
        builder: (_) => TrainingAnalysisExerciseScreen(
          exercise: exercise,
          weightUnit: _viewModel.weightUnit,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) => GainerScaffold(
        title: 'Trainingsanalyse',
        onRefresh: _viewModel.load,
        children: _children(context),
      ),
    );
  }

  List<Widget> _children(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final model = _viewModel;
    if (model.isLoading && !model.hasLoaded) {
      return const [Center(child: CupertinoActivityIndicator())];
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
    final analysis = model.analysis;
    return [
      GainerSegmentedControl<TrendPeriod>(
        options: {for (final period in analysisPeriods) period: period.label},
        value: model.period,
        onChanged: model.selectPeriod,
      ),
      const SizedBox(height: GainerSpacing.m),
      if (analysis == null || analysis.isEmpty)
        const _EmptyAnalysis()
      else ...[
        _OverallSection(overall: analysis.overall),
        const SizedBox(height: GainerSpacing.m),
        GainerGroupedSection(
          header: 'Übungen',
          footer:
              'Regelbasierte Vorschläge aus deinen Trainings, keine '
              'medizinische Beratung.',
          children: [
            for (final exercise in analysis.exercises)
              _ExerciseRow(exercise: exercise, onTap: () => _open(exercise)),
          ],
        ),
      ],
    ];
  }
}

class _OverallSection extends StatelessWidget {
  const _OverallSection({required this.overall});

  final TrainingAnalysisOverall overall;

  @override
  Widget build(BuildContext context) {
    final fatigued = overall.exercisesWithFatigue;
    return GainerGroupedSection(
      header: 'Gesamt',
      children: [
        GainerListRow(
          key: const ValueKey('analysis-weekly-volume'),
          title: 'Volumen je Woche',
          subtitle: 'Volle Wochen, Anfang gegen Ende des Zeitraums',
          value: formatAnalysisPercent(overall.weeklyVolumeChangePercent),
        ),
        GainerListRow(
          key: const ValueKey('analysis-fatigue'),
          title: 'Ermüdung',
          subtitle: fatigued == 0
              ? 'Keine Übung mit Hinweisen'
              : fatigued == 1
              ? '1 Übung mit Hinweisen'
              : '$fatigued Übungen mit Hinweisen',
          value: overall.fatigued ? 'Erhöht' : 'Unauffällig',
        ),
      ],
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.exercise, required this.onTap});

  final ExerciseAnalysis exercise;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final stacked = MediaQuery.textScalerOf(context).scale(1) >= _stackScale;
    final parts = [
      if (stacked) analysisStatusLabel(exercise.status),
      recommendationLabel(exercise.recommendation.kind),
      if (exercise.fatigueSignals.isNotEmpty) 'Ermüdung',
    ];
    return GainerListRow(
      key: ValueKey('analysis-exercise-${exercise.exerciseId}'),
      title: exercise.name,
      subtitle: parts.join(' · '),
      trailing: stacked ? null : AnalysisStatusBadge(status: exercise.status),
      showChevron: true,
      onTap: onTap,
    );
  }
}

/// Farbiges Etikett des Status.
class AnalysisStatusBadge extends StatelessWidget {
  const AnalysisStatusBadge({required this.status, super.key});

  final ExerciseProgressStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final color = switch (status) {
      ExerciseProgressStatus.progressing => colors.accent,
      ExerciseProgressStatus.stagnating => colors.warning,
      ExerciseProgressStatus.regressing => colors.destructive,
      ExerciseProgressStatus.insufficientData => colors.secondaryText,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GainerSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        analysisStatusLabel(status),
        style: GainerTypography.label.copyWith(color: color),
      ),
    );
  }
}

class _EmptyAnalysis extends StatelessWidget {
  const _EmptyAnalysis();

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return GainerCard(
      padding: const EdgeInsets.all(GainerSpacing.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Keine Trainings im Zeitraum',
            textAlign: TextAlign.center,
            style: GainerTypography.cardTitle.copyWith(
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: GainerSpacing.xs),
          Text(
            'Sobald du im Zeitraum Trainings mit Arbeitssätzen beendest, '
            'erscheinen hier Entwicklung, Ermüdung und Empfehlung je Übung.',
            textAlign: TextAlign.center,
            style: GainerTypography.body.copyWith(color: colors.secondaryText),
          ),
        ],
      ),
    );
  }
}

/// Detail einer Übung der Trainingsanalyse.
class TrainingAnalysisExerciseScreen extends StatelessWidget {
  const TrainingAnalysisExerciseScreen({
    required this.exercise,
    required this.weightUnit,
    super.key,
  });

  final ExerciseAnalysis exercise;
  final WeightUnit weightUnit;

  String _weight(double? kg) => formatStatisticsWeight(kg, weightUnit);

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final sessions = exercise.sessions;
    final recommendation = exercise.recommendation;
    return GainerScaffold(
      title: exercise.name,
      children: [
        GainerCard(
          key: const ValueKey('analysis-recommendation'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                recommendationLabel(recommendation.kind),
                style: GainerTypography.cardTitle.copyWith(
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: GainerSpacing.xs),
              Text(
                recommendationText(recommendation, weightUnit),
                style: GainerTypography.body.copyWith(
                  color: colors.secondaryText,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: GainerSpacing.m),
        GainerGroupedSection(
          header: 'Entwicklung',
          footer:
              'Trends vergleichen das erste mit dem letzten Drittel der '
              'Einheiten. Aufwärmsätze zählen nicht.',
          children: [
            GainerListRow(
              title: 'Status',
              value: analysisStatusLabel(exercise.status),
            ),
            GainerListRow(
              title: 'Einheiten',
              value: sessions.isEmpty
                  ? '0'
                  : '${sessions.length} · ${formatShortDate(sessions.first.day.toDateTime())}'
                        ' – ${formatShortDate(sessions.last.day.toDateTime())}',
            ),
            GainerListRow(
              title: 'Bestes 1RM',
              value: _weight(exercise.bestEstimatedOneRepMaxKg),
            ),
            GainerListRow(
              title: '1RM-Trend',
              value: formatAnalysisPercent(
                exercise.estimatedOneRepMaxChangePercent,
              ),
            ),
            GainerListRow(
              title: 'Topgewicht',
              value: formatAnalysisPercent(exercise.topWeightChangePercent),
            ),
            GainerListRow(
              title: 'Wdh. im Topsatz',
              value: _signedNumber(exercise.topRepetitionsChange),
            ),
            GainerListRow(
              title: 'Volumen je Woche',
              value: formatStatisticsVolume(
                exercise.volumePerWeekKg,
                weightUnit,
              ),
            ),
            GainerListRow(
              title: 'Arbeitssätze je Woche',
              value: formatCardioNumber(exercise.workingSetsPerWeek),
            ),
          ],
        ),
        const SizedBox(height: GainerSpacing.m),
        GainerGroupedSection(
          header: 'Ermüdung',
          children: [
            if (exercise.fatigueSignals.isEmpty)
              const GainerListRow(title: 'Keine Hinweise')
            else
              for (final signal in exercise.fatigueSignals)
                GainerListRow(
                  leadingIcon: CupertinoIcons.exclamationmark_triangle,
                  title: _signalTitle(signal.kind),
                  subtitle: _signalEvidence(signal),
                ),
          ],
        ),
        if (sessions.isNotEmpty) ...[
          const SizedBox(height: GainerSpacing.m),
          GainerGroupedSection(
            header: 'Einheiten',
            children: [
              for (final session in sessions.reversed)
                GainerListRow(
                  title: formatShortDate(session.day.toDateTime()),
                  subtitle:
                      '${session.workingSets} Sätze · Top '
                      '${_weight(session.topWeightKg)} × '
                      '${session.topSetMaxRepetitions}',
                  value: '1RM ${_weight(session.estimatedOneRepMaxKg)}',
                ),
            ],
          ),
        ],
      ],
    );
  }

  String _signedNumber(double? value) {
    if (value == null) return '–';
    final rounded = (value * 10).round() / 10;
    final sign = rounded > 0 ? '+' : (rounded < 0 ? '−' : '');
    return '$sign${formatCardioNumber(rounded.abs())}';
  }

  String _signalTitle(FatigueSignalKind kind) => switch (kind) {
    FatigueSignalKind.decliningRepetitions => 'Weniger Wiederholungen',
    FatigueSignalKind.failureOnMostSets => 'Oft bis zum Muskelversagen',
    FatigueSignalKind.volumeAndStrengthDrop => 'Volumen und Kraft sinken',
  };

  String _signalEvidence(FatigueSignal signal) => switch (signal.kind) {
    FatigueSignalKind.decliningRepetitions =>
      '${signal.fromRepetitions} → ${signal.toRepetitions} Wdh. in '
          '${signal.sessions} Einheiten, zuletzt ${_weight(signal.weightKg)}',
    FatigueSignalKind.failureOnMostSets =>
      '${signal.zeroRirSets} von ${signal.ratedSets} Sätzen mit RIR 0, '
          'zwei Einheiten in Folge',
    FatigueSignalKind.volumeAndStrengthDrop =>
      'Volumen ${formatAnalysisPercent(signal.volumeChangePercent)}, '
          '1RM ${formatAnalysisPercent(signal.estimatedOneRepMaxChangePercent)}',
  };
}
