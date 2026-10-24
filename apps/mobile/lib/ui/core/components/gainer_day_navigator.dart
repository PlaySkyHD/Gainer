import 'package:flutter/cupertino.dart';

import '../theme.dart';

/// Tages-Pille „‹ Heute ›“: Pfeile wechseln den Tag, der Text in der Mitte
/// öffnet die Tagesauswahl.
class GainerDayNavigator extends StatelessWidget {
  const GainerDayNavigator({
    required this.label,
    required this.onPrevious,
    required this.onNext,
    required this.onPick,
    this.pillKey,
    super.key,
  });

  final String label;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onPick;

  /// Schlüssel des Textes in der Mitte, z. B. für Tests.
  final Key? pillKey;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    Widget arrow(IconData icon, String semanticLabel, VoidCallback onTap) =>
        Semantics(
          button: true,
          label: semanticLabel,
          excludeSemantics: true,
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size.square(GainerRadii.iconButtonDiameter),
            onPressed: onTap,
            child: Icon(icon, size: 22, color: colors.primaryText),
          ),
        );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.elevatedSurface,
        borderRadius: GainerRadii.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          arrow(CupertinoIcons.chevron_left, 'Vorheriger Tag', onPrevious),
          Semantics(
            button: true,
            label: 'Tag auswählen',
            excludeSemantics: true,
            child: CupertinoButton(
              key: pillKey,
              padding: const EdgeInsets.symmetric(horizontal: GainerSpacing.xs),
              minimumSize: const Size(0, GainerRadii.iconButtonDiameter),
              onPressed: onPick,
              child: Text(
                label,
                style: GainerTypography.body.copyWith(
                  color: colors.primaryText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          arrow(CupertinoIcons.chevron_right, 'Nächster Tag', onNext),
        ],
      ),
    );
  }
}

/// „Heute“, „Gestern“, „Morgen“ oder kurzes Datum wie „Mo. 12. Okt.“.
String gainerDayLabel(DateTime date, DateTime today) {
  final now = today;
  final difference = DateTime.utc(
    date.year,
    date.month,
    date.day,
  ).difference(DateTime.utc(now.year, now.month, now.day)).inDays;
  if (difference == 0) return 'Heute';
  if (difference == -1) return 'Gestern';
  if (difference == 1) return 'Morgen';
  const weekdays = ['Mo.', 'Di.', 'Mi.', 'Do.', 'Fr.', 'Sa.', 'So.'];
  const months = [
    'Jan.',
    'Feb.',
    'März',
    'Apr.',
    'Mai',
    'Juni',
    'Juli',
    'Aug.',
    'Sept.',
    'Okt.',
    'Nov.',
    'Dez.',
  ];
  return '${weekdays[date.weekday - 1]} ${date.day}. ${months[date.month - 1]}';
}
