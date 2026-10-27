import 'package:flutter/cupertino.dart';

import '../../../domain/models/training/training_schedule.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'training_schedule_format.dart';

/// Karte „Heute“ nach `training-schedule` („Heutiges Training im
/// Trainings-Tab“): geplantes Training mit „Starten“, erledigt, Ruhetag mit
/// dem nächsten Training oder „Rhythmus einrichten“. Langes Drücken öffnet
/// die Tagesaktionen über [onActions].
class TrainingTodayCard extends StatelessWidget {
  const TrainingTodayCard({
    required this.projection,
    required this.onStart,
    required this.onSetup,
    required this.onActions,
    super.key,
  });

  final TrainingScheduleProjection projection;

  /// Startet ein Training aus dem Plan wie aus der Planliste.
  final ValueChanged<String> onStart;
  final VoidCallback onSetup;

  /// Tagesaktionen für ein Training von heute.
  final ValueChanged<ScheduledTraining> onActions;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    if (projection.schedule == null) return _setup(colors);

    final today = projection.today;
    final day = projection.day(today);
    final open = [
      for (final training in day.trainings)
        if (training.isOpen) training,
    ];
    final done = [
      for (final training in day.trainings)
        if (training.status == ScheduledTrainingStatus.done) training,
    ];
    final away = [
      for (final training in day.trainings)
        if (training.status == ScheduledTrainingStatus.moved ||
            training.status == ScheduledTrainingStatus.skipped)
          training,
    ];
    final actionable = [
      for (final training in day.trainings)
        if (projection.actionsFor(training).isNotEmpty) training,
    ];

    final (:title, :lines) = _headline(open, done, away);

    return Semantics(
      container: true,
      hint: actionable.isEmpty ? null : 'Lange drücken für Tagesaktionen',
      child: GestureDetector(
        key: const ValueKey('training-today-card'),
        behavior: HitTestBehavior.opaque,
        onLongPress: actionable.isEmpty
            ? null
            : () => _openActions(context, actionable),
        child: GainerCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (open.isEmpty && done.isNotEmpty) ...[
                    Icon(
                      CupertinoIcons.checkmark_circle_fill,
                      size: 22,
                      color: colors.accent,
                    ),
                    const SizedBox(width: GainerSpacing.xs),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      style: GainerTypography.cardTitle.copyWith(
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                ],
              ),
              for (final line in lines) ...[
                const SizedBox(height: GainerSpacing.xxs),
                Text(
                  line,
                  style: GainerTypography.label.copyWith(
                    color: colors.secondaryText,
                  ),
                ),
              ],
              if (open.isNotEmpty) ...[
                const SizedBox(height: GainerSpacing.s),
                GainerPillButton(
                  key: const ValueKey('training-today-start'),
                  label: 'Starten',
                  icon: CupertinoIcons.play_fill,
                  expand: true,
                  onPressed: () => onStart(open.first.planId),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Titel und Zusatzzeilen der Karte je nach Stand von heute.
  ({String title, List<String> lines}) _headline(
    List<ScheduledTraining> open,
    List<ScheduledTraining> done,
    List<ScheduledTraining> away,
  ) {
    final today = projection.today;
    final String title;
    final lines = <String>[];
    if (open.isNotEmpty) {
      title = 'Heute: ${open.first.planName}';
      if (open.length > 1) {
        lines.add('Danach: ${open.skip(1).map((t) => t.planName).join(', ')}');
      }
      if (done.isNotEmpty) {
        lines.add('Erledigt: ${done.map((t) => t.planName).join(', ')}');
      }
    } else if (done.isNotEmpty) {
      title = 'Heute erledigt: ${done.map((t) => t.planName).join(', ')}';
    } else {
      title = _restTitle();
    }
    for (final training in away) {
      lines.add(
        '${training.planName}: ${scheduledStatusLabel(training, today)}',
      );
    }
    return (title: title, lines: lines);
  }

  String _restTitle() {
    final today = projection.today;
    final next = projection.nextPlannedAfter(today);
    if (next == null) return 'Ruhetag';
    return 'Ruhetag · Nächstes: ${next.planName} am '
        '${scheduleDayShort(next.date, today)}';
  }

  Future<void> _openActions(
    BuildContext context,
    List<ScheduledTraining> actionable,
  ) async {
    if (actionable.length == 1) {
      onActions(actionable.single);
      return;
    }
    final chosen = await showGainerActionSheet<ScheduledTraining>(
      context: context,
      title: 'Heute',
      groups: [
        [
          for (final training in actionable)
            GainerSheetAction(
              label: training.planName,
              icon: CupertinoIcons.flame,
              value: training,
              hint: scheduledStatusLabel(training, projection.today),
            ),
        ],
      ],
    );
    if (chosen != null) onActions(chosen);
  }

  Widget _setup(GainerColors colors) {
    return GainerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Heute',
            style: GainerTypography.cardTitle.copyWith(
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: GainerSpacing.xxs),
          Text(
            'Lege fest, an welchen Tagen du welchen Plan trainierst.',
            style: GainerTypography.label.copyWith(color: colors.secondaryText),
          ),
          const SizedBox(height: GainerSpacing.s),
          GainerPillButton(
            key: const ValueKey('training-today-setup'),
            label: 'Rhythmus einrichten',
            icon: CupertinoIcons.calendar,
            variant: GainerPillVariant.tonal,
            expand: true,
            onPressed: onSetup,
          ),
        ],
      ),
    );
  }
}
