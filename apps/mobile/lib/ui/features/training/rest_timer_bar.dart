import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../../../domain/models/timer/rest_timer_state.dart';
import '../../core/components/gainer_toolbar_button.dart';
import '../../core/theme.dart';
import 'rest_timer_controller.dart';
import 'rest_timer_format.dart';
import 'rest_timer_sheet.dart';
import 'rest_timer_toggle_button.dart';
import 'training_format.dart';

/// Seite der Trainingszeit in der Leiste, solange kein Pausentimer aktiv ist.
enum RestTimerTrainingTimeSide { left, right }

/// Kompakte Pausenleiste am unteren Rand des Trainings. Antippen oder
/// Hochziehen öffnet [showRestTimerSheet]. Die Leiste ist nur Widget: Platzierung
/// über der Zahlentastatur übernimmt der Workout-Screen.
class RestTimerBar extends StatefulWidget {
  const RestTimerBar({
    required this.controller,
    this.trainingStartedAtUtc,
    this.trainingTimeSide = RestTimerTrainingTimeSide.left,
    super.key,
  });

  final RestTimerController controller;

  /// Startzeit des Trainings. Ohne Wert zeigt die Leiste keine Trainingszeit.
  final DateTime? trainingStartedAtUtc;

  /// Ob die Trainingszeit links oder rechts neben dem Countdown steht.
  final RestTimerTrainingTimeSide trainingTimeSide;

  @override
  State<RestTimerBar> createState() => _RestTimerBarState();
}

class _RestTimerBarState extends State<RestTimerBar> {
  Timer? _clockTicker;

  @override
  void initState() {
    super.initState();
    _syncClockTicker();
  }

  @override
  void didUpdateWidget(RestTimerBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncClockTicker();
  }

  @override
  void dispose() {
    _clockTicker?.cancel();
    super.dispose();
  }

  /// Die Trainingszeit zählt sichtbar weiter, auch ohne laufenden Timer.
  void _syncClockTicker() {
    if (widget.trainingStartedAtUtc == null) {
      _clockTicker?.cancel();
      _clockTicker = null;
    } else {
      _clockTicker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  void _open() => showRestTimerSheet(context, widget.controller);

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final controller = widget.controller;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _open,
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) < -200) _open();
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(GainerRadii.card),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            GainerSpacing.m,
            GainerSpacing.xs,
            GainerSpacing.m,
            GainerSpacing.s,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                  color: colors.separator,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: GainerSpacing.xs),
              AnimatedBuilder(
                animation: controller,
                builder: (context, _) => _buildRow(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final controller = widget.controller;
    final phase = controller.phase;
    final running = phase == RestTimerPhase.running;
    final startedAt = widget.trainingStartedAtUtc;
    final trainingTime = startedAt != null && phase == RestTimerPhase.ready
        ? Text(
            formatElapsed(controller.now.toUtc().difference(startedAt.toUtc())),
            style: GainerTypography.timer.copyWith(color: colors.secondaryText),
          )
        : null;
    final toggle = RestTimerToggleButton(
      running: running,
      onPressed: () => running ? controller.stop() : controller.start(),
    );
    final countdown = Text(
      formatRestTimerCountdown(controller.remainingSeconds),
      textAlign: TextAlign.center,
      style: GainerTypography.timer.copyWith(
        fontSize: 24,
        color: phase == RestTimerPhase.expired
            ? colors.accent
            : colors.primaryText,
      ),
    );
    final close = GainerToolbarButton(
      icon: CupertinoIcons.xmark,
      semanticLabel: 'Timer schließen',
      onPressed: () => controller.close(),
    );
    final leading =
        trainingTime != null &&
            widget.trainingTimeSide == RestTimerTrainingTimeSide.left
        ? trainingTime
        : null;
    final trailing =
        trainingTime != null &&
            widget.trainingTimeSide == RestTimerTrainingTimeSide.right
        ? trainingTime
        : null;
    return Row(
      children: [
        if (leading != null) ...[
          leading,
          const SizedBox(width: GainerSpacing.xs),
        ],
        toggle,
        Expanded(child: Center(child: countdown)),
        if (trailing != null) ...[
          const SizedBox(width: GainerSpacing.xs),
          trailing,
        ],
        const SizedBox(width: GainerSpacing.xs),
        close,
      ],
    );
  }
}
