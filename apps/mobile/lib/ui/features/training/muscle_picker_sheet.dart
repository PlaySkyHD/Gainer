import 'package:flutter/cupertino.dart';

import '../../../domain/models/training/muscles.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';

/// Mehrfachauswahl von Muskeln. [locked] sind in der anderen Liste gewählt
/// und hier gesperrt; der Wert ist die Beschriftung, z. B. „Hauptmuskel“.
/// Liefert die neue Auswahl oder `null` beim Schließen ohne „Fertig“.
Future<List<Muscle>?> showMusclePickerSheet(
  BuildContext context, {
  required String title,
  required List<Muscle> selected,
  required int maximum,
  Map<Muscle, String> locked = const {},
}) {
  return showGainerSheet<List<Muscle>>(
    context: context,
    heightFactor: 0.85,
    builder: (_) => _MusclePickerSheet(
      title: title,
      initial: selected,
      maximum: maximum,
      locked: locked,
    ),
  );
}

class _MusclePickerSheet extends StatefulWidget {
  const _MusclePickerSheet({
    required this.title,
    required this.initial,
    required this.maximum,
    required this.locked,
  });

  final String title;
  final List<Muscle> initial;
  final int maximum;
  final Map<Muscle, String> locked;

  @override
  State<_MusclePickerSheet> createState() => _MusclePickerSheetState();
}

class _MusclePickerSheetState extends State<_MusclePickerSheet> {
  late final List<Muscle> _selected = [...widget.initial];

  bool get _full => _selected.length >= widget.maximum;

  void _toggle(Muscle muscle) {
    setState(() {
      if (!_selected.remove(muscle) && !_full) _selected.add(muscle);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GainerSheetHeader(
          title: widget.title,
          trailing: GainerPillButton(
            key: const ValueKey('muscle-picker-done'),
            label: 'Fertig',
            onPressed: () => Navigator.of(context).pop(_selected),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(GainerSpacing.m),
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  left: GainerSpacing.m,
                  bottom: GainerSpacing.s,
                ),
                child: Text(
                  'Höchstens ${widget.maximum}. ${_selected.length} gewählt.',
                  style: GainerTypography.caption.copyWith(
                    color: colors.secondaryText,
                  ),
                ),
              ),
              for (final (group, muscles) in muscleGroups) ...[
                GainerGroupedSection(
                  header: group,
                  children: [
                    for (final muscle in muscles) _row(muscle, colors),
                  ],
                ),
                const SizedBox(height: GainerSpacing.s),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(Muscle muscle, GainerColors colors) {
    final lockedReason = widget.locked[muscle];
    final isSelected = _selected.contains(muscle);
    final enabled = lockedReason == null && (isSelected || !_full);
    return GainerListRow(
      key: ValueKey('muscle-option-${muscle.name}'),
      title: muscle.label,
      subtitle: lockedReason,
      trailing: isSelected
          ? Icon(CupertinoIcons.checkmark, color: colors.accent, size: 20)
          : null,
      onTap: enabled ? () => _toggle(muscle) : null,
    );
  }
}
