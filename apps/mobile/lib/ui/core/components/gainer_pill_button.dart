import 'package:flutter/cupertino.dart';

import '../theme.dart';

enum GainerPillVariant { filled, tonal, destructive }

/// Pillenförmiger Button. `filled` ist die Abschlussaktion, `destructive` markiert Löschen.
class GainerPillButton extends StatelessWidget {
  const GainerPillButton({
    required this.label,
    required this.onPressed,
    this.variant = GainerPillVariant.filled,
    this.expand = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final GainerPillVariant variant;

  /// Füllt die verfügbare Breite, etwa für gestapelte Dialogaktionen.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final enabled = onPressed != null;
    final (background, foreground) = switch (variant) {
      GainerPillVariant.filled => (colors.accent, colors.onAccent),
      GainerPillVariant.tonal => (colors.elevatedSurface, colors.accent),
      GainerPillVariant.destructive => (
        colors.elevatedSurface,
        colors.destructive,
      ),
    };
    final button = CupertinoButton(
      minimumSize: const Size.square(GainerRadii.iconButtonDiameter),
      padding: const EdgeInsets.symmetric(horizontal: GainerSpacing.l),
      color: enabled ? background : colors.elevatedSurface,
      disabledColor: enabled ? background : colors.elevatedSurface,
      borderRadius: GainerRadii.pill,
      onPressed: onPressed,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: GainerTypography.body.copyWith(
          fontWeight: FontWeight.w600,
          color: enabled ? foreground : colors.placeholderText,
        ),
      ),
    );
    if (!expand) return button;
    return SizedBox(width: double.infinity, child: button);
  }
}
