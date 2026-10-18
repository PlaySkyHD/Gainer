import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Formularzeile für gruppierte Karten: Beschriftung links, Eingabe rechts
/// ohne eigenen Rahmen, optional mit Einheit dahinter.
class GainerTextFieldRow extends StatelessWidget {
  const GainerTextFieldRow({
    required this.label,
    this.controller,
    this.placeholder,
    this.unit,
    this.keyboardType,
    this.inputFormatters,
    this.onChanged,
    this.errorText,
    this.textAlign = TextAlign.right,
    this.fieldKey,
    super.key,
  });

  final String label;
  final TextEditingController? controller;
  final String? placeholder;
  final String? unit;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final String? errorText;
  final TextAlign textAlign;

  /// Schlüssel des Eingabefelds, damit Tests es direkt finden.
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final error = errorText;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: GainerSpacing.m,
        vertical: GainerSpacing.xxs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: GainerTypography.body.copyWith(
                      color: colors.primaryText,
                    ),
                  ),
                ),
                const SizedBox(width: GainerSpacing.s),
                Expanded(
                  child: CupertinoTextField.borderless(
                    key: fieldKey,
                    controller: controller,
                    placeholder: placeholder,
                    keyboardType: keyboardType,
                    inputFormatters: inputFormatters,
                    onChanged: onChanged,
                    textAlign: textAlign,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    style: GainerTypography.body.copyWith(
                      color: colors.primaryText,
                    ),
                    placeholderStyle: GainerTypography.body.copyWith(
                      color: colors.placeholderText,
                    ),
                  ),
                ),
                if (unit case final suffix?) ...[
                  const SizedBox(width: GainerSpacing.xxs),
                  Text(
                    suffix,
                    style: GainerTypography.body.copyWith(
                      color: colors.secondaryText,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: GainerSpacing.xxs),
              child: Text(
                error,
                style: GainerTypography.label.copyWith(
                  color: colors.destructive,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
