import 'package:flutter/cupertino.dart';

import 'theme/gainer_colors.dart';
import 'theme/gainer_design.dart';
import 'theme/gainer_typography.dart';

export 'theme/gainer_colors.dart';
export 'theme/gainer_design.dart';
export 'theme/gainer_metrics.dart';
export 'theme/gainer_status_colors.dart';
export 'theme/gainer_typography.dart';

/// Übergangs-API für bestehende Screens. Neue Widgets lesen direkt
/// `GainerDesign.colorsOf(context)`.
abstract final class GainerTheme {
  static Color secondaryText(BuildContext context) =>
      GainerDesign.colorsOf(context).secondaryText;

  static Color actionColor(BuildContext context) =>
      GainerDesign.colorsOf(context).accent;

  static CupertinoThemeData forBrightness(Brightness brightness) =>
      _themeFor(GainerColors.forBrightness(brightness), brightness);

  static final light = forBrightness(Brightness.light);
  static final dark = forBrightness(Brightness.dark);

  static CupertinoThemeData _themeFor(
    GainerColors colors,
    Brightness brightness,
  ) => CupertinoThemeData(
    brightness: brightness,
    primaryColor: colors.accent,
    primaryContrastingColor: colors.onAccent,
    scaffoldBackgroundColor: colors.background,
    barBackgroundColor: colors.background,
    textTheme: CupertinoTextThemeData(
      primaryColor: colors.accent,
      textStyle: GainerTypography.body.copyWith(color: colors.primaryText),
      navTitleTextStyle: GainerTypography.title.copyWith(
        color: colors.primaryText,
      ),
      actionTextStyle: GainerTypography.body.copyWith(color: colors.accent),
    ),
  );
}
