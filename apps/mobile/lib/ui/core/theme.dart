import 'package:flutter/cupertino.dart';

abstract final class GainerTheme {
  // Match Gainer's blue controls and cool, neutral surfaces across the PWA
  // and native app. Keep the filled-control color dark enough for white text.
  static const _accent = Color(0xFF245EDB);
  static const _darkAccent = Color(0xFF86A9F5);

  static const actionColor = _accent;

  static Color secondaryText(BuildContext context) =>
      CupertinoTheme.of(context).brightness == Brightness.dark
      ? const Color(0xFFA5ACBC)
      : const Color(0xFF586174);

  static CupertinoThemeData forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  static const light = CupertinoThemeData(
    brightness: Brightness.light,
    primaryColor: _accent,
    scaffoldBackgroundColor: Color(0xFFF5F6FA),
    barBackgroundColor: Color(0xEBF9FAFC),
    textTheme: CupertinoTextThemeData(
      primaryColor: _accent,
      navTitleTextStyle: TextStyle(
        inherit: false,
        fontFamily: 'CupertinoSystemText',
        color: Color(0xFF171B27),
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  static const dark = CupertinoThemeData(
    brightness: Brightness.dark,
    primaryColor: _darkAccent,
    scaffoldBackgroundColor: Color(0xFF11131A),
    barBackgroundColor: Color(0xEB191C25),
    textTheme: CupertinoTextThemeData(
      primaryColor: _darkAccent,
      navTitleTextStyle: TextStyle(
        inherit: false,
        fontFamily: 'CupertinoSystemText',
        color: CupertinoColors.label,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
