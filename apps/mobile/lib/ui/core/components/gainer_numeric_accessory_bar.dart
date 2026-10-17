import 'package:flutter/cupertino.dart';

import '../theme.dart';

/// Leiste über der Ziffernblock-Tastatur für Fokuswechsel zwischen Satzfeldern.
/// Ein fehlender Callback deaktiviert den zugehörigen Button.
class GainerNumericAccessoryBar extends StatelessWidget {
  const GainerNumericAccessoryBar({
    this.onPrevious,
    this.onNext,
    this.onDone,
    this.onHideKeyboard,
    super.key,
  });

  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onDone;
  final VoidCallback? onHideKeyboard;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.separator, width: 0.5)),
      ),
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: GainerSpacing.xs),
          child: Row(
            children: [
              _AccessoryButton(
                icon: CupertinoIcons.chevron_up,
                label: 'Zurück',
                onPressed: onPrevious,
              ),
              _AccessoryButton(
                icon: CupertinoIcons.chevron_down,
                label: 'Weiter',
                onPressed: onNext,
              ),
              const Spacer(),
              _AccessoryButton(
                icon: CupertinoIcons.checkmark,
                label: 'Fertig',
                onPressed: onDone,
              ),
              _AccessoryButton(
                icon: CupertinoIcons.keyboard_chevron_compact_down,
                label: 'Tastatur ausblenden',
                onPressed: onHideKeyboard,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccessoryButton extends StatelessWidget {
  const _AccessoryButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: CupertinoButton(
        minimumSize: const Size.square(44),
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        child: Icon(
          icon,
          size: 22,
          color: enabled ? colors.accent : colors.placeholderText,
        ),
      ),
    );
  }
}
