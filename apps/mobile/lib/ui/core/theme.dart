import 'package:flutter/cupertino.dart';

abstract final class GainerTheme {
  static const _accent = Color(0xFF366B58);

  static CupertinoThemeData forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  static const light = CupertinoThemeData(
    brightness: Brightness.light,
    primaryColor: _accent,
    scaffoldBackgroundColor: Color(0xFFF5F6F3),
    barBackgroundColor: Color(0xFFF8F8F6),
    textTheme: CupertinoTextThemeData(
      primaryColor: _accent,
      navTitleTextStyle: TextStyle(
        color: Color(0xFF171C19),
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  static const dark = CupertinoThemeData(
    brightness: Brightness.dark,
    primaryColor: Color(0xFF8CC7AA),
    scaffoldBackgroundColor: Color(0xFF111613),
    barBackgroundColor: Color(0xFF191F1B),
    textTheme: CupertinoTextThemeData(
      primaryColor: Color(0xFF8CC7AA),
      navTitleTextStyle: TextStyle(
        color: CupertinoColors.label,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
