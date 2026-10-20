import 'package:flutter/cupertino.dart';

import '../../../domain/models/training/muscles.dart';
import '../../core/theme.dart';

/// Vorder- und Rückansicht mit eingefärbten Muskelflächen (Design D5).
/// Muskeln ohne Eintrag in [fills] erscheinen in der Grundfarbe.
class BodyMap extends StatelessWidget {
  const BodyMap({
    required this.fills,
    this.onMuscleTap,
    this.semanticLabel,
    super.key,
  });

  final Map<Muscle, Color> fills;
  final ValueChanged<Muscle>? onMuscleTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Semantics(
      label: semanticLabel,
      image: true,
      child: AspectRatio(
        aspectRatio: _BodyMapGeometry.width / _BodyMapGeometry.height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = constraints.maxWidth / _BodyMapGeometry.width;
            final painter = CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: _BodyMapPainter(
                fills: fills,
                silhouette: colors.background,
                outline: colors.separator,
                idle: colors.separator,
              ),
            );
            final onTap = onMuscleTap;
            if (onTap == null) return painter;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                final muscle = _BodyMapGeometry.hit(
                  details.localPosition / scale,
                );
                if (muscle != null) onTap(muscle);
              },
              child: painter,
            );
          },
        ),
      ),
    );
  }
}

class _BodyMapPainter extends CustomPainter {
  _BodyMapPainter({
    required this.fills,
    required this.silhouette,
    required this.outline,
    required this.idle,
  });

  final Map<Muscle, Color> fills;
  final Color silhouette;
  final Color outline;
  final Color idle;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _BodyMapGeometry.width;
    canvas.save();
    canvas.scale(scale);
    for (final figure in _BodyMapGeometry.figures) {
      canvas.save();
      canvas.translate(figure.offsetX, 0);
      // Erst alle Umrisse, dann alle Flächen: So bleibt nur die Außenkante
      // sichtbar, wo sich Körperteile überlappen.
      final stroke = Paint()
        ..color = outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round;
      final fill = Paint()..color = silhouette;
      for (final part in _BodyMapGeometry.silhouette) {
        canvas.drawPath(part, stroke);
      }
      for (final part in _BodyMapGeometry.silhouette) {
        canvas.drawPath(part, fill);
      }
      for (final MapEntry(key: muscle, value: path) in figure.muscles.entries) {
        canvas.drawPath(path, Paint()..color = fills[muscle] ?? idle);
      }
      if (figure.isFront) {
        // Trennlinien im Bauch für die typische Form.
        final line = Paint()
          ..color = silhouette
          ..strokeWidth = 2;
        for (final y in const [146.0, 166.0]) {
          canvas.drawLine(Offset(84, y), Offset(116, y), line);
        }
      }
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BodyMapPainter old) =>
      !_sameFills(old.fills, fills) ||
      old.silhouette != silhouette ||
      old.outline != outline ||
      old.idle != idle;

  static bool _sameFills(Map<Muscle, Color> a, Map<Muscle, Color> b) {
    if (a.length != b.length) return false;
    for (final MapEntry(:key, :value) in a.entries) {
      if (b[key] != value) return false;
    }
    return true;
  }
}

class _Figure {
  const _Figure(this.offsetX, this.isFront, this.muscles);

  final double offsetX;
  final bool isFront;
  final Map<Muscle, Path> muscles;
}

/// Pfade in einem Raster von 200 × 430 je Ansicht. Stützpunkte gelten für
/// die linke Bildhälfte und werden an x = 100 gespiegelt.
abstract final class _BodyMapGeometry {
  static const figureWidth = 200.0;
  static const gap = 8.0;
  static const width = figureWidth * 2 + gap;
  static const height = 430.0;

  static final figures = [
    _Figure(0, true, _front),
    _Figure(figureWidth + gap, false, _back),
  ];

  static Muscle? hit(Offset position) {
    for (final figure in figures) {
      final local = position.translate(-figure.offsetX, 0);
      for (final MapEntry(key: muscle, value: path) in figure.muscles.entries) {
        if (path.contains(local)) return muscle;
      }
    }
    return null;
  }

  /// Körperteile einzeln, weil gespiegelte Formen gegenläufig umlaufen und
  /// sich in einem gemeinsamen Pfad an Überlappungen auslöschen würden.
  static final List<Path> silhouette = [
    Path()..addOval(
      Rect.fromCenter(center: const Offset(100, 34), width: 38, height: 48),
    ),
    _symmetric(_neck),
    _symmetric(_torso),
    for (final part in [
      _upperArm,
      _forearm,
      _hand,
      _thigh,
      _lowerLeg,
      _foot,
    ]) ...[_smooth(part), _smooth(_mirror(part))],
  ];

  static const _neck = [Offset(100, 50), Offset(90, 52), Offset(88, 76)];
  static const _torso = [
    Offset(100, 70),
    Offset(86, 72),
    Offset(68, 78),
    Offset(56, 86),
    Offset(56, 102),
    Offset(62, 118),
    Offset(66, 142),
    Offset(68, 172),
    Offset(66, 196),
    Offset(70, 212),
    Offset(100, 218),
  ];
  static const _upperArm = [
    Offset(54, 82),
    Offset(62, 94),
    Offset(60, 120),
    Offset(57, 146),
    Offset(48, 154),
    Offset(39, 146),
    Offset(37, 120),
    Offset(40, 96),
    Offset(46, 86),
  ];
  static const _forearm = [
    Offset(40, 148),
    Offset(57, 148),
    Offset(56, 168),
    Offset(50, 196),
    Offset(42, 200),
    Offset(33, 188),
    Offset(33, 164),
  ];
  static const _hand = [
    Offset(36, 196),
    Offset(49, 196),
    Offset(50, 212),
    Offset(44, 226),
    Offset(36, 224),
    Offset(31, 210),
  ];
  static const _thigh = [
    Offset(68, 196),
    Offset(99, 206),
    Offset(98, 238),
    Offset(94, 278),
    Offset(90, 300),
    Offset(74, 302),
    Offset(66, 270),
    Offset(62, 230),
  ];
  static const _lowerLeg = [
    Offset(72, 296),
    Offset(92, 296),
    Offset(93, 322),
    Offset(89, 362),
    Offset(87, 394),
    Offset(76, 396),
    Offset(70, 360),
    Offset(67, 322),
  ];
  static const _foot = [
    Offset(74, 392),
    Offset(88, 392),
    Offset(92, 406),
    Offset(86, 414),
    Offset(70, 414),
    Offset(68, 404),
  ];

  static final Map<Muscle, Path> _front = {
    Muscle.sideDelts: _pair(_sideDelt),
    Muscle.frontDelts: _pair(const [
      Offset(59, 84),
      Offset(68, 80),
      Offset(74, 86),
      Offset(70, 100),
      Offset(63, 108),
      Offset(59, 100),
    ]),
    Muscle.chest: _pair(const [
      Offset(77, 84),
      Offset(97, 86),
      Offset(97, 114),
      Offset(89, 122),
      Offset(78, 120),
      Offset(71, 110),
      Offset(72, 94),
    ]),
    Muscle.biceps: _pair(_upperArmMuscle),
    Muscle.forearms: _pair(_forearmMuscle),
    Muscle.abs: _pair(const [
      Offset(87, 128),
      Offset(97, 128),
      Offset(97, 190),
      Offset(93, 196),
      Offset(87, 188),
      Offset(85, 156),
    ]),
    Muscle.obliques: _pair(const [
      Offset(73, 128),
      Offset(82, 130),
      Offset(83, 160),
      Offset(82, 186),
      Offset(76, 182),
      Offset(70, 158),
      Offset(69, 138),
    ]),
    Muscle.quads: _pair(const [
      Offset(71, 214),
      Offset(88, 216),
      Offset(91, 242),
      Offset(89, 272),
      Offset(84, 290),
      Offset(76, 290),
      Offset(70, 268),
      Offset(67, 238),
    ]),
    Muscle.adductors: _pair(const [
      Offset(92, 216),
      Offset(98, 218),
      Offset(97, 238),
      Offset(94, 258),
      Offset(91, 240),
    ]),
    Muscle.calves: _pair(const [
      Offset(71, 318),
      Offset(78, 314),
      Offset(80, 336),
      Offset(77, 362),
      Offset(72, 360),
      Offset(69, 338),
    ]),
  };

  static final Map<Muscle, Path> _back = {
    Muscle.traps: _symmetric(const [
      Offset(100, 62),
      Offset(90, 70),
      Offset(74, 80),
      Offset(68, 86),
      Offset(84, 94),
      Offset(90, 120),
      Offset(96, 140),
      Offset(100, 142),
    ]),
    Muscle.sideDelts: _pair(_sideDelt),
    Muscle.rearDelts: _pair(const [
      Offset(59, 86),
      Offset(68, 84),
      Offset(76, 90),
      Offset(72, 102),
      Offset(63, 108),
      Offset(59, 100),
    ]),
    Muscle.triceps: _pair(_upperArmMuscle),
    Muscle.forearms: _pair(_forearmMuscle),
    Muscle.lats: _pair(const [
      Offset(74, 98),
      Offset(84, 102),
      Offset(88, 128),
      Offset(89, 158),
      Offset(84, 178),
      Offset(76, 174),
      Offset(68, 148),
      Offset(64, 118),
      Offset(66, 104),
    ]),
    Muscle.lowerBack: _symmetric(const [
      Offset(100, 148),
      Offset(94, 148),
      Offset(91, 166),
      Offset(92, 188),
      Offset(100, 194),
    ]),
    Muscle.glutes: _pair(const [
      Offset(74, 198),
      Offset(97, 200),
      Offset(99, 222),
      Offset(94, 240),
      Offset(80, 242),
      Offset(70, 228),
      Offset(68, 210),
    ]),
    Muscle.hamstrings: _pair(const [
      Offset(70, 250),
      Offset(94, 250),
      Offset(95, 276),
      Offset(90, 294),
      Offset(78, 296),
      Offset(70, 282),
      Offset(67, 264),
    ]),
    Muscle.calves: _pair(const [
      Offset(71, 318),
      Offset(89, 316),
      Offset(91, 340),
      Offset(86, 366),
      Offset(77, 368),
      Offset(69, 346),
    ]),
  };

  static const _sideDelt = [
    Offset(46, 90),
    Offset(54, 84),
    Offset(58, 90),
    Offset(56, 104),
    Offset(50, 112),
    Offset(43, 106),
    Offset(42, 96),
  ];
  static const _upperArmMuscle = [
    Offset(44, 116),
    Offset(54, 114),
    Offset(57, 126),
    Offset(55, 142),
    Offset(48, 148),
    Offset(41, 140),
    Offset(40, 126),
  ];
  static const _forearmMuscle = [
    Offset(38, 156),
    Offset(52, 156),
    Offset(52, 170),
    Offset(48, 190),
    Offset(42, 192),
    Offset(36, 182),
    Offset(35, 166),
  ];

  /// Linke Form und ihr Spiegelbild.
  static Path _pair(List<Offset> left) => Path()
    ..addPath(_smooth(left), Offset.zero)
    ..addPath(_smooth(_mirror(left)), Offset.zero);

  /// Eine Form aus der linken Hälfte (von der Mitte oben bis zur Mitte unten)
  /// und ihrem Spiegelbild.
  static Path _symmetric(List<Offset> leftHalf) => _smooth([
    ...leftHalf,
    ..._mirror([
      for (final point in leftHalf.reversed)
        if (point.dx != figureWidth / 2) point,
    ]),
  ]);

  static List<Offset> _mirror(List<Offset> points) => [
    for (final point in points) Offset(figureWidth - point.dx, point.dy),
  ];

  /// Geschlossene Catmull-Rom-Kurve durch alle Punkte.
  static Path _smooth(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    final n = points.length;
    for (var i = 0; i < n; i++) {
      final p0 = points[(i - 1 + n) % n];
      final p1 = points[i];
      final p2 = points[(i + 1) % n];
      final p3 = points[(i + 2) % n];
      final c1 = p1 + (p2 - p0) / 6;
      final c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path..close();
  }
}
