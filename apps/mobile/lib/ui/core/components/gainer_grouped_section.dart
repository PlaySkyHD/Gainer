import 'package:flutter/cupertino.dart';

import '../theme.dart';
import 'gainer_card.dart';

/// Zeilen in einer gemeinsamen Karte, getrennt durch feine Trenner.
class GainerGroupedSection extends StatelessWidget {
  const GainerGroupedSection({required this.children, this.header, super.key});

  final String? header;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(
          Container(
            height: 0.5,
            margin: const EdgeInsets.only(left: GainerSpacing.m),
            color: colors.separator,
          ),
        );
      }
      rows.add(children[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header case final text?)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              GainerSpacing.m,
              0,
              GainerSpacing.m,
              GainerSpacing.xs,
            ),
            child: Text(
              text,
              style: GainerTypography.label.copyWith(
                color: colors.secondaryText,
              ),
            ),
          ),
        GainerCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows,
          ),
        ),
      ],
    );
  }
}
