import 'package:flutter/cupertino.dart';

import '../theme.dart';
import 'gainer_stacked_dialog.dart';

/// Fragt mit einem gestapelten Dialog nach, ob gelöscht werden soll.
Future<bool> confirmGainerDelete(
  BuildContext context, {
  required String title,
  required String message,
  String deleteLabel = 'Löschen',
}) async {
  final confirmed = await showGainerStackedDialog<bool>(
    context: context,
    title: title,
    message: message,
    actions: [
      GainerDialogAction(label: deleteLabel, value: true, destructive: true),
      const GainerDialogAction(label: 'Abbrechen', value: false),
    ],
  );
  return confirmed ?? false;
}

/// Listenzeile, die sich nach links wischen und nach Bestätigung löschen lässt.
class GainerSwipeToDelete extends StatelessWidget {
  const GainerSwipeToDelete({
    required this.dismissKey,
    required this.confirm,
    required this.onDeleted,
    required this.child,
    this.label = 'Löschen',
    super.key,
  });

  final Key dismissKey;

  /// Liefert true, wenn wirklich gelöscht werden soll.
  final Future<bool> Function() confirm;
  final VoidCallback onDeleted;
  final Widget child;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Dismissible(
      key: dismissKey,
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => confirm(),
      onDismissed: (_) => onDeleted(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: GainerSpacing.m),
        color: colors.destructive,
        child: Text(
          label,
          style: GainerTypography.body.copyWith(
            color: CupertinoColors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      child: child,
    );
  }
}

/// Rotes Minus für den Bearbeiten-Modus einer Liste.
class GainerDeleteMinusButton extends StatelessWidget {
  const GainerDeleteMinusButton({
    required this.semanticLabel,
    required this.onPressed,
    super.key,
  });

  final String semanticLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size.square(GainerRadii.iconButtonDiameter),
        onPressed: onPressed,
        child: Icon(
          CupertinoIcons.minus_circle_fill,
          color: colors.destructive,
        ),
      ),
    );
  }
}
