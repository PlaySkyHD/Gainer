import 'package:flutter/cupertino.dart';

import '../theme.dart';

/// Abschnittsüberschrift wie im Trainingstagebuch: Titel links, Zusatz rechts.
class GainerSectionHeader extends StatelessWidget {
  const GainerSectionHeader({required this.title, this.trailing, super.key});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final extra = trailing;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: GainerSpacing.xxs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: GainerTypography.cardTitle.copyWith(
                color: colors.primaryText,
              ),
            ),
          ),
          if (extra != null)
            Text(
              extra,
              style: GainerTypography.label.copyWith(
                color: colors.secondaryText,
              ),
            ),
        ],
      ),
    );
  }
}
