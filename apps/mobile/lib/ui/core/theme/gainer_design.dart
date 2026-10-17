import 'package:flutter/cupertino.dart';

import 'gainer_colors.dart';

/// Stellt die Farbrollen passend zur aktuellen System-Helligkeit bereit.
/// Ohne Vorfahr-Widget leitet `colorsOf` die Rollen aus dem `CupertinoTheme` ab.
class GainerDesign extends StatelessWidget {
  const GainerDesign({required this.child, super.key});

  final Widget child;

  static GainerColors colorsOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_GainerDesignScope>();
    if (scope != null) return scope.colors;
    return GainerColors.forBrightness(
      CupertinoTheme.of(context).brightness ?? Brightness.light,
    );
  }

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    return _GainerDesignScope(
      colors: GainerColors.forBrightness(brightness),
      child: child,
    );
  }
}

class _GainerDesignScope extends InheritedWidget {
  const _GainerDesignScope({required this.colors, required super.child});

  final GainerColors colors;

  @override
  bool updateShouldNotify(_GainerDesignScope oldWidget) =>
      colors != oldWidget.colors;
}
