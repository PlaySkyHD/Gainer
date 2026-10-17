import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../../domain/models/training/workout_model.dart';
import '../../core/theme.dart';
import 'active_workout_controller.dart';
import 'training_format.dart';
import 'workout_screen.dart';

/// Kompakte Leiste über der Tableiste, solange ein Training minimiert läuft.
/// Die Zeit kommt aus `startedAtUtc`, nicht aus einem eigenen Zähler.
class CompactTrainingBar extends StatelessWidget {
  const CompactTrainingBar({
    required this.activeWorkout,
    required this.repository,
    super.key,
  });

  final ActiveWorkoutController activeWorkout;
  final TrainingLogRepository repository;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: activeWorkout,
      builder: (context, _) {
        final workout = activeWorkout.active;
        if (workout == null) return const SizedBox.shrink();
        return Padding(
          key: const ValueKey('compact-training-bar'),
          padding: const EdgeInsets.only(bottom: GainerSpacing.xs),
          child: _BarBody(
            workout: workout,
            onOpen: () => openWorkoutScreen(
              context,
              repository: repository,
              activeWorkout: activeWorkout,
              workoutId: workout.workoutId,
            ),
          ),
        );
      },
    );
  }
}

class _BarBody extends StatefulWidget {
  const _BarBody({required this.workout, required this.onOpen});

  final Workout workout;
  final VoidCallback onOpen;

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
    final elapsed = DateTime.now().toUtc().difference(
      widget.workout.startedAtUtc,
    );
    final time = formatElapsed(elapsed);
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
