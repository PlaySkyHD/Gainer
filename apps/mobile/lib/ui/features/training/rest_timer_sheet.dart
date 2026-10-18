import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../../domain/models/timer/rest_timer_state.dart';
import '../../core/components/gainer_sheet.dart';
import '../../core/components/gainer_toolbar_button.dart';
import '../../core/theme.dart';
import 'rest_timer_controller.dart';
import 'rest_timer_format.dart';
import 'rest_timer_menu.dart';
import 'rest_timer_option_sheets.dart';
import 'rest_timer_toggle_button.dart';

/// Öffnet die große Timeransicht als Sheet. X beendet den Timer und schließt das Sheet;
/// Wischen nach unten minimiert nur, der Timer läuft weiter.
Future<void> showRestTimerSheet(
  BuildContext context,
  RestTimerController controller,
) {
  // Ohne sichtbare Tastatur hat kein Feld den Fokus. Flutter stellt ihn sonst
  // nach dem Schließen wieder her und blendet die Tastatur ungefragt ein.
  if (View.of(context).viewInsets.bottom <= 0) {
    FocusManager.instance.primaryFocus?.unfocus();
  }
  return showCupertinoModalPopup<void>(
    context: context,
    builder: (_) =>
        GainerSwipeToDismiss(child: RestTimerSheet(controller: controller)),
  );
}

class RestTimerSheet extends StatefulWidget {
  const RestTimerSheet({required this.controller, super.key});

  final RestTimerController controller;

  @override
  State<RestTimerSheet> createState() => _RestTimerSheetState();
}

class _RestTimerSheetState extends State<RestTimerSheet> {
  RestTimerController get _controller => widget.controller;

  void _closeTimer() {
    unawaited(_controller.close());
    Navigator.of(context).pop();
  }

  Future<void> _openMenu(BuildContext buttonContext) async {
    final choice = await showRestTimerMenu(
      buttonContext,
      autoStart: _controller.autoStartEnabled,
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case RestTimerMenuChoice.sound:
        await showRestTimerSoundSheet(context, _controller);
      case RestTimerMenuChoice.edit:
        await showRestTimerEditSheet(context, _controller);
      case RestTimerMenuChoice.autoStart:
        await _controller.setAutoStart(!_controller.autoStartEnabled);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final controller = _controller;
        final phase = controller.phase;
        final running = phase == RestTimerPhase.running;
        final showShortcuts =
            phase == RestTimerPhase.ready || phase == RestTimerPhase.expired;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(GainerRadii.card),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                GainerSpacing.m,
                GainerSpacing.xs,
                GainerSpacing.m,
                GainerSpacing.m,
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
                  Row(
                    children: [
                      const Spacer(),
                      GainerToolbarButton(
                        icon: CupertinoIcons.xmark,
                        semanticLabel: 'Timer schließen',
                        onPressed: _closeTimer,
                      ),
                    ],
                  ),
                  _RingCountdown(
                    progress: controller.progress,
                    seconds: controller.remainingSeconds,
                  ),
                  const SizedBox(height: GainerSpacing.l),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CupertinoButton(
                        onPressed: () =>
                            controller.adjust(-restTimerAdjustStepSeconds),
                        child: Text(
                          '−15s',
                          style: GainerTypography.body.copyWith(
                            color: colors.accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: GainerSpacing.l),
                      RestTimerToggleButton(
                        running: running,
                        diameter: 80,
                        onPressed: () =>
                            running ? controller.stop() : controller.start(),
                      ),
                      const SizedBox(width: GainerSpacing.l),
                      CupertinoButton(
                        onPressed: () =>
                            controller.adjust(restTimerAdjustStepSeconds),
                        child: Text(
                          '+15s',
                          style: GainerTypography.body.copyWith(
                            color: colors.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: GainerSpacing.l),
                  Container(height: 1, color: colors.separator),
                  const SizedBox(height: GainerSpacing.m),
                  Row(
                    children: [
                      Text(
                        'Timer',
                        style: GainerTypography.title.copyWith(
                          color: colors.primaryText,
                        ),
                      ),
                      const Spacer(),
                      Builder(
                        builder: (buttonContext) => GainerToolbarButton(
                          icon: CupertinoIcons.ellipsis,
                          semanticLabel: 'Timer-Optionen',
                          onPressed: () => _openMenu(buttonContext),
                        ),
                      ),
                    ],
                  ),
                  if (showShortcuts) ...[
                    const SizedBox(height: GainerSpacing.s),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: GainerSpacing.s,
                      runSpacing: GainerSpacing.s,
                      children: [
                        _ShortcutChip(
                          semanticLabel: 'Shortcut hinzufügen',
                          onPressed: () =>
                              addRestTimerShortcut(context, controller),
                          child: Icon(
                            CupertinoIcons.plus,
                            size: 18,
                            color: colors.accent,
                          ),
                        ),
                        for (final seconds in controller.shortcuts.seconds)
                          _ShortcutChip(
                            semanticLabel:
                                'Timer auf ${formatRestTimerCountdown(seconds)}',
                            onPressed: () => controller.startShortcut(seconds),
                            child: Text(
                              formatRestTimerCountdown(seconds),
                              style: GainerTypography.timer.copyWith(
                                color: colors.accent,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Kleine Pille der Shortcut-Zeile.
class _ShortcutChip extends StatelessWidget {
  const _ShortcutChip({
    required this.semanticLabel,
    required this.onPressed,
    required this.child,
  });

  final String semanticLabel;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: GainerSpacing.m),
        minimumSize: const Size(52, 40),
        color: colors.elevatedSurface,
        borderRadius: GainerRadii.pill,
        onPressed: onPressed,
        child: child,
      ),
    );
  }
}

class _RingCountdown extends StatelessWidget {
  const _RingCountdown({required this.progress, required this.seconds});

  static const double _diameter = 240;

  final double progress;
  final int seconds;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Semantics(
      label: 'Pausenzeit ${formatRestTimerCountdown(seconds)}',
      child: SizedBox.square(
        dimension: _diameter,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: const Size.square(_diameter),
              painter: _RingPainter(
                progress: progress,
                track: colors.separator,
                color: colors.accent,
              ),
            ),
            Text(
              formatRestTimerCountdown(seconds),
              style: GainerTypography.timer.copyWith(
                fontSize: 56,
                color: colors.primaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.track,
    required this.color,
  });

  static const double _strokeWidth = 10;

  final double progress;
  final Color track;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final arc = Offset.zero & size;
    final bounds = arc.deflate(_strokeWidth / 2);
    canvas.drawArc(
      bounds,
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth
        ..color = track,
    );
    if (progress <= 0) return;
    canvas.drawArc(
      bounds,
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = _strokeWidth
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      track != oldDelegate.track ||
      color != oldDelegate.color;
}
