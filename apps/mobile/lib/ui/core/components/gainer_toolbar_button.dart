import 'package:flutter/cupertino.dart';

import '../theme.dart';

/// Eine Aktion für Toolbar-Buttons; `semanticLabel` ist Pflicht, weil Icons allein nicht sprechen.
final class GainerToolbarAction {
  const GainerToolbarAction({
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;
}

/// Runder Icon-Button (44 pt) auf erhöhter Fläche für Seitenaktionen.
class GainerToolbarButton extends StatelessWidget {
  const GainerToolbarButton({
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return _toolbarIcon(
      action: GainerToolbarAction(
        icon: icon,
        semanticLabel: semanticLabel,
        onPressed: onPressed,
      ),
      background: colors.elevatedSurface,
      radius: BorderRadius.circular(GainerRadii.iconButtonDiameter / 2),
      colors: colors,
    );
  }
}

/// Mehrere Icon-Buttons in einer gemeinsamen Pille.
class GainerToolbarGroup extends StatelessWidget {
  const GainerToolbarGroup({required this.actions, super.key});

  final List<GainerToolbarAction> actions;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.elevatedSurface,
        borderRadius: GainerRadii.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final action in actions)
            _toolbarIcon(
              action: action,
              background: null,
              radius: BorderRadius.circular(GainerRadii.iconButtonDiameter / 2),
              colors: colors,
            ),
        ],
      ),
    );
  }
}

Widget _toolbarIcon({
  required GainerToolbarAction action,
  required Color? background,
  required BorderRadius radius,
  required GainerColors colors,
}) {
  final enabled = action.onPressed != null;
  return Semantics(
    button: true,
    enabled: enabled,
    label: action.semanticLabel,
    excludeSemantics: true,
    child: CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size.square(GainerRadii.iconButtonDiameter),
      color: background,
      disabledColor: background ?? CupertinoColors.transparent,
      borderRadius: radius,
      onPressed: action.onPressed,
      child: Icon(
        action.icon,
        size: 22,
        color: enabled ? colors.primaryText : colors.placeholderText,
      ),
    ),
  );
}
