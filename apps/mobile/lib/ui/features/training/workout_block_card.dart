import 'package:flutter/cupertino.dart';

import '../../../domain/models/training/workout_model.dart';
import '../../../domain/models/training/workout_rules.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'set_row.dart';
import 'workout_history_sheet.dart';
import 'workout_text_sheet.dart';
import 'workout_view_model.dart';

enum _BlockAction { note, addSet, connect, detach }

enum _SetAction { duplicate, moveUp, moveDown, remove }

/// Übungskarte: Name, Stammnotiz (nur lesend), Blocknotiz, Satzzeilen und
/// Fußzeile mit „Satz hinzufügen“, Verlauf, Graph und Rekorden.
/// [supersetLabel] (A, B, …) kennzeichnet Blöcke innerhalb eines Supersets.
/// Graph und Rekorde sind Platzhalter, bis ihre Sheets existieren; ohne
/// Callback sind die Buttons deaktiviert.
class WorkoutBlockCard extends StatelessWidget {
  const WorkoutBlockCard({
    required this.viewModel,
    required this.block,
    required this.fieldFocus,
    this.supersetLabel,
    this.onShowChart,
    this.onShowRecords,
    this.onEditingChanged,
    super.key,
  });

  final WorkoutViewModel viewModel;
  final WorkoutBlock block;
  final SetFieldFocus fieldFocus;
  final String? supersetLabel;
  final VoidCallback? onShowChart;
  final VoidCallback? onShowRecords;

  /// Meldet, ob ein Zahlenfeld dieser Übung den Fokus hat.
  final ValueChanged<bool>? onEditingChanged;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final labels = setLabels(block.sets);
    final previous =
        viewModel.previousValues[block.workoutExerciseId] ?? const [];
    final stammnotiz = viewModel.exerciseNoteFor(block);
    final notes = block.notes;
    final complete = isBlockComplete(block);
    return GainerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (supersetLabel case final letter?) ...[
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    letter,
                    style: GainerTypography.caption.copyWith(
                      color: colors.onAccent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: GainerSpacing.xs),
              ],
              Expanded(
                child: Text(
                  block.exerciseNameSnapshot,
                  style: GainerTypography.cardTitle.copyWith(
                    color: colors.primaryText,
                  ),
                ),
              ),
              if (complete)
                Padding(
                  padding: const EdgeInsets.only(left: GainerSpacing.xs),
                  child: Semantics(
                    label: 'Übung vollständig',
                    child: Icon(
                      CupertinoIcons.checkmark_circle_fill,
                      size: 20,
                      color: colors.accent,
                    ),
                  ),
                ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size.square(36),
                onPressed: () => _showBlockMenu(context),
                child: Semantics(
                  label: 'Übungsmenü',
                  child: Icon(
                    CupertinoIcons.ellipsis,
                    size: 20,
                    color: colors.secondaryText,
                  ),
                ),
              ),
            ],
          ),
          if (stammnotiz != null && stammnotiz.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: GainerSpacing.xxs),
              child: Text(
                stammnotiz,
                style: GainerTypography.label.copyWith(
                  color: colors.secondaryText,
                ),
              ),
            ),
          if (notes != null && notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: GainerSpacing.xxs),
              child: Text(
                notes,
                style: GainerTypography.label.copyWith(
                  color: colors.primaryText,
                ),
              ),
            ),
          const SizedBox(height: GainerSpacing.s),
          if (block.sets.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: GainerSpacing.xs),
              child: Text(
                'Noch keine Sätze.',
                style: GainerTypography.label.copyWith(
                  color: colors.secondaryText,
                ),
              ),
            ),
          for (var index = 0; index < block.sets.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: GainerSpacing.s),
              child: SetRow(
                key: ValueKey(block.sets[index].setId),
                loggedSet: block.sets[index],
                label: labels[index],
                kind: block.exerciseTypeSnapshot,
                unit: viewModel.weightUnit,
                showRir: viewModel.showRir,
                weightFocus: fieldFocus.node(
                  block.sets[index].setId,
                  SetField.weight,
                ),
                repetitionsFocus: fieldFocus.node(
                  block.sets[index].setId,
                  SetField.repetitions,
                ),
                rirFocus: fieldFocus.node(
                  block.sets[index].setId,
                  SetField.rir,
                ),
                previous: index < previous.length ? previous[index] : null,
                onWeightChanged: (kg) => viewModel.setWeight(
                  block.workoutExerciseId,
                  block.sets[index].setId,
                  kg,
                ),
                onRepetitionsChanged: (repetitions) => viewModel.setRepetitions(
                  block.workoutExerciseId,
                  block.sets[index].setId,
                  repetitions,
                ),
                onRirChanged: (rir) => viewModel.setRir(
                  block.workoutExerciseId,
                  block.sets[index].setId,
                  rir,
                ),
                onLabelTap: () => viewModel.applyPreviousValues(
                  block.workoutExerciseId,
                  block.sets[index].setId,
                ),
                onNotesTap: () => _editSetNotes(context, block.sets[index]),
                onMenuTap: () => _showSetMenu(context, index, labels[index]),
                onEditingChanged: onEditingChanged,
              ),
            ),
          Row(
            children: [
              Flexible(
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size.square(36),
                  onPressed: () => viewModel.addSet(block.workoutExerciseId),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.add, size: 18, color: colors.accent),
                      const SizedBox(width: GainerSpacing.xxs),
                      Flexible(
                        child: Text(
                          'Satz hinzufügen',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GainerTypography.label.copyWith(
                            color: colors.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _FooterIconButton(
                icon: CupertinoIcons.clock,
                semanticLabel: 'Verlauf',
                onPressed: () => _showHistory(context),
              ),
              const SizedBox(width: GainerSpacing.xs),
              _FooterIconButton(
                icon: CupertinoIcons.chart_bar,
                semanticLabel: 'Graph',
                onPressed: onShowChart,
              ),
              const SizedBox(width: GainerSpacing.xs),
              _FooterIconButton(
                icon: CupertinoIcons.rosette,
                semanticLabel: 'Rekorde',
                onPressed: onShowRecords,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showHistory(BuildContext context) {
    showWorkoutHistorySheet(
      context: context,
      exerciseName: block.exerciseNameSnapshot,
      entries: viewModel.historyFor(block),
      unit: viewModel.weightUnit,
    );
  }

  Future<void> _showBlockMenu(BuildContext context) async {
    final next = viewModel.blockAfter(block.workoutExerciseId);
    final inSuperset = block.supersetId != null;
    final connectedToNext = inSuperset && next?.supersetId == block.supersetId;
    final action = await showGainerActionSheet<_BlockAction>(
      context: context,
      title: block.exerciseNameSnapshot,
      quickActions: [
        const GainerSheetAction(
          label: 'Notiz',
          icon: CupertinoIcons.doc_text,
          value: _BlockAction.note,
        ),
        const GainerSheetAction(
          label: 'Satz',
          icon: CupertinoIcons.add,
          value: _BlockAction.addSet,
        ),
        if (next != null && !connectedToNext)
          const GainerSheetAction(
            label: 'Verbinden',
            icon: CupertinoIcons.link,
            value: _BlockAction.connect,
          ),
        if (inSuperset)
          const GainerSheetAction(
            label: 'Lösen',
            icon: CupertinoIcons.link_circle_fill,
            value: _BlockAction.detach,
          ),
      ],
    );
    if (!context.mounted) return;
    switch (action) {
      case _BlockAction.note:
        final text = await showWorkoutTextSheet(
          context: context,
          title: 'Notiz zur Übung',
          initialText: block.notes ?? '',
          placeholder: 'Notiz nur für dieses Training',
          multiline: true,
        );
        if (text != null) {
          await viewModel.setBlockNotes(block.workoutExerciseId, text);
        }
      case _BlockAction.addSet:
        await viewModel.addSet(block.workoutExerciseId);
      case _BlockAction.connect:
        await viewModel.connectWithNextBlock(block.workoutExerciseId);
      case _BlockAction.detach:
        await viewModel.detachFromSuperset(block.workoutExerciseId);
      case null:
    }
  }

  Future<void> _showSetMenu(
    BuildContext context,
    int index,
    String label,
  ) async {
    final set = block.sets[index];
    final last = block.sets.length - 1;
    final choice = await showGainerActionSheet<Object>(
      context: context,
      title: 'Satz $label',
      quickActions: [
        const GainerSheetAction<Object>(
          label: 'Duplizieren',
          icon: CupertinoIcons.doc_on_doc,
          value: _SetAction.duplicate,
        ),
        if (index > 0)
          const GainerSheetAction<Object>(
            label: 'Nach oben',
            icon: CupertinoIcons.arrow_up,
            value: _SetAction.moveUp,
          ),
        if (index < last)
          const GainerSheetAction<Object>(
            label: 'Nach unten',
            icon: CupertinoIcons.arrow_down,
            value: _SetAction.moveDown,
          ),
      ],
      groups: [
        [
          for (final type in SetType.values)
            GainerSheetAction<Object>(
              label: _setTypeLabel(type, current: type == set.setType),
              icon: _setTypeIcon(type),
              value: type,
            ),
        ],
        const [
          GainerSheetAction<Object>(
            label: 'Entfernen',
            icon: CupertinoIcons.trash,
            value: _SetAction.remove,
            destructive: true,
          ),
        ],
      ],
    );
    if (!context.mounted) return;
    final blockId = block.workoutExerciseId;
    switch (choice) {
      case SetType type:
        await viewModel.setSetType(blockId, set.setId, type);
      case _SetAction.duplicate:
        await viewModel.duplicateSet(blockId, set.setId);
      case _SetAction.moveUp:
        await viewModel.moveSet(blockId, set.setId, -1);
      case _SetAction.moveDown:
        await viewModel.moveSet(blockId, set.setId, 1);
      case _SetAction.remove:
        await viewModel.removeSet(blockId, set.setId);
      case _:
    }
  }

  Future<void> _editSetNotes(BuildContext context, LoggedSet set) async {
    final text = await showWorkoutTextSheet(
      context: context,
      title: 'Notiz zum Satz',
      initialText: set.notes ?? '',
      placeholder: 'Notiz zum Satz',
      multiline: true,
    );
    if (text != null) {
      await viewModel.setSetNotes(block.workoutExerciseId, set.setId, text);
    }
  }
}

String _setTypeLabel(SetType type, {required bool current}) {
  final name = switch (type) {
    SetType.normal => 'Normaler Satz',
    SetType.warmup => 'Aufwärmsatz',
    SetType.dropset => 'Dropsatz',
  };
  return current ? '$name (aktuell)' : name;
}

IconData _setTypeIcon(SetType type) => switch (type) {
  SetType.normal => CupertinoIcons.circle,
  SetType.warmup => CupertinoIcons.flame,
  SetType.dropset => CupertinoIcons.arrow_down_circle,
};

class _FooterIconButton extends StatelessWidget {
  const _FooterIconButton({
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      excludeSemantics: true,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size.square(36),
        color: colors.elevatedSurface,
        disabledColor: colors.elevatedSurface,
        borderRadius: BorderRadius.circular(18),
        onPressed: onPressed,
        child: Icon(
          icon,
          size: 18,
          color: enabled ? colors.accent : colors.placeholderText,
        ),
      ),
    );
  }
}
