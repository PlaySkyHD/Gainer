import 'package:flutter/cupertino.dart';

import '../theme.dart';

/// Ein Eintrag der schwebenden Tableiste.
final class GainerTabItem {
  const GainerTabItem({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

/// Schwebende, stark gerundete Tableiste mit dauerhaft beschrifteten Icons.
class GainerFloatingTabBar extends StatelessWidget {
  const GainerFloatingTabBar({
    required this.items,
    required this.currentIndex,
    required this.onTap,
    super.key,
  });

  final List<GainerTabItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: Container(
        height: 64,
        padding: const EdgeInsets.all(GainerSpacing.xs - 2),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: GainerRadii.pill,
          border: Border.all(color: colors.separator, width: 0.5),
        ),
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: _TabItem(
                  item: items[i],
                  selected: i == currentIndex,
                  onTap: () => onTap(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final GainerTabItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final foreground = selected ? colors.accent : colors.secondaryText;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      tooltip: item.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: selected ? colors.elevatedSurface : null,
            borderRadius: GainerRadii.pill,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(item.icon, size: 22, color: foreground),
              const SizedBox(height: 2),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GainerTypography.caption.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
