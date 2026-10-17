import 'package:flutter/cupertino.dart';

import '../theme.dart';

/// Gerundete Fläche für zusammengehörige Inhalte.
class GainerCard extends StatelessWidget {
  const GainerCard({
    required this.child,
    this.padding = const EdgeInsets.all(GainerSpacing.m),
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: GainerDesign.colorsOf(context).surface,
        borderRadius: BorderRadius.circular(GainerRadii.card),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
