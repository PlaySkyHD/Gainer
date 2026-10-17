import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../../domain/models/timer/rest_timer_state.dart';
import '../../../domain/models/training/workout_model.dart';
import '../../core/theme.dart';
import 'active_workout_controller.dart';
import 'rest_timer_controller.dart';
import 'rest_timer_format.dart';
import 'training_format.dart';
import 'workout_screen.dart';

/// Kompakte Leiste über der Tableiste, solange ein Training minimiert läuft.
/// Die Trainingszeit kommt aus `startedAtUtc`, nicht aus einem eigenen Zähler.
/// Läuft eine Pause, steht die Restzeit daneben; sie kommt aus demselben
/// Pausentimer wie in der Timeransicht.
class CompactTrainingBar extends StatelessWidget {
  const CompactTrainingBar({
    required this.activeWorkout,
    required this.repository,
    this.clock = _systemNow,
    super.key,
  });

  final ActiveWorkoutController activeWorkout;
  final TrainingLogRepository repository;

  /// Source of the current time; injectable so tests render a stable elapsed time.
  final DateTime Function() clock;

  static DateTime _systemNow() => DateTime.now();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: activeWorkout,
      builder: (context, _) {
        final workout = activeWorkout.active;
        if (workout == null) return const SizedBox.shrink();
        final timer = activeWorkout.restTimer;
        void open() => openWorkoutScreen(
          context,
          repository: repository,
          activeWorkout: activeWorkout,
          workoutId: workout.workoutId,
        );
        return Padding(
          key: const ValueKey('compact-training-bar'),
          padding: const EdgeInsets.only(bottom: GainerSpacing.xs),
          child: timer == null
              ? _BarBody(
                  workout: workout,
                  timer: null,
                  onOpen: open,
                  clock: clock,
                )
              : ListenableBuilder(
                  listenable: timer,
                  builder: (context, _) => _BarBody(
                    workout: workout,
                    timer: timer,
                    onOpen: open,
                    clock: clock,
                  ),
                ),
        );
      },
    );
  }
}

class _BarBody extends StatefulWidget {
  const _BarBody({
    required this.workout,
    required this.timer,
    required this.onOpen,
    required this.clock,
  });

  final Workout workout;
  final RestTimerController? timer;
  final VoidCallback onOpen;
  final DateTime Function() clock;

  @override
  State<_BarBody> createState() => _BarBodyState();
}

class _BarBodyState extends State<_BarBody> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final elapsed = widget.clock().toUtc().difference(
      widget.workout.startedAtUtc,
    );
    final time = formatElapsed(elapsed);
    final timer = widget.timer;
    final rest = timer != null && timer.workoutId == widget.workout.workoutId
        ? timer
        : null;
    final showsRest =
        rest != null &&
        (rest.phase == RestTimerPhase.running ||
            rest.phase == RestTimerPhase.paused ||
            rest.phase == RestTimerPhase.expired);
    return Semantics(
      button: true,
      label: '${widget.workout.title}, Trainingszeit $time, öffnen',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onOpen,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(GainerRadii.card),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: GainerSpacing.m,
              vertical: GainerSpacing.s,
            ),
            child: Row(
              children: [
                Icon(CupertinoIcons.timer, size: 20, color: colors.accent),
                const SizedBox(width: GainerSpacing.s),
                Expanded(
                  child: Text(
                    widget.workout.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GainerTypography.cardTitle.copyWith(
                      color: colors.primaryText,
                    ),
                  ),
                ),
                if (showsRest) ...[
                  Text(
                    formatRestTimerCountdown(rest.remainingSeconds),
                    style: GainerTypography.timer.copyWith(
                      color: rest.phase == RestTimerPhase.expired
                          ? colors.accent
                          : colors.warning,
                    ),
                  ),
                  const SizedBox(width: GainerSpacing.s),
                ],
                Text(
                  time,
                  style: GainerTypography.timer.copyWith(
                    color: colors.primaryText,
                  ),
                ),
                const SizedBox(width: GainerSpacing.xs),
                Icon(
                  CupertinoIcons.chevron_up,
                  size: 16,
                  color: colors.secondaryText,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
