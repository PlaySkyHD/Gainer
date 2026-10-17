import 'package:flutter/cupertino.dart';

import '../theme.dart';

/// Umschalter mit Rollenfarben, z. B. „Tagebuch | Pläne | Statistik“.
class GainerSegmentedControl<T extends Object> extends StatelessWidget {
  const GainerSegmentedControl({
    required this.options,
    required this.value,
    required this.onChanged,
    super.key,
  });

  /// Reihenfolge der Map bestimmt die Reihenfolge der Segmente.
  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return SizedBox(
      width: double.infinity,
      child: CupertinoSlidingSegmentedControl<T>(
        groupValue: value,
        backgroundColor: colors.elevatedSurface,
        thumbColor: colors.surface,
        onValueChanged: (selected) {
          if (selected != null) onChanged(selected);
        },
        children: {
          for (final entry in options.entries)
            entry.key: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: GainerSpacing.xs,
                vertical: GainerSpacing.xs,
              ),
              child: Text(
                entry.value,
                textAlign: TextAlign.center,
                style: GainerTypography.label.copyWith(
                  fontWeight: entry.key == value
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: entry.key == value
                      ? colors.primaryText
                      : colors.secondaryText,
                ),
              ),
            ),
        },
      ),
    );
  }
}
