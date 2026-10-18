import 'package:flutter/cupertino.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'exercise_statistics_screen.dart';
import 'training_format.dart';
import 'training_statistics_view_model.dart';
import 'warmup_sets_row.dart';

/// Statistik-Segment: alle trainierten Übungen mit aktuellem Rekord. Die
/// Reihenfolge ist „zuletzt trainiert“ zuerst, damit die Übungen des letzten
/// Trainings oben stehen. Die Suche filtert nach Name.
class TrainingStatisticsSection extends StatefulWidget {
  const TrainingStatisticsSection({required this.repository, super.key});

  final TrainingLogRepository repository;

  @override
  State<TrainingStatisticsSection> createState() =>
      _TrainingStatisticsSectionState();
}

class _TrainingStatisticsSectionState extends State<TrainingStatisticsSection> {
  late final TrainingStatisticsViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = TrainingStatisticsViewModel(repository: widget.repository)
      ..load();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _open(String exerciseId) async {
    await openExerciseStatistics(
      context,
      repository: widget.repository,
      exerciseId: exerciseId,
    );
    if (mounted) await _viewModel.load();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final colors = GainerDesign.colorsOf(context);
        final model = _viewModel;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WarmupSetsRow(
              value: model.includeWarmups,
              onChanged: model.setIncludeWarmups,
            ),
            const SizedBox(height: GainerSpacing.s),
            if (model.hasLoaded && model.exercises.isNotEmpty) ...[
              GainerSearchField(
                placeholder: 'Übung suchen',
                onChanged: model.setQuery,
              ),
              const SizedBox(height: GainerSpacing.s),
            ],
            if (model.errorMessage case final message?) ...[
              GainerCard(
                child: Text(
                  message,
                  style: GainerTypography.body.copyWith(
                    color: colors.destructive,
                  ),
                ),
              ),
              const SizedBox(height: GainerSpacing.s),
            ],
            if (model.isLoading && !model.hasLoaded)
              const Padding(
                padding: EdgeInsets.all(GainerSpacing.l),
                child: Center(child: CupertinoActivityIndicator()),
              )
            else if (model.exercises.isEmpty)
              const _EmptyStatistics()
            else if (model.visibleExercises.isEmpty)
              GainerCard(
                padding: const EdgeInsets.all(GainerSpacing.l),
                child: Text(
                  'Keine passende Übung gefunden.',
                  textAlign: TextAlign.center,
                  style: GainerTypography.body.copyWith(
                    color: colors.secondaryText,
                  ),
                ),
              )
            else
              GainerGroupedSection(
                children: [
                  for (final exercise in model.visibleExercises)
                    GainerListRow(
                      title: exercise.name,
                      subtitle:
                          'Max. ${_formatKg(exercise.maxWeightKg)} · '
                          'zuletzt ${formatShortDate(exercise.lastTrainedAtUtc.toLocal())}',
                      // Geschätztes One-Rep-Max aus dem besten Satz.
                      value: '1RM ${_formatKg(exercise.estimatedOneRepMaxKg)}',
                      showChevron: true,
                      onTap: () => _open(exercise.exerciseId),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _EmptyStatistics extends StatelessWidget {
  const _EmptyStatistics();

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return GainerCard(
      padding: const EdgeInsets.all(GainerSpacing.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Noch keine Statistik',
            textAlign: TextAlign.center,
            style: GainerTypography.cardTitle.copyWith(
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: GainerSpacing.xs),
          Text(
            'Sobald du beendete Trainings mit erfassten Sätzen hast, erscheinen deine Übungen und Rekorde hier.',
            textAlign: TextAlign.center,
            style: GainerTypography.body.copyWith(color: colors.secondaryText),
          ),
        ],
      ),
    );
  }
}

String _formatKg(double? value) =>
    value == null ? '–' : '${value.toStringAsFixed(1).replaceAll('.', ',')} kg';
