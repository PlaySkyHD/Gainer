import 'package:flutter/cupertino.dart';

import '../theme.dart';

enum GainerPillVariant { filled, tonal, destructive }

/// Pillenförmiger Button. `filled` ist die Abschlussaktion, `destructive` markiert Löschen.
/// Im Ladezustand ist der Button deaktiviert und zeigt statt des Labels einen Spinner;
/// das Label bleibt unsichtbar im Layout, damit sich die Breite nicht ändert.
class GainerPillButton extends StatelessWidget {
  const GainerPillButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.variant = GainerPillVariant.filled,
    this.expand = false,
    this.compact = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final GainerPillVariant variant;

  /// Füllt die verfügbare Breite, etwa für gestapelte Dialogaktionen.
  final bool expand;

  /// Weniger Innenabstand für mehrere Buttons nebeneinander, etwa
  /// Schnellknöpfe in einer Karte.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final enabled = onPressed != null && !isLoading;
    final (background, foreground) = switch (variant) {
      GainerPillVariant.filled => (colors.accent, colors.onAccent),
      GainerPillVariant.tonal => (colors.elevatedSurface, colors.accent),
      GainerPillVariant.destructive => (
        colors.elevatedSurface,
        colors.destructive,
      ),
    };
    final contentColor = enabled || isLoading
        ? foreground
        : colors.placeholderText;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon case final symbol?) ...[
          Icon(symbol, size: 18, color: contentColor),
          const SizedBox(width: GainerSpacing.xs),
        ],
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GainerTypography.body.copyWith(
              fontWeight: FontWeight.w600,
              color: contentColor,
            ),
          ),
        ),
      ],
    );
    final button = Semantics(
      label: isLoading ? '$label, lädt' : null,
      child: CupertinoButton(
        minimumSize: const Size.square(GainerRadii.iconButtonDiameter),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? GainerSpacing.s : GainerSpacing.l,
        ),
        color: enabled || isLoading ? background : colors.elevatedSurface,
        disabledColor: enabled || isLoading
            ? background
            : colors.elevatedSurface,
        borderRadius: GainerRadii.pill,
        onPressed: enabled ? onPressed : null,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: isLoading ? 0 : 1,
              child: ExcludeSemantics(child: content),
            ),
            if (isLoading) CupertinoActivityIndicator(color: foreground),
          ],
        ),
      ),
    );
    if (!expand) return button;
    return SizedBox(width: double.infinity, child: button);
  }
}
