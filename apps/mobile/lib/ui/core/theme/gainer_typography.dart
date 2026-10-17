import 'package:flutter/cupertino.dart';

/// Schriftrollen ohne Farbe; die Farbe kommt aus `GainerColors`.
/// Größen sind logische Pixel und werden von Dynamic Type skaliert.
/// Gleiche Basis wie die Cupertino-Standardstile, damit Themenwechsel animierbar bleiben.
const _systemFont = 'CupertinoSystemText';

abstract final class GainerTypography {
  static const largeTitle = TextStyle(
    inherit: false,
    fontFamily: _systemFont,
    fontSize: 34,
    fontWeight: FontWeight.w700,
  );
  static const title = TextStyle(
    inherit: false,
    fontFamily: _systemFont,
    fontSize: 17,
    fontWeight: FontWeight.w600,
  );
  static const cardTitle = TextStyle(
    inherit: false,
    fontFamily: _systemFont,
    fontSize: 17,
    fontWeight: FontWeight.w600,
  );
  static const body = TextStyle(
    inherit: false,
    fontFamily: _systemFont,
    fontSize: 17,
    fontWeight: FontWeight.w400,
  );
  static const value = TextStyle(
    inherit: false,
    fontFamily: _systemFont,
    fontSize: 17,
    fontWeight: FontWeight.w400,
  );
  static const label = TextStyle(
    inherit: false,
    fontFamily: _systemFont,
    fontSize: 13,
    fontWeight: FontWeight.w400,
  );
  static const caption = TextStyle(
    inherit: false,
    fontFamily: _systemFont,
    fontSize: 12,
    fontWeight: FontWeight.w400,
  );

  /// Countdown und Trainingszeit: Ziffern mit fester Breite, damit die Anzeige nicht springt.
  static const timer = TextStyle(
    inherit: false,
    fontFamily: _systemFont,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
