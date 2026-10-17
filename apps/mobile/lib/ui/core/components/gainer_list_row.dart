import 'package:flutter/cupertino.dart';

import '../theme.dart';

/// Zeile mit Titel, optionalem Wert rechts und optionalem Pfeil.
class GainerListRow extends StatelessWidget {
  const GainerListRow({
    required this.title,
    this.value,
    this.showChevron = false,
    this.onTap,
    super.key,
  });

  final String title;
  final String? value;
  final bool showChevron;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: GainerSpacing.m,
          vertical: 11,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: GainerTypography.body.copyWith(
                  color: colors.primaryText,
                ),
              ),
            ),
            if (value case final text?)
              Padding(
                padding: const EdgeInsets.only(left: GainerSpacing.xs),
                child: Text(
                  text,
                  textAlign: TextAlign.end,
                  style: GainerTypography.value.copyWith(
                    color: colors.secondaryText,
                  ),
                ),
              ),
            if (showChevron)
              Padding(
                padding: const EdgeInsets.only(left: GainerSpacing.xs),
                child: Icon(
                  CupertinoIcons.chevron_forward,
                  size: 16,
                  color: colors.secondaryText,
                ),
              ),
          ],
        ),
      ),
    );
    if (onTap == null) return row;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: row,
      ),
    );
  }
}
