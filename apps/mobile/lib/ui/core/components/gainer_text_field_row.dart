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
    // Bei sehr großer Schrift steht die Beschriftung über der Eingabe.
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.5;
    final labelText = Text(
      label,
      style: GainerTypography.body.copyWith(color: colors.primaryText),
    );
    final field = CupertinoTextField.borderless(
      key: fieldKey,
      controller: controller,
      placeholder: placeholder,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      textAlign: stacked ? TextAlign.start : textAlign,
      padding: const EdgeInsets.symmetric(vertical: 6),
      style: GainerTypography.body.copyWith(color: colors.primaryText),
      placeholderStyle: GainerTypography.body.copyWith(
        color: colors.placeholderText,
      ),
      // Die Einheit gehört zum Feld und steht immer am rechten Rand.
      suffix: switch (unit) {
        final suffix? => Padding(
          padding: const EdgeInsets.only(left: GainerSpacing.xxs),
          child: Text(
            suffix,
            style: GainerTypography.body.copyWith(color: colors.secondaryText),
          ),
        ),
        null => null,
      },
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: GainerSpacing.m,
        vertical: GainerSpacing.xxs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (stacked) ...[
            labelText,
            field,
          ] else
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 36),
              // Die Beschriftung nimmt höchstens die halbe Breite, die Eingabe
              // füllt den Rest bis zum rechten Rand.
              child: LayoutBuilder(
                builder: (context, constraints) => Row(
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth / 2,
                      ),
                      child: labelText,
                    ),
                    const SizedBox(width: GainerSpacing.s),
                    Expanded(child: field),
                  ],
                ),
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
