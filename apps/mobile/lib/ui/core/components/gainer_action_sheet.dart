import 'package:flutter/cupertino.dart';

import '../theme.dart';
import 'gainer_card.dart';

/// Aktion im Kontext-Sheet. Gewählte Aktionen liefern `value` als Ergebnis.
final class GainerSheetAction<T> {
  const GainerSheetAction({
    required this.label,
    required this.icon,
    required this.value,
    this.destructive = false,
    this.hint,
  });

  final String label;
  final IconData icon;
  final T value;
  final bool destructive;

  /// Kurzer Hinweis unter dem Titel der Aktion.
  final String? hint;
}

/// Zeigt das Sheet; liefert die gewählte Aktion oder null bei Schließen ohne Auswahl.
Future<T?> showGainerActionSheet<T>({
  required BuildContext context,
  required String title,
  List<GainerSheetAction<T>> quickActions = const [],
  List<List<GainerSheetAction<T>>> groups = const [],
}) {
  return showCupertinoModalPopup<T>(
    context: context,
    builder: (_) => GainerActionSheet<T>(
      title: title,
      quickActions: quickActions,
      groups: groups,
    ),
  );
}

/// Gerundetes Bottom-Sheet: Titel mit X, Reihe gleich breiter Aktionen, darunter Gruppen.
class GainerActionSheet<T> extends StatelessWidget {
  const GainerActionSheet({
    required this.title,
    this.quickActions = const [],
    this.groups = const [],
    super.key,
  });

  final String title;
  final List<GainerSheetAction<T>> quickActions;
  final List<List<GainerSheetAction<T>>> groups;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return SafeArea(
      top: false,
      child: GestureDetector(
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) > 300) {
            Navigator.of(context).pop();
          }
        },
        child: Container(
          margin: const EdgeInsets.all(GainerSpacing.xs),
          padding: const EdgeInsets.fromLTRB(
            GainerSpacing.m,
            GainerSpacing.s,
            GainerSpacing.m,
            GainerSpacing.m,
          ),
          decoration: BoxDecoration(
            color: colors.elevatedSurface,
            borderRadius: BorderRadius.circular(GainerRadii.card),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const SizedBox(width: GainerRadii.iconButtonDiameter),
                    Expanded(
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: GainerTypography.cardTitle.copyWith(
                          color: colors.primaryText,
                        ),
                      ),
                    ),
                    _CloseButton(colors: colors),
                  ],
                ),
                if (quickActions.isNotEmpty) ...[
                  const SizedBox(height: GainerSpacing.s),
                  Row(
                    children: [
                      for (final action in quickActions)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: GainerSpacing.xxs,
                            ),
                            child: _QuickAction<T>(action: action),
                          ),
                        ),
                    ],
                  ),
                ],
                for (final group in groups) ...[
                  const SizedBox(height: GainerSpacing.s),
                  GainerCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < group.length; i++) ...[
                          if (i > 0)
                            Container(
                              height: 0.5,
                              margin: const EdgeInsets.only(
                                left: GainerSpacing.m,
                              ),
                              color: colors.separator,
                            ),
                          _GroupRow<T>(action: group[i]),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.colors});

  final GainerColors colors;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Schließen',
      excludeSemantics: true,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size.square(GainerRadii.iconButtonDiameter),
        color: colors.surface,
        borderRadius: BorderRadius.circular(GainerRadii.iconButtonDiameter / 2),
        onPressed: () => Navigator.of(context).pop(),
        child: Icon(CupertinoIcons.xmark, size: 18, color: colors.primaryText),
      ),
    );
  }
}

class _QuickAction<T> extends StatelessWidget {
  const _QuickAction({required this.action});

  final GainerSheetAction<T> action;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final tint = action.destructive ? colors.destructive : colors.accent;
    return Semantics(
      button: true,
      label: action.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop<T>(action.value),
        child: Container(
          constraints: const BoxConstraints(minHeight: 76),
          padding: const EdgeInsets.symmetric(
            horizontal: GainerSpacing.xxs,
            vertical: GainerSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(GainerRadii.card),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(action.icon, size: 26, color: tint),
              const SizedBox(height: GainerSpacing.xxs),
              Text(
                action.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GainerTypography.caption.copyWith(
                  color: action.destructive
                      ? colors.destructive
                      : colors.primaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupRow<T> extends StatelessWidget {
  const _GroupRow({required this.action});

  final GainerSheetAction<T> action;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Semantics(
      button: true,
      label: action.label,
      hint: action.hint,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop<T>(action.value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: GainerSpacing.m,
              vertical: 11,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        action.label,
                        style: GainerTypography.body.copyWith(
                          color: action.destructive
                              ? colors.destructive
                              : colors.primaryText,
                        ),
                      ),
                      if (action.hint case final hint?)
                        Text(
                          hint,
                          style: GainerTypography.label.copyWith(
                            color: colors.secondaryText,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  action.icon,
                  size: 20,
                  color: action.destructive
                      ? colors.destructive
                      : colors.secondaryText,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
