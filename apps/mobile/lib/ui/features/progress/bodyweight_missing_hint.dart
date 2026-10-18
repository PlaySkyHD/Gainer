import 'package:flutter/cupertino.dart';

import '../../core/theme.dart';

/// Textlicher Hinweis, damit fehlendes Körpergewicht nicht nur über Farbe erkennbar ist.
class BodyweightMissingHint extends StatelessWidget {
  const BodyweightMissingHint({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          CupertinoIcons.exclamationmark_circle,
          size: 16,
          color: colors.warning,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Für korrekte Werte fehlt ein Check-in mit Körpergewicht.',
            style: GainerTypography.label.copyWith(color: colors.primaryText),
          ),
        ),
      ],
    );
  }
}
