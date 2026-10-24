import 'package:flutter/widgets.dart';

import '../theme.dart';

/// Schmaler Fortschrittsbalken; wärmere Farbe, sobald das Ziel überschritten
/// ist.
class GainerProgressBar extends StatelessWidget {
  const GainerProgressBar({
    super.key,
    required this.consumed,
    required this.target,
    this.height = 6,
    this.warnWhenExceeded = true,
    this.color,
  });

  final double? consumed;
  final double target;
  final double height;

  /// False für Mindestziele wie Ballaststoffe: Darüber bleibt der Balken voll
  /// in der Akzentfarbe.
  final bool warnWhenExceeded;

  /// Füllfarbe; ohne Angabe die Akzentfarbe. Über dem Ziel gilt weiter die
  /// Warnfarbe.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final value = consumed ?? 0;
    final ratio = target <= 0 ? 0.0 : (value / target).clamp(0.0, 1.0);
    final exceeded = warnWhenExceeded && target > 0 && value > target;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: colors.elevatedSurface)),
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: constraints.maxWidth * ratio,
                  height: height,
                  child: ColoredBox(
                    color: exceeded ? colors.warning : color ?? colors.accent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
