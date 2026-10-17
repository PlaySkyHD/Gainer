import 'package:flutter/cupertino.dart';

import '../../core/theme.dart';

/// Runder Start/Stopp-Button des Pausentimers. Laufend zeigt er orange mit
/// Stopp-Symbol, sonst in Akzentfarbe mit Start-Symbol.
class RestTimerToggleButton extends StatelessWidget {
  const RestTimerToggleButton({
    required this.running,
    required this.onPressed,
    this.diameter = GainerRadii.iconButtonDiameter,
    super.key,
  });

  final bool running;
  final VoidCallback onPressed;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final background = running ? colors.warning : colors.accent;
    return Semantics(
      button: true,
      label: running ? 'Pause stoppen' : 'Pause starten',
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.square(diameter),
        color: background,
        borderRadius: GainerRadii.pill,
        onPressed: onPressed,
        child: Icon(
          running ? CupertinoIcons.stop_fill : CupertinoIcons.play_fill,
          size: diameter * 0.42,
          color: colors.onAccent,
        ),
      ),
    );
  }
}
