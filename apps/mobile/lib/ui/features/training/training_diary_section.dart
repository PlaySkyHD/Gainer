import 'package:flutter/cupertino.dart';

import '../../../domain/models/training/workout_model.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'repeat_workout_sheet.dart';
import 'save_workout_as_plan.dart';
import 'training_format.dart';
import 'training_home_view_model.dart';

const _deleteLabel = 'Löschen';

enum _DiaryAction { repeat, savePlan, delete }

/// Tagebuch: Trainings nach Monat gruppiert, neueste zuerst.
class TrainingDiarySection extends StatelessWidget {
  const TrainingDiarySection({
    required this.viewModel,
    required this.editing,
    required this.onOpen,
    required this.onStart,
    super.key,
  });

  final TrainingHomeViewModel viewModel;

  /// Im Bearbeiten-Modus löschen rote Minus-Buttons die Zeilen.
  final bool editing;
  final ValueChanged<Workout> onOpen;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final colors = GainerDesign.colorsOf(context);
        final diary = viewModel.diary;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (viewModel.errorMessage case final message?) ...[
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
            if (diary.isEmpty && viewModel.isLoading)
              const Center(child: CupertinoActivityIndicator())
            else if (diary.isEmpty)
              _EmptyDiary(onStart: onStart)
            else
              for (final month in groupDiaryByMonth(diary)) ...[
                GainerSectionHeader(
                  title: formatMonthTitle(DateTime(month.year, month.month)),
                  trailing: formatTrainingCount(month.workouts.length),
                ),
                const SizedBox(height: GainerSpacing.xs),
                _MonthCard(
                  viewModel: viewModel,
                  workouts: month.workouts,
                  editing: editing,
                  onOpen: onOpen,
                ),
                const SizedBox(height: GainerSpacing.l),
              ],
          ],
        );
      },
    );
  }
}

class _EmptyDiary extends StatelessWidget {
  const _EmptyDiary({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return GainerCard(
      padding: const EdgeInsets.all(GainerSpacing.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Noch keine Trainings',
            textAlign: TextAlign.center,
            style: GainerTypography.cardTitle.copyWith(
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: GainerSpacing.xs),
          Text(
            'Starte dein erstes Training, dann erscheint es hier im Tagebuch.',
            textAlign: TextAlign.center,
            style: GainerTypography.body.copyWith(color: colors.secondaryText),
          ),
          const SizedBox(height: GainerSpacing.m),
          GainerPillButton(
            key: const ValueKey('training-start-empty'),
            label: 'Training starten',
            onPressed: onStart,
          ),
        ],
      ),
    );
  }
}

class _MonthCard extends StatelessWidget {
  const _MonthCard({
    required this.viewModel,
    required this.workouts,
    required this.editing,
    required this.onOpen,
  });

  final TrainingHomeViewModel viewModel;
  final List<Workout> workouts;
  final bool editing;
  final ValueChanged<Workout> onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(GainerRadii.card),
      child: DecoratedBox(
        decoration: BoxDecoration(color: colors.surface),
        child: Column(
          children: [
            for (var i = 0; i < workouts.length; i++) ...[
              if (i > 0)
                Container(
                  height: 0.5,
                  margin: const EdgeInsets.only(left: GainerSpacing.m),
                  color: colors.separator,
                ),
              _DiaryRow(
                viewModel: viewModel,
                workout: workouts[i],
                editing: editing,
                onOpen: onOpen,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DiaryRow extends StatelessWidget {
  const _DiaryRow({
    required this.viewModel,
    required this.workout,
    required this.editing,
    required this.onOpen,
  });

  final TrainingHomeViewModel viewModel;
  final Workout workout;
  final bool editing;
  final ValueChanged<Workout> onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final row = _rowContent(context, colors);
    if (editing) {
      return Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: GainerSpacing.s),
            child: GainerDeleteMinusButton(
              semanticLabel: '${workout.title} löschen',
              onPressed: () => _deleteAfterConfirmation(context),
            ),
          ),
          Expanded(child: row),
        ],
      );
    }
    return GainerSwipeToDelete(
      dismissKey: ValueKey('diary-${workout.workoutId}'),
      label: _deleteLabel,
      confirm: () => _confirmDelete(context, workout),
      onDeleted: () => viewModel.deleteWorkout(workout.workoutId),
      child: row,
    );
  }

  Future<void> _deleteAfterConfirmation(BuildContext context) async {
    if (await _confirmDelete(context, workout)) {
      await viewModel.deleteWorkout(workout.workoutId);
    }
  }

  Future<void> _showActions(BuildContext context) async {
    final action = await showGainerActionSheet<_DiaryAction>(
      context: context,
      title: workout.title,
      groups: [
        [
          const GainerSheetAction(
            label: 'Wiederholen',
            icon: CupertinoIcons.arrow_2_circlepath,
            value: _DiaryAction.repeat,
          ),
          const GainerSheetAction(
            label: 'Als Trainingsplan speichern',
            icon: CupertinoIcons.square_list,
            value: _DiaryAction.savePlan,
          ),
        ],
        [
          const GainerSheetAction(
            label: _deleteLabel,
            icon: CupertinoIcons.trash,
            value: _DiaryAction.delete,
            destructive: true,
          ),
        ],
      ],
    );
    if (!context.mounted) return;
    switch (action) {
      case _DiaryAction.repeat:
        await showRepeatWorkoutSheet(
          context,
          repository: viewModel.repository,
          activeWorkout: viewModel.activeWorkout,
          source: workout,
        );
        await viewModel.loadDiary();
      case _DiaryAction.savePlan:
        await saveWorkoutAsPlanFlow(
          context,
          repository: viewModel.repository,
          workout: workout,
        );
      case _DiaryAction.delete:
        await _deleteAfterConfirmation(context);
      case null:
        return;
    }
  }

  Widget _rowContent(BuildContext context, GainerColors colors) {
    final local = workout.startedAtUtc.toLocal();
    final ended = workout.endedAtUtc;
    final duration = ended == null
        ? 'läuft'
        : formatDurationMinutes(ended.difference(workout.startedAtUtc));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: editing ? null : () => onOpen(workout),
      onLongPress: editing ? null : () => _showActions(context),
      child: Padding(
        padding: const EdgeInsets.all(GainerSpacing.m),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DateBadge(local: local),
            const SizedBox(width: GainerSpacing.s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          workout.title,
                          style: GainerTypography.cardTitle.copyWith(
                            color: colors.primaryText,
                          ),
                        ),
                      ),
                      Text(
                        duration,
                        style: GainerTypography.label.copyWith(
                          color: colors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                  for (final block in workout.exercises) ...[
                    const SizedBox(height: GainerSpacing.xxs),
                    Text(
                      '${block.sets.length}x ${block.exerciseNameSnapshot}',
                      style: GainerTypography.label.copyWith(
                        color: colors.secondaryText,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateBadge extends StatelessWidget {
  const _DateBadge({required this.local});

  final DateTime local;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Container(
      width: 52,
      padding: const EdgeInsets.symmetric(vertical: GainerSpacing.xs),
      decoration: BoxDecoration(
        color: colors.elevatedSurface,
        borderRadius: BorderRadius.circular(GainerRadii.field),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formatWeekdayShort(local),
            style: GainerTypography.caption.copyWith(
              color: colors.secondaryText,
            ),
          ),
          Text(
            '${local.day}',
            style: GainerTypography.value.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.primaryText,
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool> _confirmDelete(
  BuildContext context,
  Workout workout,
) => confirmGainerDelete(
  context,
  title: 'Training löschen?',
  message:
      '„${workout.title}“ verschwindet sofort aus dem Tagebuch und wird beim nächsten Sync entfernt.',
  deleteLabel: _deleteLabel,
);
