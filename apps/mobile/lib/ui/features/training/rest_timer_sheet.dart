import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../../domain/models/timer/rest_timer_state.dart';
import '../../core/components/gainer_sheet.dart';
import '../../core/components/gainer_toolbar_button.dart';
import '../../core/theme.dart';
import 'rest_timer_controller.dart';
import 'rest_timer_format.dart';
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
  var _editingShortcuts = false;

  RestTimerController get _controller => widget.controller;

  void _closeTimer() {
    unawaited(_controller.close());
    Navigator.of(context).pop();
  }

  Future<void> _addShortcut() async {
    final picked = await showCupertinoModalPopup<Duration>(
      context: context,
      builder: (_) => const _DurationPickerSheet(),
    );
    if (picked == null) return;
    await _controller.addShortcut(_clampShortcut(picked.inSeconds));
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
        final idle = phase == RestTimerPhase.ready;
        final selected = idle ? controller.state.baseDurationSeconds : null;
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
                      GainerToolbarButton(
                        icon: CupertinoIcons.ellipsis,
                        semanticLabel: 'Shortcuts bearbeiten',
                        onPressed: () => setState(
                          () => _editingShortcuts = !_editingShortcuts,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: GainerSpacing.s),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: GainerSpacing.s,
                    runSpacing: GainerSpacing.s,
                    children: [
                      for (final seconds in controller.shortcuts.seconds)
                        _ShortcutButton(
                          seconds: seconds,
                          selected: seconds == selected,
                          editing: _editingShortcuts,
                          onPressed: _editingShortcuts
                              ? () => controller.removeShortcut(seconds)
                              : () => controller.selectShortcut(seconds),
                        ),
                      _AddShortcutButton(onPressed: _addShortcut),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

int _clampShortcut(int seconds) {
  if (seconds < restTimerMinSeconds) return restTimerMinSeconds;
  if (seconds > restTimerMaxSeconds) return restTimerMaxSeconds;
  return seconds;
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

class _ShortcutButton extends StatelessWidget {
  const _ShortcutButton({
    required this.seconds,
    required this.selected,
    required this.editing,
    required this.onPressed,
  });

  static const double _diameter = 64;

  final int seconds;
  final bool selected;
  final bool editing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final label = formatRestTimerCountdown(seconds);
    return Semantics(
      button: true,
      label: editing ? '$label löschen' : 'Timer auf $label',
      selected: selected,
      child: SizedBox.square(
        dimension: _diameter + 6,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              top: 6,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size.square(_diameter),
                color: selected ? colors.accent : colors.elevatedSurface,
                borderRadius: GainerRadii.pill,
                onPressed: onPressed,
                child: Text(
                  label,
                  style: GainerTypography.timer.copyWith(
                    color: selected ? colors.onAccent : colors.accent,
                  ),
                ),
              ),
            ),
            if (editing)
              Positioned(
                right: 0,
                top: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.destructive,
                    shape: BoxShape.circle,
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(3),
                    child: Icon(
                      CupertinoIcons.minus,
                      size: 12,
                      color: CupertinoColors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddShortcutButton extends StatelessWidget {
  const _AddShortcutButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Semantics(
      button: true,
      label: 'Shortcut hinzufügen',
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size.square(64),
        color: colors.elevatedSurface,
        borderRadius: GainerRadii.pill,
        onPressed: onPressed,
        child: Icon(CupertinoIcons.plus, color: colors.accent),
      ),
    );
  }
}

/// Dauerwähler für neue Shortcuts im Bereich 5 s bis 30 min.
class _DurationPickerSheet extends StatefulWidget {
  const _DurationPickerSheet();

  @override
  State<_DurationPickerSheet> createState() => _DurationPickerSheetState();
}

class _DurationPickerSheetState extends State<_DurationPickerSheet> {
  var _value = const Duration(minutes: 3);

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(GainerRadii.card),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 320,
          child: Column(
            children: [
              Row(
                children: [
                  CupertinoButton(
                    child: const Text('Abbrechen'),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  CupertinoButton(
                    child: const Text('Fertig'),
                    onPressed: () => Navigator.of(context).pop(_value),
                  ),
                ],
              ),
              Expanded(
                child: CupertinoTimerPicker(
                  mode: CupertinoTimerPickerMode.ms,
                  initialTimerDuration: _value,
                  minuteInterval: 1,
                  secondInterval: 5,
                  onTimerDurationChanged: (value) => _value = value,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
