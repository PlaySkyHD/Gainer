import 'package:flutter/cupertino.dart';

abstract final class GainerRadii {
  static const double card = 20;
  static const double field = 14;
  static const double iconButtonDiameter = 44;

  /// Pillenform für Buttons und Toolbar-Aktionen, unabhängig von der Höhe.
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
}

abstract final class GainerSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double s = 12;
  static const double m = 16;
  static const double l = 24;
}
