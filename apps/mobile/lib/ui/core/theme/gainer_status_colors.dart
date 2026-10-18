import 'package:flutter/cupertino.dart';

/// Statusfarben, die die Rollenpalette nicht kennt: „in Ordnung“ (Grün) und
/// „zu niedrig“ (Blau), etwa für den Zielbereich beim Cardio.
abstract final class GainerStatusColors {
  static Color success(Brightness brightness) => brightness == Brightness.dark
      ? const Color(0xFF30D158)
      : const Color(0xFF1E9E45);

  static Color info(Brightness brightness) => brightness == Brightness.dark
      ? const Color(0xFF64D2FF)
      : const Color(0xFF0A74D6);
}
