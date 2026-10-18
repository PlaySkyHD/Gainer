import 'package:flutter/cupertino.dart';

import '../theme.dart';

/// Suchfeld mit Lupe auf erhöhter Fläche.
class GainerSearchField extends StatelessWidget {
  const GainerSearchField({
    this.controller,
    this.placeholder = 'Suchen',
    this.onChanged,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController? controller;
  final String placeholder;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return CupertinoSearchTextField(
      controller: controller,
      placeholder: placeholder,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      backgroundColor: colors.elevatedSurface,
      borderRadius: BorderRadius.circular(GainerRadii.field),
      itemColor: colors.secondaryText,
      style: GainerTypography.body.copyWith(color: colors.primaryText),
      placeholderStyle: GainerTypography.body.copyWith(
        color: colors.placeholderText,
      ),
    );
  }
}
