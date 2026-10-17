import 'package:flutter/cupertino.dart';

/// Farbrollen der App. Widgets lesen nur Rollen, nie Hex-Werte.
@immutable
final class GainerColors {
  const GainerColors({
    required this.background,
    required this.surface,
    required this.elevatedSurface,
    required this.separator,
    required this.primaryText,
    required this.secondaryText,
    required this.placeholderText,
    required this.accent,
    required this.onAccent,
    required this.warning,
    required this.destructive,
  });

  final Color background;
  final Color surface;
  final Color elevatedSurface;
  final Color separator;
  final Color primaryText;
  final Color secondaryText;
  final Color placeholderText;
  final Color accent;
  final Color onAccent;
  final Color warning;
  final Color destructive;

  static const dark = GainerColors(
    background: Color(0xFF000000),
    surface: Color(0xFF1C1C1E),
    elevatedSurface: Color(0xFF2C2C2E),
    separator: Color(0xFF38383A),
    primaryText: Color(0xFFFFFFFF),
    secondaryText: Color(0xFFA1A1A6),
    placeholderText: Color(0xFF5E5E63),
    accent: Color(0xFF54D9E6),
    onAccent: Color(0xFF00363B),
    warning: Color(0xFFFFA400),
    destructive: Color(0xFFFF453A),
  );

  static const light = GainerColors(
    background: Color(0xFFF2F2F7),
    surface: Color(0xFFFFFFFF),
    elevatedSurface: Color(0xFFE9EFF0),
    separator: Color(0xFFD8DEDF),
    primaryText: Color(0xFF191C1D),
    secondaryText: Color(0xFF5F6869),
    placeholderText: Color(0xFFB4BCBD),
    accent: Color(0xFF00828D),
    onAccent: Color(0xFFFFFFFF),
    warning: Color(0xFFE9651F),
    destructive: Color(0xFFDD2C00),
  );

  static GainerColors forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}
