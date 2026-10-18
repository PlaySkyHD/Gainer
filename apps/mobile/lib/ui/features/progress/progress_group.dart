import 'package:flutter/cupertino.dart';

import '../../core/components/components.dart';
import '../../core/theme.dart';

/// Gruppe im Tab Heute: kleine Überschrift, Zeilen in einer Karte und optionale Fußnote, wie im Training.
class ProgressGroup extends StatelessWidget {
  const ProgressGroup({
    required this.header,
    required this.children,
    this.footer,
    super.key,
  });

  final String header;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: GainerSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GainerGroupedSection(header: header, children: children),
          if (footer case final note?)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                GainerSpacing.m,
                GainerSpacing.xs,
                GainerSpacing.m,
                0,
              ),
              child: Text(
                note,
                style: GainerTypography.label.copyWith(
                  color: colors.secondaryText,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Kennzahl mit kleiner Beschriftung darüber und großem Wert.
class ProgressFigure extends StatelessWidget {
  const ProgressFigure({
    required this.label,
    required this.value,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final String label;
  final String value;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GainerTypography.label.copyWith(color: colors.secondaryText),
          ),
          const SizedBox(height: GainerSpacing.xxs),
          Text(
            value,
            style: GainerTypography.title.copyWith(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: colors.primaryText,
            ),
          ),
        ],
      ),
    );
  }
}
