import 'package:flutter/cupertino.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../../domain/models/training/training_schedule.dart';
import '../../core/components/components.dart';
import 'training_plans_view_model.dart';
import 'training_schedule_format.dart';

enum _MainChoice { move, skip, catchUp, continueFromToday, undo }

/// Kontext-Sheet mit den Tagesaktionen für ein geplantes Training (D7). Es
/// zeigt nur die Aktionen, die nach `training-schedule` zulässig sind; ohne
/// zulässige Aktion erscheint nichts. Jede Aktion schreibt sofort lokal.
/// Liefert true, wenn der Rhythmus geändert wurde.
Future<bool> showScheduledTrainingActions(
  BuildContext context, {
  required TrainingLogRepository repository,
  required TrainingScheduleProjection projection,
  required ScheduledTraining training,
}) async {
  final actions = projection.actionsFor(training);
  if (actions.isEmpty) return false;
  final today = projection.today;
  bool has(ScheduleActionKind kind) => actions.any((a) => a.kind == kind);
  final moves = [
    for (final action in actions)
      if (action.kind == ScheduleActionKind.shiftRhythm ||
          action.kind == ScheduleActionKind.moveSingle)
        action,
  ];

  final choice = await showGainerActionSheet<_MainChoice>(
    context: context,
    title: '${training.planName} · ${scheduleDateLabel(training.date)}',
    groups: [
      [
        if (moves.isNotEmpty)
          const GainerSheetAction(
            label: 'Verschieben…',
            icon: CupertinoIcons.arrow_right_arrow_left,
            value: _MainChoice.move,
          ),
        if (has(ScheduleActionKind.skip))
          const GainerSheetAction(
            label: 'Überspringen',
            icon: CupertinoIcons.forward_end,
            value: _MainChoice.skip,
            hint: 'Alle anderen Tage bleiben, wie sie sind.',
          ),
        if (has(ScheduleActionKind.catchUpToday))
          const GainerSheetAction(
            label: 'Heute nachholen',
            icon: CupertinoIcons.arrow_counterclockwise,
            value: _MainChoice.catchUp,
            hint: 'Nur dieses Training liegt dann auf heute.',
          ),
        if (has(ScheduleActionKind.continueFromToday))
          const GainerSheetAction(
            label: 'Ab heute weiter',
            icon: CupertinoIcons.arrow_right_circle,
            value: _MainChoice.continueFromToday,
            hint: 'Der Rhythmus rückt nach, die Tage davor sind pausiert.',
          ),
      ],
      if (has(ScheduleActionKind.undo))
        [
          GainerSheetAction(
            label: 'Aufheben',
            icon: CupertinoIcons.arrow_uturn_left,
            value: _MainChoice.undo,
            hint: training.status == ScheduledTrainingStatus.skipped
                ? 'Das Training ist wieder geplant.'
                : 'Das Training liegt wieder auf '
                      '${scheduleDayShort(training.originDate, today)}.',
          ),
        ],
    ].where((group) => group.isNotEmpty).toList(),
  );
  if (choice == null || !context.mounted) return false;

  final ScheduleAction? action = switch (choice) {
    _MainChoice.move => await _chooseMove(context, projection, training, moves),
    _MainChoice.skip => const ScheduleAction.skip(),
    _MainChoice.catchUp => const ScheduleAction.catchUpToday(),
    _MainChoice.continueFromToday => const ScheduleAction.continueFromToday(),
    _MainChoice.undo => const ScheduleAction.undo(),
  };
  if (action == null || !context.mounted) return false;

  try {
    await repository.schedule.applyAction(training, action);
    return true;
  } catch (error) {
    if (context.mounted) {
      await showGainerStackedDialog<bool>(
        context: context,
        title: 'Nicht geändert',
        message: planErrorMessage(
          error,
          'Der Rhythmus konnte nicht geändert werden.',
        ),
        actions: const [GainerDialogAction(label: 'OK', value: true)],
      );
    }
    return false;
  }
}

Future<ScheduleAction?> _chooseMove(
  BuildContext context,
  TrainingScheduleProjection projection,
  ScheduledTraining training,
  List<ScheduleAction> moves,
) {
  final today = projection.today;
  final shifts = [
    for (final action in moves)
      if (action.kind == ScheduleActionKind.shiftRhythm) action,
  ];
  final singles = [
    for (final action in moves)
      if (action.kind == ScheduleActionKind.moveSingle) action,
  ];
  String? shiftHint(int days) {
    final voided = projection.exceptionsVoidedByShift(training.date, days);
    if (voided == 0) return 'Dieses und alle folgenden Trainings rücken nach.';
    return voided == 1
        ? 'Alle folgenden rücken nach. Eine spätere Verschiebung entfällt.'
        : 'Alle folgenden rücken nach. $voided spätere Verschiebungen entfallen.';
  }

  return showGainerActionSheet<ScheduleAction>(
    context: context,
    title: 'Verschieben',
    groups: [
      if (shifts.isNotEmpty)
        [
          for (final action in shifts)
            GainerSheetAction(
              label: action.days == 1
                  ? 'Rhythmus +1 Tag'
                  : 'Rhythmus +${action.days} Tage',
              icon: CupertinoIcons.calendar_badge_plus,
              value: action,
              hint: shiftHint(action.days!),
            ),
        ],
      [
        for (final action in singles)
          GainerSheetAction(
            label:
                'Nur dieses auf ${scheduleDayShort(action.targetDate!, today)}',
            icon: CupertinoIcons.arrow_right,
            value: action,
          ),
      ],
    ],
  );
}
