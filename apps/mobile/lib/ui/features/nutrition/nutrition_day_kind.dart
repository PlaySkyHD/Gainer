import 'package:flutter/cupertino.dart';

import '../../../domain/models/nutrition/nutrition.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';

String dayKindLabel(NutritionDayKind kind) => switch (kind) {
  NutritionDayKind.training => 'Trainingstag',
  NutritionDayKind.rest => 'Ruhetag',
};

/// Chip „Trainingstag“ bzw. „Ruhetag · manuell“ über dem Tagesziel. Antippen
/// öffnet die Auswahl „Zählt als“.
class NutritionDayKindChip extends StatelessWidget {
  const NutritionDayKindChip({
    required this.kind,
    required this.manual,
    required this.onTap,
    super.key,
  });

  final NutritionDayKind kind;
  final bool manual;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final text = manual
        ? '${dayKindLabel(kind)} · manuell'
        : dayKindLabel(kind);
    // Eigener Knoten: Die Tageskarte ist selbst ein Button und würde den Chip
    // sonst in ihre Beschriftung übernehmen.
    return Semantics(
      container: true,
      button: onTap != null,
      // Ohne eigene Aktion bliebe der Chip für VoiceOver ein Knopf ohne Wirkung,
      // weil excludeSemantics die Geste des GestureDetector verbirgt.
      onTap: onTap,
      label:
          'Tagesart: ${dayKindLabel(kind)}'
          '${manual ? ', manuell festgelegt' : ''}'
          '${onTap != null ? '. Ändern' : ''}',
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('nutrition-day-kind-chip'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: GainerSpacing.s,
            vertical: GainerSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: colors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                kind == NutritionDayKind.training
                    ? CupertinoIcons.bolt_fill
                    : CupertinoIcons.moon_fill,
                size: 13,
                color: colors.accent,
              ),
              const SizedBox(width: GainerSpacing.xxs),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GainerTypography.caption.copyWith(
                    color: colors.accent,
                    fontWeight: FontWeight.w600,
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

enum _DayKindChoice { automatic, training, rest }

/// Auswahl „Zählt als“. Liefert die neue Festlegung (null heißt automatisch)
/// oder [current], wenn der Nutzer nichts wählt.
Future<({bool changed, NutritionDayKind? kind})> showDayKindSheet(
  BuildContext context, {
  required NutritionDayKind automatic,
  required NutritionDayKind? current,
}) async {
  String mark(bool selected) => selected ? 'Ausgewählt' : '';
  final choice = await showGainerActionSheet<_DayKindChoice>(
    context: context,
    title: 'Zählt als',
    groups: [
      [
        GainerSheetAction(
          label: 'Automatisch (${dayKindLabel(automatic)})',
          icon: current == null
              ? CupertinoIcons.checkmark_circle_fill
              : CupertinoIcons.wand_stars,
          hint: current == null ? mark(true) : 'Aus Training und Rhythmus',
          value: _DayKindChoice.automatic,
        ),
        GainerSheetAction(
          label: 'Trainingstag',
          icon: current == NutritionDayKind.training
              ? CupertinoIcons.checkmark_circle_fill
              : CupertinoIcons.bolt,
          hint: current == NutritionDayKind.training ? mark(true) : null,
          value: _DayKindChoice.training,
        ),
        GainerSheetAction(
          label: 'Ruhetag',
          icon: current == NutritionDayKind.rest
              ? CupertinoIcons.checkmark_circle_fill
              : CupertinoIcons.moon,
          hint: current == NutritionDayKind.rest ? mark(true) : null,
          value: _DayKindChoice.rest,
        ),
      ],
    ],
  );
  final kind = switch (choice) {
    null => current,
    _DayKindChoice.automatic => null,
    _DayKindChoice.training => NutritionDayKind.training,
    _DayKindChoice.rest => NutritionDayKind.rest,
  };
  return (changed: choice != null && kind != current, kind: kind);
}
