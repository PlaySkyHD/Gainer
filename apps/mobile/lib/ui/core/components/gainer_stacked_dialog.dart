import 'package:flutter/cupertino.dart';

import '../theme.dart';
import 'gainer_pill_button.dart';

/// Aktion im Bestätigungsdialog. Keine Aktion ist als Standard markiert.
final class GainerDialogAction<T> {
  const GainerDialogAction({
    required this.label,
    required this.value,
    this.destructive = false,
  });

  final String label;
  final T value;
  final bool destructive;
}

/// Zeigt den Dialog; liefert die gewählte Aktion oder null bei Abbruch über den Hintergrund.
Future<T?> showGainerStackedDialog<T>({
  required BuildContext context,
  required String title,
  required String message,
  required List<GainerDialogAction<T>> actions,
}) {
  return showCupertinoDialog<T>(
    context: context,
    builder: (_) => GainerStackedDialog<T>(
      title: title,
      message: message,
      actions: actions,
    ),
  );
}

/// Zentrierter, gerundeter Dialog mit gestapelten, vollbreiten Aktionen.
class GainerStackedDialog<T> extends StatelessWidget {
  const GainerStackedDialog({
    required this.title,
    required this.message,
    required this.actions,
    super.key,
  });

  final String title;
  final String message;
  final List<GainerDialogAction<T>> actions;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    // Bei großer Schrift scrollt der Dialog, statt abgeschnitten zu werden.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: _dialogBox(context, colors)),
        ),
      ),
    );
  }

  Widget _dialogBox(BuildContext context, GainerColors colors) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          GainerSpacing.m,
          GainerSpacing.l,
          GainerSpacing.m,
          GainerSpacing.m,
        ),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(GainerRadii.card),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: GainerTypography.cardTitle.copyWith(
                color: colors.primaryText,
              ),
            ),
            const SizedBox(height: GainerSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GainerTypography.body.copyWith(
                color: colors.secondaryText,
              ),
            ),
            const SizedBox(height: GainerSpacing.l),
            for (final (index, action) in actions.indexed) ...[
              if (index > 0) const SizedBox(height: GainerSpacing.xs),
              GainerPillButton(
                label: action.label,
                expand: true,
                variant: action.destructive
                    ? GainerPillVariant.destructive
                    : GainerPillVariant.tonal,
                onPressed: () => Navigator.of(context).pop<T>(action.value),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
