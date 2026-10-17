import 'package:flutter/cupertino.dart';

import '../../../domain/models/training/workout_model.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';

/// Sheet zum Umordnen und Entfernen der Übungsblöcke. Änderungen gelten erst
/// mit „Fertig“. Liefert die Block-IDs in neuer Reihenfolge ohne entfernte
/// Blöcke, bei Abbrechen oder Schließen `null`.
Future<List<String>?> showReorderBlocksSheet(
  BuildContext context, {
  required List<WorkoutBlock> blocks,
}) {
  return showCupertinoModalPopup<List<String>>(
    context: context,
    builder: (_) => _ReorderBlocksSheet(blocks: blocks),
  );
}

class _ReorderBlocksSheet extends StatefulWidget {
  const _ReorderBlocksSheet({required this.blocks});

  final List<WorkoutBlock> blocks;

  @override
  State<_ReorderBlocksSheet> createState() => _ReorderBlocksSheetState();
}

class _ReorderBlocksSheetState extends State<_ReorderBlocksSheet> {
  late final List<WorkoutBlock> _blocks = [...widget.blocks];

  Future<void> _confirmRemove(WorkoutBlock block) async {
    final confirmed = await showGainerStackedDialog<bool>(
      context: context,
      title: 'Übung entfernen?',
      message:
          '„${block.exerciseNameSnapshot}“ und seine Sätze werden aus dem Training entfernt, sobald du fertig bist.',
      actions: const [
        GainerDialogAction(label: 'Entfernen', value: true, destructive: true),
        GainerDialogAction(label: 'Abbrechen', value: false),
      ],
    );
    if (confirmed != true || !mounted) return;
    setState(() => _blocks.remove(block));
  }

  void _move(int oldIndex, int newIndex) {
    setState(() => _blocks.insert(newIndex, _blocks.removeAt(oldIndex)));
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
                  onPressed: () => Navigator.of(
                    context,
                  ).pop([for (final block in _blocks) block.workoutExerciseId]),
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
            if (_blocks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: GainerSpacing.m),
                child: Text(
                  'Keine Übungen mehr. Mit „Fertig“ wird das Training leer.',
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
                      itemCount: _blocks.length,
                      onReorderItem: _move,
                      itemBuilder: (context, index) =>
                          _row(context, _blocks[index], index),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, WorkoutBlock block, int index) {
    final colors = GainerDesign.colorsOf(context);
    return Padding(
      key: ValueKey(block.workoutExerciseId),
      padding: const EdgeInsets.only(bottom: GainerSpacing.xs),
      child: GainerCard(
        child: Row(
          children: [
            Semantics(
              button: true,
              label: 'Entfernen ${block.exerciseNameSnapshot}',
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size.square(36),
                onPressed: () => _confirmRemove(block),
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
                block.exerciseNameSnapshot,
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
