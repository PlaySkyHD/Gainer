import 'package:flutter/cupertino.dart';

import '../theme.dart';

/// Zeile mit optionalem Icon links, Titel und Untertitel, rechts Wert oder `trailing` (z. B. Switch) und optionalem Pfeil.
/// `value` und `trailing` schließen sich aus.
class GainerListRow extends StatelessWidget {
  const GainerListRow({
    required this.title,
    this.subtitle,
    this.leadingIcon,
    this.leadingIconBackground,
    this.value,
    this.trailing,
    this.showChevron = false,
    this.onTap,
    super.key,
  }) : assert(
         value == null || trailing == null,
         'value und trailing schließen sich aus.',
       );

  final String title;
  final String? subtitle;
  final IconData? leadingIcon;

  /// Hintergrund eines gerundeten Icon-Containers; ohne Wert steht das Icon frei in Akzentfarbe.
  final Color? leadingIconBackground;
  final String? value;
  final Widget? trailing;
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
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              if (leadingIcon case final icon?) ...[
                _LeadingIcon(
                  icon: icon,
                  background: leadingIconBackground,
                  colors: colors,
                ),
                const SizedBox(width: GainerSpacing.s),
              ],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GainerTypography.body.copyWith(
                        color: colors.primaryText,
                      ),
                    ),
                    if (subtitle case final text?)
                      Text(
                        text,
                        style: GainerTypography.label.copyWith(
                          color: colors.secondaryText,
                        ),
                      ),
                  ],
                ),
              ),
              if (value case final text?)
                ConstrainedBox(
                  // Long values wrap instead of overflowing the row.
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * 0.6,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(left: GainerSpacing.xs),
                    child: Text(
                      text,
                      textAlign: TextAlign.end,
                      style: GainerTypography.value.copyWith(
                        color: colors.secondaryText,
                      ),
                    ),
                  ),
                ),
              if (trailing case final widget?)
                Padding(
                  padding: const EdgeInsets.only(left: GainerSpacing.xs),
                  child: widget,
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

class _LeadingIcon extends StatelessWidget {
  const _LeadingIcon({
    required this.icon,
    required this.background,
    required this.colors,
  });

  final IconData icon;
  final Color? background;
  final GainerColors colors;

  @override
  Widget build(BuildContext context) {
    final tile = background;
    if (tile == null) {
      return Icon(icon, size: 22, color: colors.accent);
    }
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: tile,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 16, color: colors.onAccent),
    );
  }
}
