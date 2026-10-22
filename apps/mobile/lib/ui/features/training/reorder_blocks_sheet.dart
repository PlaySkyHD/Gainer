import 'package:flutter/cupertino.dart';

import '../../../domain/models/training/workout_model.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';

/// Eintrag im Neuordnen-Sheet: stabile ID und angezeigter Übungsname.
typedef ReorderItem = ({String id, String name});

/// Sheet zum Umordnen und Entfernen der Übungsblöcke. Änderungen gelten erst
/// mit „Fertig“. Liefert die Block-IDs in neuer Reihenfolge ohne entfernte
/// Blöcke, bei Abbrechen oder Schließen `null`.
Future<List<String>?> showReorderBlocksSheet(
  BuildContext context, {
  required List<WorkoutBlock> blocks,
}) {
  return showReorderItemsSheet(
    context,
    items: [
      for (final block in blocks)
        (id: block.workoutExerciseId, name: block.exerciseNameSnapshot),
    ],
    removalNote: 'und seine Sätze werden aus dem Training entfernt, sobald du fertig bist.',
    emptyNote: 'Keine Übungen mehr. Mit „Fertig“ wird das Training leer.',
  );
}

/// Allgemeine Form von [showReorderBlocksSheet]. [removalNote] folgt im
/// Bestätigungsdialog auf den Übungsnamen, [emptyNote] steht in der leeren
/// Liste.
Future<List<String>?> showReorderItemsSheet(
  BuildContext context, {
  required List<ReorderItem> items,
  required String removalNote,
  required String emptyNote,
}) {
  return showCupertinoModalPopup<List<String>>(
    context: context,
    builder: (_) => _ReorderItemsSheet(
      items: items,
      removalNote: removalNote,
      emptyNote: emptyNote,
    ),
  );
}

class _ReorderItemsSheet extends StatefulWidget {
  const _ReorderItemsSheet({
    required this.items,
    required this.removalNote,
    required this.emptyNote,
  });

  final List<ReorderItem> items;
  final String removalNote;
  final String emptyNote;

  @override
  State<_ReorderItemsSheet> createState() => _ReorderItemsSheetState();
}

class _ReorderItemsSheetState extends State<_ReorderItemsSheet> {
  late final List<ReorderItem> _items = [...widget.items];

  Future<void> _confirmRemove(ReorderItem item) async {
    final confirmed = await showGainerStackedDialog<bool>(
      context: context,
      title: 'Übung entfernen?',
      message: '„${item.name}“ ${widget.removalNote}',
      actions: const [
        GainerDialogAction(label: 'Entfernen', value: true, destructive: true),
        GainerDialogAction(label: 'Abbrechen', value: false),
      ],
    );
    if (confirmed != true || !mounted) return;
    setState(() => _items.remove(item));
  }

  void _move(int oldIndex, int newIndex) {
    setState(() => _items.insert(newIndex, _items.removeAt(oldIndex)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final maxListHeight = MediaQuery.sizeOf(context).height * 0.7;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(GainerSpacing.xs),
        padding: const EdgeInsets.fromLTRB(
          GainerSpacing.s,
          GainerSpacing.s,
          GainerSpacing.s,
          GainerSpacing.m,
        ),
        decoration: BoxDecoration(
          color: colors.elevatedSurface,
          borderRadius: BorderRadius.circular(GainerRadii.card),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(72, 44),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Abbrechen',
                    style: GainerTypography.label.copyWith(
                      color: colors.accent,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Übungen anordnen',
                    textAlign: TextAlign.center,
                    style: GainerTypography.cardTitle.copyWith(
                      color: colors.primaryText,
                    ),
                  ),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(72, 44),
                  onPressed: () =>
                      Navigator.of(context)
                          .pop([for (final item in _items) item.id]),
                  child: Text(
                    'Fertig',
                    textAlign: TextAlign.end,
                    style: GainerTypography.label.copyWith(
                      color: colors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: GainerSpacing.s),
            if (_items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: GainerSpacing.m),
                child: Text(
                  widget.emptyNote,
                  textAlign: TextAlign.center,
                  style: GainerTypography.label.copyWith(
                    color: colors.secondaryText,
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxListHeight),
                child: CustomScrollView(
                  shrinkWrap: true,
                  slivers: [
                    SliverReorderableList(
                      itemCount: _items.length,
                      onReorderItem: _move,
                      itemBuilder: (context, index) =>
                          _row(context, _items[index], index),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, ReorderItem item, int index) {
    final colors = GainerDesign.colorsOf(context);
    return Padding(
      key: ValueKey(item.id),
      padding: const EdgeInsets.only(bottom: GainerSpacing.xs),
      child: GainerCard(
        child: Row(
          children: [
            Semantics(
              button: true,
              label: 'Entfernen ${item.name}',
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size.square(36),
                onPressed: () => _confirmRemove(item),
                child: Icon(
                  CupertinoIcons.minus_circle_fill,
                  size: 24,
                  color: colors.destructive,
                ),
              ),
            ),
            const SizedBox(width: GainerSpacing.xs),
            Expanded(
              child: Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GainerTypography.cardTitle.copyWith(
                  color: colors.primaryText,
                ),
              ),
            ),
            ReorderableDragStartListener(
              index: index,
              child: Semantics(
                label: 'Ziehen zum Umordnen',
                child: Padding(
                  padding: const EdgeInsets.all(GainerSpacing.xxs),
                  child: Icon(
                    CupertinoIcons.line_horizontal_3,
                    size: 22,
                    color: colors.secondaryText,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
