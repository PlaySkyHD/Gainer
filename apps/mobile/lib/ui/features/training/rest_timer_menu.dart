import 'package:flutter/cupertino.dart';

import '../../core/theme.dart';

enum RestTimerMenuChoice { sound, edit, autoStart }

/// Öffnet das kompakte Menü des „…“-Buttons. Es erscheint über dem Button,
/// rechtsbündig mit ihm, und liefert die gewählte Aktion. [autoStart] zeigt
/// den Zustand der Checkbox.
Future<RestTimerMenuChoice?> showRestTimerMenu(
  BuildContext buttonContext, {
  required bool autoStart,
}) {
  final box = buttonContext.findRenderObject()! as RenderBox;
  final anchor = box.localToGlobal(Offset.zero) & box.size;
  return showGeneralDialog<RestTimerMenuChoice>(
    context: buttonContext,
    barrierDismissible: true,
    barrierLabel: 'Menü schließen',
    barrierColor: CupertinoColors.transparent,
    transitionDuration: const Duration(milliseconds: 120),
    transitionBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
    pageBuilder: (context, _, _) =>
        _RestTimerMenu(anchor: anchor, autoStart: autoStart),
  );
}

class _RestTimerMenu extends StatelessWidget {
  const _RestTimerMenu({required this.anchor, required this.autoStart});

  static const double _width = 250;

  final Rect anchor;
  final bool autoStart;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final screen = MediaQuery.sizeOf(context);
    return Stack(
      children: [
        Positioned(
          right: screen.width - anchor.right,
          bottom: screen.height - anchor.top + GainerSpacing.xs,
          width: _width,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.elevatedSurface,
              borderRadius: BorderRadius.circular(GainerRadii.field),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MenuRow(
                  icon: CupertinoIcons.speaker_2,
                  label: 'Timersound',
                  onTap: () =>
                      Navigator.of(context).pop(RestTimerMenuChoice.sound),
                ),
                _MenuRow(
                  icon: CupertinoIcons.pencil,
                  label: 'Timer bearbeiten',
                  onTap: () =>
                      Navigator.of(context).pop(RestTimerMenuChoice.edit),
                ),
                Container(height: 0.5, color: colors.separator),
                _MenuRow(
                  icon: autoStart
                      ? CupertinoIcons.checkmark_square_fill
                      : CupertinoIcons.square,
                  label: 'Timer automatisch starten',
                  checked: autoStart,
                  onTap: () =>
                      Navigator.of(context).pop(RestTimerMenuChoice.autoStart),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.checked,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Nur für Zeilen mit Checkbox; sonst null.
  final bool? checked;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Semantics(
      button: true,
      checked: checked,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: GainerSpacing.s,
              vertical: GainerSpacing.xs,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: checked == true ? colors.accent : colors.primaryText,
                ),
                const SizedBox(width: GainerSpacing.s),
                Expanded(
                  child: Text(
                    label,
                    style: GainerTypography.body.copyWith(
                      color: colors.primaryText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
