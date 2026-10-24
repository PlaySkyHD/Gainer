import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../core/components/components.dart';
import '../../core/theme.dart';
import '../nutrition/nutrition_day_kind.dart';
import 'calendar_format.dart';
import 'calendar_view_model.dart';

/// Ernährungsübersicht eines Tages: offener Ring mit den übrigen Kalorien,
/// links „Gegessen“, rechts „Ziel“, darunter drei Makro-Balken. Ohne Ziel
/// steht nur „Gegessen“ im Ring und die Makros zeigen die Ist-Werte.
/// Die ganze Karte öffnet den Essen-Tab für den Tag.
class CalendarNutritionOverview extends StatelessWidget {
  const CalendarNutritionOverview({
    required this.nutrition,
    required this.onTap,
    this.onDayKind,
    super.key,
  });

  final CalendarNutrition nutrition;
  final VoidCallback onTap;

  /// Öffnet „Zählt als“; der Chip erscheint nur mit Ruhetag-Ziel.
  final VoidCallback? onDayKind;

  /// Ab dieser Textgröße werden Ring und Makros gestapelt.
  static const _stackScale = 1.4;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final stacked = MediaQuery.textScalerOf(context).scale(1) > _stackScale;
    final summary = _Summary.of(nutrition);
    final chip = switch (nutrition.target?.kind) {
      final kind? => NutritionDayKindChip(
        kind: kind,
        manual: nutrition.target!.manual,
        onTap: onDayKind,
      ),
      null => null,
    };
    return Semantics(
      container: true,
      button: true,
      label: summary.semanticsLabel(nutrition),
      onTap: onTap,
      excludeSemantics: true,
      child: CupertinoButton(
        key: const ValueKey('calendar-nutrition-card'),
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        pressedOpacity: .7,
        onPressed: onTap,
        child: SizedBox(
          width: double.infinity,
          child: GainerCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Ernährung',
                        style: GainerTypography.cardTitle.copyWith(
                          color: colors.primaryText,
                        ),
                      ),
                    ),
                    if (chip != null && !stacked) ...[
                      Flexible(child: chip),
                      const SizedBox(width: GainerSpacing.xs),
                    ],
                    Icon(
                      CupertinoIcons.chevron_forward,
                      size: 16,
                      color: colors.placeholderText,
                    ),
                  ],
                ),
                // Bei großer Schrift steht die Tagesart in eigener Zeile.
                if (chip != null && stacked) ...[
                  const SizedBox(height: GainerSpacing.xs),
                  Align(alignment: Alignment.centerLeft, child: chip),
                ],
                const SizedBox(height: GainerSpacing.s),
                _energy(summary, stacked),
                const SizedBox(height: GainerSpacing.l),
                _macros(stacked),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _energy(_Summary summary, bool stacked) {
    final ring = _CalorieRing(
      progress: summary.progress,
      showKnob: nutrition.targetKilocalories != null,
      exceeded: summary.exceeded,
      value: calendarWholeNumber(summary.centreValue),
      label: summary.centreLabel,
      diameter: stacked ? 208 : 148,
    );
    final target = nutrition.targetKilocalories;
    if (target == null) return Center(child: ring);
    final eaten = _Figure(
      key: const ValueKey('calendar-nutrition-eaten'),
      value: calendarWholeNumber(nutrition.kilocalories),
      label: 'Gegessen',
    );
    final goal = _Figure(
      key: const ValueKey('calendar-nutrition-target'),
      value: calendarWholeNumber(target),
      label: 'Ziel',
    );
    if (stacked) {
      return Column(
        children: [
          ring,
          const SizedBox(height: GainerSpacing.s),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: eaten),
              const SizedBox(width: GainerSpacing.s),
              Expanded(child: goal),
            ],
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: eaten),
        ring,
        Expanded(child: goal),
      ],
    );
  }

  Widget _macros(bool stacked) {
    final macros = [
      _Macro(
        key: const ValueKey('calendar-nutrition-carbs'),
        name: 'Kohlenhydrate',
        value: nutrition.carbohydrateGrams,
        target: nutrition.targetCarbohydrateGrams,
        stacked: stacked,
        tint: (colors) => colors.carbohydrate,
      ),
      _Macro(
        key: const ValueKey('calendar-nutrition-protein'),
        name: 'Eiweiß',
        value: nutrition.proteinGrams,
        target: nutrition.targetProteinGrams,
        stacked: stacked,
        tint: (colors) => colors.protein,
      ),
      _Macro(
        key: const ValueKey('calendar-nutrition-fat'),
        name: 'Fett',
        value: nutrition.fatGrams,
        target: nutrition.targetFatGrams,
        stacked: stacked,
        tint: (colors) => colors.fat,
      ),
    ];
    final fiber = _Macro(
      key: const ValueKey('calendar-nutrition-fiber'),
      name: 'Ballaststoffe',
      value: nutrition.fiberGrams,
      target: nutrition.targetFiberGrams,
      stacked: stacked,
      minimum: true,
    );
    final salt = _Macro(
      key: const ValueKey('calendar-nutrition-salt'),
      name: 'Salz',
      value: nutrition.saltGrams,
      target: nutrition.targetSaltGrams,
      stacked: stacked,
      decimals: 1,
    );
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final macro in [...macros, fiber, salt]) ...[
            if (macro != macros.first) const SizedBox(height: GainerSpacing.m),
            macro,
          ],
        ],
      );
    }
    // Ballaststoffe (Mindestziel) und Salz (Obergrenze) stehen zentriert in
    // eigener Zeile unter den Makros, je so breit wie eine Makrospalte.
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = GainerSpacing.m;
        final column = (constraints.maxWidth - 2 * gap) / 3;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < macros.length; i++) ...[
                  if (i > 0) const SizedBox(width: gap),
                  Expanded(child: macros[i]),
                ],
              ],
            ),
            const SizedBox(height: GainerSpacing.m),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: column, child: fiber),
                const SizedBox(width: gap),
                SizedBox(width: column, child: salt),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Werte für Ring und VoiceOver, aus ganzen Kilokalorien gerechnet, damit
/// „Übrig“ zu den angezeigten Zahlen passt.
class _Summary {
  const _Summary({
    required this.centreValue,
    required this.centreLabel,
    required this.progress,
    required this.exceeded,
  });

  factory _Summary.of(CalendarNutrition nutrition) {
    final eaten = nutrition.kilocalories.roundToDouble();
    final target = nutrition.targetKilocalories?.roundToDouble();
    if (target == null) {
      return _Summary(
        centreValue: eaten,
        centreLabel: 'Gegessen',
        progress: 0,
        exceeded: false,
      );
    }
    final remaining = target - eaten;
    return _Summary(
      centreValue: remaining.abs(),
      centreLabel: remaining < 0 ? 'Über' : 'Übrig',
      progress: target <= 0 ? 0 : (eaten / target).clamp(0.0, 1.0),
      exceeded: remaining < 0,
    );
  }

  final double centreValue;
  final String centreLabel;
  final double progress;
  final bool exceeded;

  String semanticsLabel(CalendarNutrition nutrition) {
    final target = nutrition.targetKilocalories;
    String macro(
      String name,
      double? value,
      double? goal, {
      int decimals = 0,
    }) => value == null
        ? '$name ohne Angabe'
        : '$name ${calendarGrams(value, goal, decimals: decimals)}';
    return [
      'Ernährung: ${calendarKcal(nutrition.kilocalories, null)} gegessen',
      if (target != null) ...[
        '${calendarKcal(centreValue, null)} ${exceeded ? 'über' : 'übrig'}',
        'Ziel ${calendarKcal(target, null)}',
      ],
      macro(
        'Kohlenhydrate',
        nutrition.carbohydrateGrams,
        nutrition.targetCarbohydrateGrams,
      ),
      macro('Eiweiß', nutrition.proteinGrams, nutrition.targetProteinGrams),
      macro('Fett', nutrition.fatGrams, nutrition.targetFatGrams),
      macro('Ballaststoffe', nutrition.fiberGrams, nutrition.targetFiberGrams),
      macro(
        'Salz',
        nutrition.saltGrams,
        nutrition.targetSaltGrams,
        decimals: 1,
      ),
    ].join(', ');
  }
}

/// Große Zahl mit kleiner Beschriftung darunter.
class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label, super.key});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            style: GainerTypography.title.copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: colors.primaryText,
            ),
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: GainerTypography.label.copyWith(color: colors.secondaryText),
        ),
      ],
    );
  }
}

/// Offener Ring (270°, Lücke unten) mit Punkt am Ende des Fortschritts.
class _CalorieRing extends StatelessWidget {
  const _CalorieRing({
    required this.progress,
    required this.showKnob,
    required this.exceeded,
    required this.value,
    required this.label,
    required this.diameter,
  });

  static const _stroke = 10.0;

  final double progress;

  /// Punkt am Ende des Fortschritts; ohne Ziel gibt es keinen Fortschritt.
  final bool showKnob;
  final bool exceeded;
  final String value;
  final String label;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return SizedBox.square(
      key: const ValueKey('calendar-nutrition-ring'),
      dimension: diameter,
      child: CustomPaint(
        painter: _RingPainter(
          progress: progress,
          showKnob: showKnob,
          track: colors.elevatedSurface,
          fill: exceeded ? colors.warning : colors.accent,
          knob: colors.surface,
          stroke: _stroke,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            _stroke + GainerSpacing.s,
            _stroke + GainerSpacing.s,
            _stroke + GainerSpacing.s,
            _stroke,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  key: const ValueKey('calendar-nutrition-centre'),
                  maxLines: 1,
                  style: GainerTypography.largeTitle.copyWith(
                    color: colors.primaryText,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  style: GainerTypography.label.copyWith(
                    color: exceeded ? colors.warning : colors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.showKnob,
    required this.track,
    required this.fill,
    required this.knob,
    required this.stroke,
  });

  /// Beginn unten links, 270° im Uhrzeigersinn bis unten rechts.
  static const _start = math.pi * 3 / 4;
  static const _sweep = math.pi * 3 / 2;

  final double progress;
  final bool showKnob;
  final Color track;
  final Color fill;
  final Color knob;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (math.min(size.width, size.height) - stroke) / 2;
    final centre = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: centre, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _start, _sweep, false, paint..color = track);
    if (progress > 0) {
      canvas.drawArc(
        rect,
        _start,
        _sweep * progress,
        false,
        paint..color = fill,
      );
    }
    if (!showKnob) return;
    final angle = _start + _sweep * progress;
    canvas.drawCircle(
      centre + Offset(math.cos(angle), math.sin(angle)) * radius,
      stroke * .3,
      Paint()..color = progress > 0 ? knob : fill,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.showKnob != showKnob ||
      old.track != track ||
      old.fill != fill ||
      old.knob != knob ||
      old.stroke != stroke;
}

/// Ein Makro: Name, schmaler Balken zum Ziel, darunter „x / Ziel g“. Ohne
/// Ziel entfällt der Balken.
class _Macro extends StatelessWidget {
  const _Macro({
    required this.name,
    required this.value,
    required this.target,
    required this.stacked,
    this.decimals = 0,
    this.minimum = false,
    this.tint,
    super.key,
  });

  final String name;
  final double? value;
  final double? target;
  final bool stacked;
  final int decimals;

  /// Makrofarbe für Punkt und Balken; ohne Wert neutral (Ballaststoffe, Salz).
  final Color Function(GainerColors colors)? tint;

  /// Mindestziel: Über dem Ziel gibt es keine Warnfarbe.
  final bool minimum;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final goal = target;
    final alignment = stacked
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.center;
    final textAlignment = stacked ? Alignment.centerLeft : Alignment.center;
    final color = tint?.call(colors);
    return Column(
      crossAxisAlignment: alignment,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: textAlignment,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (color != null) ...[
                _Dot(color: color),
                const SizedBox(width: GainerSpacing.xxs),
              ],
              Text(
                name,
                maxLines: 1,
                style: GainerTypography.label.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.primaryText,
                ),
              ),
            ],
          ),
        ),
        if (goal != null) ...[
          const SizedBox(height: GainerSpacing.xxs),
          SizedBox(
            width: double.infinity,
            child: GainerProgressBar(
              consumed: value,
              target: goal,
              height: 4,
              warnWhenExceeded: !minimum,
              color: color ?? (minimum ? null : colors.secondaryText),
            ),
          ),
        ],
        const SizedBox(height: GainerSpacing.xxs),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: textAlignment,
          child: Text(
            calendarGramsOf(value, goal, decimals: decimals),
            maxLines: 1,
            style: GainerTypography.label.copyWith(color: colors.secondaryText),
          ),
        ),
      ],
    );
  }
}

/// Farbpunkt vor dem Namen eines Makros; trägt die Farbe, der Text bleibt
/// in Textfarbe.
class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    child: const SizedBox.square(dimension: 8),
  );
}
