import 'package:flutter/cupertino.dart';

import '../../../domain/models/training/training_plan_model.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'training_plans_view_model.dart';

/// Rotation verwalten: Pläne in die Reihenfolge der Rotation aufnehmen und ordnen.
/// Liefert true, wenn die Rotation gespeichert wurde.
Future<bool?> showPlanRotationSheet(
  BuildContext context, {
  required TrainingPlansViewModel viewModel,
}) {
  return showCupertinoModalPopup<bool>(
    context: context,
    builder: (_) => _PlanRotationSheet(viewModel: viewModel),
  );
}

class _PlanRotationSheet extends StatefulWidget {
  const _PlanRotationSheet({required this.viewModel});

  final TrainingPlansViewModel viewModel;

  @override
  State<_PlanRotationSheet> createState() => _PlanRotationSheetState();
}

class _PlanRotationSheetState extends State<_PlanRotationSheet> {
  late List<String> _ordered = _initialOrder();
  String? _error;
  bool _saving = false;

  /// Gespeicherte Rotation, auf aktive Pläne beschränkt und in gespeicherter Reihenfolge.
  List<String> _initialOrder() {
    final active = {for (final plan in widget.viewModel.plans) plan.planId};
    return [
      for (final id in widget.viewModel.rotation?.planIds ?? const <String>[])
        if (active.contains(id)) id,
    ];
  }

  TrainingPlanModel? _planOf(String planId) {
    for (final plan in widget.viewModel.plans) {
      if (plan.planId == planId) return plan;
    }
    return null;
  }

  void _move(int index, int delta) {
    setState(() {
      final target = index + delta;
      final ids = [..._ordered];
      final moved = ids.removeAt(index);
      ids.insert(target, moved);
      _ordered = ids;
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.viewModel.saveRotation(_ordered);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _saving = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final available = [
      for (final plan in widget.viewModel.plans)
        if (!_ordered.contains(plan.planId)) plan,
    ];
    return SafeArea(
      top: false,
      child: Container(
        height: MediaQuery.sizeOf(context).height * 0.85,
        margin: const EdgeInsets.all(GainerSpacing.xs),
        decoration: BoxDecoration(
          color: colors.elevatedSurface,
          borderRadius: BorderRadius.circular(GainerRadii.card),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                GainerSpacing.xs,
                GainerSpacing.s,
                GainerSpacing.xs,
                0,
              ),
              child: Row(
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text(
                      'Abbrechen',
                      style: GainerTypography.body.copyWith(
                        color: colors.accent,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Rotation',
                      textAlign: TextAlign.center,
                      style: GainerTypography.cardTitle.copyWith(
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                  GainerPillButton(
                    label: 'Speichern',
                    isLoading: _saving,
                    onPressed: _saving ? null : _save,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(GainerSpacing.m),
                children: [
                  Text(
                    'Nach einem Training aus der Rotation wird der nächste Plan '
                    'vorgeschlagen. Nach dem letzten folgt wieder der erste.',
                    style: GainerTypography.caption.copyWith(
                      color: colors.secondaryText,
                    ),
                  ),
                  const SizedBox(height: GainerSpacing.m),
                  Text(
                    'In der Rotation',
                    style: GainerTypography.label.copyWith(
                      color: colors.secondaryText,
                    ),
                  ),
                  const SizedBox(height: GainerSpacing.xs),
                  if (_ordered.isEmpty)
                    GainerCard(
                      child: Text(
                        'Noch kein Plan in der Rotation.',
                        style: GainerTypography.body.copyWith(
                          color: colors.secondaryText,
                        ),
                      ),
                    )
                  else
                    GainerGroupedSection(
                      children: [
                        for (var i = 0; i < _ordered.length; i++)
                          _rotationRow(i),
                      ],
                    ),
                  const SizedBox(height: GainerSpacing.m),
                  if (available.isNotEmpty) ...[
                    Text(
                      'Verfügbare Pläne',
                      style: GainerTypography.label.copyWith(
                        color: colors.secondaryText,
                      ),
                    ),
                    const SizedBox(height: GainerSpacing.xs),
                    GainerGroupedSection(
                      children: [
                        for (final plan in available)
                          GainerListRow(
                            title: plan.name,
                            trailing: Icon(
                              CupertinoIcons.plus_circle,
                              color: colors.accent,
                            ),
                            onTap: () => setState(
                              () => _ordered = [..._ordered, plan.planId],
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: GainerSpacing.m),
                    Text(
                      _error!,
                      style: GainerTypography.caption.copyWith(
                        color: colors.destructive,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rotationRow(int index) {
    final planId = _ordered[index];
    final plan = _planOf(planId);
    return GainerListRow(
      title: plan?.name ?? 'Plan',
      subtitle: 'Position ${index + 1}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RowIconButton(
            icon: CupertinoIcons.arrow_up,
            label: 'Nach oben',
            onPressed: index > 0 && !_saving ? () => _move(index, -1) : null,
          ),
          _RowIconButton(
            icon: CupertinoIcons.arrow_down,
            label: 'Nach unten',
            onPressed: index < _ordered.length - 1 && !_saving
                ? () => _move(index, 1)
                : null,
          ),
          _RowIconButton(
            icon: CupertinoIcons.minus_circle,
            label: 'Aus der Rotation entfernen',
            onPressed: _saving
                ? null
                : () =>
                      setState(() => _ordered = [..._ordered]..removeAt(index)),
          ),
        ],
      ),
    );
  }
}

class _RowIconButton extends StatelessWidget {
  const _RowIconButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
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
        size: 22,
        color: onPressed == null ? colors.placeholderText : colors.accent,
        semanticLabel: label,
      ),
    );
  }
}
