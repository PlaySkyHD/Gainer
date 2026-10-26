import 'package:flutter/cupertino.dart';

import '../../../data/repositories/cardio/cardio_repository.dart';
import '../../../data/repositories/training/training_log_repository.dart';
import '../../../domain/models/training/training_schedule.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import '../cardio/cardio_statistics_area.dart';
import 'exercise_statistics_screen.dart';
import 'muscle_map_screen.dart';
import 'training_format.dart';
import 'training_heatmap_card.dart';
import 'training_statistics_view_model.dart';
import 'warmup_sets_row.dart';

/// Statistik-Segment: alle trainierten Übungen mit aktuellem Rekord. Die
/// Reihenfolge ist „zuletzt trainiert“ zuerst, damit die Übungen des letzten
/// Trainings oben stehen. Die Suche filtert nach Name.
class TrainingStatisticsSection extends StatefulWidget {
  const TrainingStatisticsSection({
    required this.repository,
    this.cardio,
    this.onOpenCalendarDay,
    super.key,
  });

  final TrainingLogRepository repository;

  /// Cardio-Einheiten für den Bereich „Cardio“; ohne Wert entfällt er.
  final CardioRepository? cardio;

  /// Öffnet einen in der Heatmap gewählten Tag im Kalender; ohne Wert fehlt
  /// die Schaltfläche „Im Kalender öffnen“.
  final ValueChanged<LocalDay>? onOpenCalendarDay;

  @override
  State<TrainingStatisticsSection> createState() =>
      _TrainingStatisticsSectionState();
}

class _TrainingStatisticsSectionState extends State<TrainingStatisticsSection> {
  late final TrainingStatisticsViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = TrainingStatisticsViewModel(
      repository: widget.repository,
      cardio: widget.cardio,
    )..load();
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
            if (model.heatmap case final heatmap?
                when heatmap.trainingDays > 0) ...[
              const GainerSectionHeader(title: 'Trainingstage'),
              const SizedBox(height: GainerSpacing.xs),
              TrainingHeatmapCard(
                heatmap: heatmap,
                onOpenDay: widget.onOpenCalendarDay,
              ),
              const SizedBox(height: GainerSpacing.l),
            ],
            if (widget.cardio case final cardio?) ...[
              CardioStatisticsArea(repository: cardio),
              const GainerSectionHeader(title: 'Kraft'),
              const SizedBox(height: GainerSpacing.xs),
            ],
            GainerGroupedSection(
              children: [
                GainerListRow(
                  key: const ValueKey('statistics-muscles'),
                  title: 'Muskeln',
                  subtitle: 'Welche Muskeln du planst und trainierst',
                  leadingIcon: CupertinoIcons.person_fill,
                  showChevron: true,
                  onTap: () =>
                      openMuscleMap(context, repository: widget.repository),
                ),
              ],
            ),
            const SizedBox(height: GainerSpacing.s),
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
                          'Max. ${formatStatisticsWeight(exercise.maxWeightKg, model.weightUnit)} · '
                          'zuletzt ${formatShortDate(exercise.lastTrainedAtUtc.toLocal())}',
                      // Geschätztes One-Rep-Max aus dem besten Satz.
                      value:
                          '1RM ${formatStatisticsWeight(exercise.estimatedOneRepMaxKg, model.weightUnit)}',
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
