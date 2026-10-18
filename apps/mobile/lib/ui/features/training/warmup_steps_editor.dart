import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../../domain/models/training/warmup.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';

/// Liste der Aufwärmstufen: Prozent, optionale Wiederholungen, Löschen und
/// „+ Stufe“ (höchstens [maxWarmupSteps]). Ungültige Eingaben (außerhalb der
/// Grenzen) behalten den letzten gültigen Wert der Stufe.
class WarmupStepsEditor extends StatefulWidget {
  const WarmupStepsEditor({
    required this.initialSteps,
    required this.onChanged,
    super.key,
  });

  final List<WarmupStep> initialSteps;
  final ValueChanged<List<WarmupStep>> onChanged;

  @override
  State<WarmupStepsEditor> createState() => _WarmupStepsEditorState();
}

class _StepRow {
  _StepRow(this.id, WarmupStep step)
    : value = step,
      percent = TextEditingController(text: '${step.percent}'),
      repetitions = TextEditingController(text: '${step.repetitions ?? ''}');

  final int id;
  WarmupStep value;
  final TextEditingController percent;
  final TextEditingController repetitions;

  void dispose() {
    percent.dispose();
    repetitions.dispose();
  }
}

class _WarmupStepsEditorState extends State<WarmupStepsEditor> {
  final List<_StepRow> _rows = [];
  int _nextId = 0;

  @override
  void initState() {
    super.initState();
    for (final step in widget.initialSteps) {
      _rows.add(_StepRow(_nextId++, step));
    }
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _emit() => widget.onChanged([for (final row in _rows) row.value]);

  void _changed(_StepRow row) {
    final percent = int.tryParse(row.percent.text.trim());
    final repsText = row.repetitions.text.trim();
    final reps = repsText.isEmpty ? null : int.tryParse(repsText);
    final percentValid =
        percent != null &&
        percent >= minWarmupPercent &&
        percent <= maxWarmupPercent;
    final repsValid =
        repsText.isEmpty ||
        (reps != null &&
            reps >= minWarmupRepetitions &&
            reps <= maxWarmupRepetitions);
    row.value = WarmupStep(
      percent: percentValid ? percent : row.value.percent,
      repetitions: repsValid ? reps : row.value.repetitions,
    );
    _emit();
  }

  void _add() {
    if (_rows.length >= maxWarmupSteps) return;
    final last = _rows.isEmpty ? null : _rows.last.value.percent;
    final percent = last == null ? 50 : (last + 10).clamp(1, 100);
    setState(
      () => _rows.add(_StepRow(_nextId++, WarmupStep(percent: percent))),
    );
    _emit();
  }

  void _remove(_StepRow row) {
    setState(() => _rows.remove(row));
    row.dispose();
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_rows.isNotEmpty)
          GainerGroupedSection(
            children: [
              for (var i = 0; i < _rows.length; i++)
                _StepRowView(
                  key: ValueKey('warmup-step-${_rows[i].id}'),
                  index: i,
                  row: _rows[i],
                  onChanged: () => _changed(_rows[i]),
                  onDelete: () => _remove(_rows[i]),
                ),
            ],
          ),
        if (_rows.length < maxWarmupSteps)
          Align(
            alignment: Alignment.centerLeft,
            child: CupertinoButton(
              key: const ValueKey('warmup-add-step'),
              padding: const EdgeInsets.symmetric(vertical: GainerSpacing.xs),
              minimumSize: const Size.square(36),
              onPressed: _add,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.add, size: 18, color: colors.accent),
                  const SizedBox(width: GainerSpacing.xxs),
                  Text(
                    'Stufe',
                    style: GainerTypography.label.copyWith(
                      color: colors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _StepRowView extends StatelessWidget {
  const _StepRowView({
    required this.index,
    required this.row,
    required this.onChanged,
    required this.onDelete,
    super.key,
  });

  final int index;
  final _StepRow row;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: GainerSpacing.m,
        vertical: GainerSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: _NumberField(
              fieldKey: ValueKey('warmup-percent-$index'),
              controller: row.percent,
              placeholder: 'Anteil',
              suffix: '%',
              semanticLabel: 'Anteil der Stufe ${index + 1}',
              onChanged: onChanged,
            ),
          ),
          const SizedBox(width: GainerSpacing.s),
          Expanded(
            child: _NumberField(
              fieldKey: ValueKey('warmup-reps-$index'),
              controller: row.repetitions,
              placeholder: 'Wdh.',
              suffix: '×',
              semanticLabel: 'Wiederholungen der Stufe ${index + 1}',
              onChanged: onChanged,
            ),
          ),
          Semantics(
            button: true,
            label: 'Stufe ${index + 1} löschen',
            excludeSemantics: true,
            child: CupertinoButton(
              key: ValueKey('warmup-delete-$index'),
              padding: EdgeInsets.zero,
              minimumSize: const Size.square(36),
              onPressed: onDelete,
              child: Icon(
                CupertinoIcons.minus_circle_fill,
                size: 22,
                color: colors.destructive,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.fieldKey,
    required this.controller,
    required this.placeholder,
    required this.suffix,
    required this.semanticLabel,
    required this.onChanged,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String placeholder;
  final String suffix;
  final String semanticLabel;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Semantics(
      label: semanticLabel,
      child: CupertinoTextField(
        key: fieldKey,
        controller: controller,
        placeholder: placeholder,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(3),
        ],
        textAlign: TextAlign.right,
        onChanged: (_) => onChanged(),
        suffix: Padding(
          padding: const EdgeInsets.only(right: GainerSpacing.xs),
          child: Text(
            suffix,
            style: GainerTypography.body.copyWith(color: colors.secondaryText),
          ),
        ),
        placeholderStyle: GainerTypography.body.copyWith(
          color: colors.placeholderText,
        ),
        style: GainerTypography.body.copyWith(color: colors.primaryText),
        padding: const EdgeInsets.symmetric(
          horizontal: GainerSpacing.xs,
          vertical: GainerSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: colors.elevatedSurface,
          borderRadius: BorderRadius.circular(GainerRadii.field),
        ),
      ),
    );
  }
}
