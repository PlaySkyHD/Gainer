import 'package:flutter/cupertino.dart';

import '../../../domain/models/training/training_plan_model.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';

const _maxWarmupSets = 20;
const _maxWorkingSets = 50;
const _maxSetsPerEntry = 50;

/// Ergebnis des Eintrag-Editors. [entry] null bedeutet „Entfernen“.
final class PlanEntryEdit {
  const PlanEntryEdit({required this.entry, this.unlinkSuperset = false});

  const PlanEntryEdit.removed() : entry = null, unlinkSuperset = false;

  final PlanEntry? entry;

  /// Löst das Superset des Eintrags auf; betrifft alle Einträge der Gruppe.
  final bool unlinkSuperset;
}

/// Zeigt den Eintrag-Editor als Sheet. Liefert null, wenn ohne Änderung geschlossen wird.
Future<PlanEntryEdit?> showPlanEntryEditor(
  BuildContext context, {
  required PlanEntry entry,
  required String exerciseName,
}) {
  return showCupertinoModalPopup<PlanEntryEdit>(
    context: context,
    builder: (_) => GainerKeyboardInset(
      child: _PlanEntryEditorSheet(entry: entry, exerciseName: exerciseName),
    ),
  );
}

class _PlanEntryEditorSheet extends StatefulWidget {
  const _PlanEntryEditorSheet({
    required this.entry,
    required this.exerciseName,
  });

  final PlanEntry entry;
  final String exerciseName;

  @override
  State<_PlanEntryEditorSheet> createState() => _PlanEntryEditorSheetState();
}

class _PlanEntryEditorSheetState extends State<_PlanEntryEditorSheet> {
  late int _warmupSets = widget.entry.warmupSets;
  late int _workingSets = widget.entry.workingSets;
  late final _notesController = TextEditingController(
    text: widget.entry.notes ?? '',
  );

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  /// Gleiche Grenzen wie im Plan: mindestens ein Satz, höchstens 50 insgesamt.
  String? get _setsError {
    final total = _warmupSets + _workingSets;
    if (total < 1) return 'Ein Eintrag braucht mindestens einen Satz.';
    if (total > _maxSetsPerEntry) {
      return 'Ein Eintrag darf höchstens $_maxSetsPerEntry Sätze haben.';
    }
    return null;
  }

  /// Eintrag mit den Werten aus dem Sheet.
  PlanEntry _edited() {
    final notes = _notesController.text.trim();
    return widget.entry.copyWith(
      warmupSets: _warmupSets,
      workingSets: _workingSets,
      notes: () => notes.isEmpty ? null : notes,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final setsError = _setsError;
    return SafeArea(
      top: false,
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
                      widget.exerciseName,
                      textAlign: TextAlign.center,
                      style: GainerTypography.cardTitle.copyWith(
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size.square(
                      GainerRadii.iconButtonDiameter,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Icon(
                      CupertinoIcons.xmark,
                      color: colors.secondaryText,
                      semanticLabel: 'Schließen',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: GainerSpacing.s),
              GainerCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: GainerSpacing.m,
                  vertical: GainerSpacing.xs,
                ),
                child: Column(
                  children: [
                    _Stepper(
                      label: 'Aufwärmsätze',
                      hint: '0–$_maxWarmupSets',
                      value: _warmupSets,
                      max: _maxWarmupSets,
                      onChanged: (value) => setState(() => _warmupSets = value),
                    ),
                    _Stepper(
                      label: 'Arbeitssätze',
                      hint: '0–$_maxWorkingSets',
                      value: _workingSets,
                      max: _maxWorkingSets,
                      onChanged: (value) =>
                          setState(() => _workingSets = value),
                    ),
                  ],
                ),
              ),
              if (setsError != null)
                Padding(
                  padding: const EdgeInsets.only(top: GainerSpacing.xs),
                  child: Text(
                    setsError,
                    style: GainerTypography.caption.copyWith(
                      color: colors.destructive,
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: GainerSpacing.xs),
                  child: Text(
                    'Aufwärm- und Arbeitssätze zusammen: 1–$_maxSetsPerEntry.',
                    style: GainerTypography.caption.copyWith(
                      color: colors.secondaryText,
                    ),
                  ),
                ),
              const SizedBox(height: GainerSpacing.m),
              CupertinoTextField(
                controller: _notesController,
                placeholder: 'Notiz zur Übung',
                placeholderStyle: GainerTypography.body.copyWith(
                  color: colors.placeholderText,
                ),
                style: GainerTypography.body.copyWith(
                  color: colors.primaryText,
                ),
                minLines: 2,
                maxLines: 4,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(GainerRadii.field),
                ),
              ),
              const SizedBox(height: GainerSpacing.m),
              GainerPillButton(
                label: 'Fertig',
                expand: true,
                onPressed: setsError != null
                    ? null
                    : () =>
                          Navigator.of(context)
                              .pop(PlanEntryEdit(entry: _edited())),
              ),
              if (widget.entry.supersetId != null) ...[
                const SizedBox(height: GainerSpacing.xs),
                GainerPillButton(
                  label: 'Superset lösen',
                  variant: GainerPillVariant.tonal,
                  expand: true,
                  onPressed: setsError != null
                      ? null
                      : () => Navigator.of(context).pop(
                          PlanEntryEdit(entry: _edited(), unlinkSuperset: true),
                        ),
                ),
              ],
              const SizedBox(height: GainerSpacing.xs),
              GainerPillButton(
                label: 'Entfernen',
                variant: GainerPillVariant.destructive,
                expand: true,
                onPressed: () =>
                    Navigator.of(context).pop(const PlanEntryEdit.removed()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Zeile mit Bezeichnung, Wertebereich und Plus-/Minus-Schaltflächen.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.hint,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: GainerSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GainerTypography.body.copyWith(
                    color: colors.primaryText,
                  ),
                ),
                Text(
                  hint,
                  style: GainerTypography.caption.copyWith(
                    color: colors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          _StepButton(
            icon: CupertinoIcons.minus_circle,
            semanticLabel: '$label verringern',
            onPressed: value > 0 ? () => onChanged(value - 1) : null,
          ),
          SizedBox(
            width: 36,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: GainerTypography.value.copyWith(color: colors.primaryText),
            ),
          ),
          _StepButton(
            icon: CupertinoIcons.plus_circle,
            semanticLabel: '$label erhöhen',
            onPressed: value < max ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
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
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size.square(GainerRadii.iconButtonDiameter),
      onPressed: onPressed,
      child: Icon(
        icon,
        size: 28,
        color: onPressed == null ? colors.placeholderText : colors.accent,
        semanticLabel: semanticLabel,
      ),
    );
  }
}
