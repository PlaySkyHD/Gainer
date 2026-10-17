import 'package:flutter/cupertino.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../../domain/models/training/training_plan_model.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'active_workout_controller.dart';
import 'plan_editor_screen.dart';
import 'plan_rotation_sheet.dart';
import 'plan_start.dart';
import 'training_plans_view_model.dart';

/// Pläne-Segment: nächstes Training aus der Rotation, Planliste mit Umordnen
/// und Archivieren sowie die Rotation.
class TrainingPlansSection extends StatefulWidget {
  const TrainingPlansSection({
    required this.repository,
    required this.activeWorkout,
    super.key,
  });

  final TrainingLogRepository repository;
  final ActiveWorkoutController activeWorkout;

  @override
  State<TrainingPlansSection> createState() => _TrainingPlansSectionState();
}

class _TrainingPlansSectionState extends State<TrainingPlansSection> {
  late final TrainingPlansViewModel _viewModel = TrainingPlansViewModel(
    repository: widget.repository,
  );
  bool _editing = false;

  /// Reihenfolge während eines Umordnens, bis das Speichern abgeschlossen ist.
  List<String>? _pendingOrder;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _viewModel.load());
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _openEditor(String? planId) async {
    await Navigator.of(context).push<void>(
      CupertinoPageRoute<void>(
        builder: (_) => PlanEditorScreen(
          repository: widget.repository,
          activeWorkout: widget.activeWorkout,
          planId: planId,
        ),
      ),
    );
    if (mounted) await _viewModel.load();
  }

  Future<void> _start(String planId) async {
    await startPlanWorkout(
      context,
      repository: widget.repository,
      activeWorkout: widget.activeWorkout,
      planId: planId,
    );
    if (mounted) await _viewModel.load();
  }

  Future<void> _openRotation() async {
    await showPlanRotationSheet(context, viewModel: _viewModel);
  }

  Future<void> _archive(TrainingPlanModel plan) async {
    final confirmed = await showGainerStackedDialog<bool>(
      context: context,
      title: 'Plan archivieren?',
      message:
          '„${plan.name}“ verschwindet aus der Planliste. Trainings, die daraus entstanden sind, bleiben erhalten.',
      actions: const [
        GainerDialogAction(
          label: 'Archivieren',
          value: true,
          destructive: true,
        ),
        GainerDialogAction(label: 'Abbrechen', value: false),
      ],
    );
    if (confirmed != true || !mounted) return;
    final error = await _viewModel.archive(plan.planId);
    if (error != null) await _showError(error);
  }

  Future<void> _reorder(
    List<TrainingPlanModel> plans,
    int oldIndex,
    int newIndex,
  ) async {
    final ids = [for (final plan in plans) plan.planId];
    ids.insert(newIndex, ids.removeAt(oldIndex));
    setState(() => _pendingOrder = ids);
    final error = await _viewModel.reorder(ids);
    if (!mounted) return;
    setState(() => _pendingOrder = null);
    if (error != null) await _showError(error);
  }

  Future<void> _showError(String message) {
    return showGainerStackedDialog<bool>(
      context: context,
      title: 'Hinweis',
      message: message,
      actions: const [GainerDialogAction(label: 'OK', value: true)],
    ).then((_) {});
  }

  /// Planliste in Nutzerreihenfolge; während eines Umordnens die neue Reihenfolge.
  List<TrainingPlanModel> _orderedPlans() {
    final plans = _viewModel.plans;
    final pending = _pendingOrder;
    if (pending == null) return plans;
    final byId = {for (final plan in plans) plan.planId: plan};
    return [
      for (final id in pending)
        if (byId[id] != null) byId[id]!,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final plans = _orderedPlans();
        final nextId = _viewModel.nextPlanId;
        final colors = GainerDesign.colorsOf(context);
        final loading = _viewModel.isLoading && _viewModel.plans.isEmpty;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: GainerSpacing.xs,
              runSpacing: GainerSpacing.xs,
              children: [
                GainerPillButton(
                  label: 'Neuer Plan',
                  onPressed: () => _openEditor(null),
                ),
                GainerPillButton(
                  label: 'Rotation',
                  variant: GainerPillVariant.tonal,
                  onPressed: _openRotation,
                ),
                if (plans.isNotEmpty)
                  GainerPillButton(
                    key: const ValueKey('training-plans-edit-toggle'),
                    label: _editing ? 'Fertig' : 'Bearbeiten',
                    variant: GainerPillVariant.tonal,
                    onPressed: () => setState(() => _editing = !_editing),
                  ),
              ],
            ),
            const SizedBox(height: GainerSpacing.m),
            if (loading)
              const Center(child: CupertinoActivityIndicator())
            else if (_viewModel.errorMessage != null)
              GainerCard(
                child: Text(
                  _viewModel.errorMessage!,
                  textAlign: TextAlign.center,
                  style: GainerTypography.body.copyWith(
                    color: colors.secondaryText,
                  ),
                ),
              )
            else ...[
              if (nextId != null && !_editing)
                _buildNextCard(plans, nextId, colors),
              if (plans.isEmpty)
                _buildEmpty(colors)
              else if (_editing)
                _buildEditableList(plans)
              else
                _buildList(plans, nextId, colors),
            ],
          ],
        );
      },
    );
  }

  Widget _buildNextCard(
    List<TrainingPlanModel> plans,
    String nextId,
    GainerColors colors,
  ) {
    final next = plans.where((plan) => plan.planId == nextId).firstOrNull;
    if (next == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: GainerSpacing.m),
      child: GainerCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Nächstes Training',
              style: GainerTypography.caption.copyWith(
                color: colors.secondaryText,
              ),
            ),
            const SizedBox(height: GainerSpacing.xxs),
            Text(
              next.name,
              style: GainerTypography.title.copyWith(color: colors.primaryText),
            ),
            const SizedBox(height: GainerSpacing.s),
            GainerPillButton(
              key: const ValueKey('training-plans-next-start'),
              label: 'Training starten',
              icon: CupertinoIcons.play_fill,
              expand: true,
              onPressed: () => _start(next.planId),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(GainerColors colors) {
    return GainerCard(
      padding: const EdgeInsets.all(GainerSpacing.l),
      child: Text(
        'Noch keine Pläne. Lege einen Plan an, z. B. „Push“, um Trainings schneller zu starten.',
        textAlign: TextAlign.center,
        style: GainerTypography.body.copyWith(color: colors.secondaryText),
      ),
    );
  }

  Widget _buildList(
    List<TrainingPlanModel> plans,
    String? nextId,
    GainerColors colors,
  ) {
    return GainerGroupedSection(
      header: 'Pläne',
      children: [
        for (final plan in plans)
          GainerListRow(
            title: plan.name,
            subtitle: _subtitle(plan, nextId),
            showChevron: true,
            onTap: () => _openEditor(plan.planId),
          ),
      ],
    );
  }

  Widget _buildEditableList(List<TrainingPlanModel> plans) {
    final colors = GainerDesign.colorsOf(context);
    return CustomScrollView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      slivers: [
        SliverReorderableList(
          itemCount: plans.length,
          onReorderItem: (oldIndex, newIndex) =>
              _reorder(plans, oldIndex, newIndex),
          itemBuilder: (context, index) {
            final plan = plans[index];
            return Padding(
              key: ValueKey(plan.planId),
              padding: const EdgeInsets.only(bottom: GainerSpacing.xs),
              child: GainerCard(
                padding: EdgeInsets.zero,
                child: GainerListRow(
                  title: plan.name,
                  subtitle: _subtitle(plan, null),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size.square(
                          GainerRadii.iconButtonDiameter,
                        ),
                        onPressed: () => _archive(plan),
                        child: Icon(
                          CupertinoIcons.archivebox,
                          color: colors.destructive,
                          semanticLabel: 'Archivieren',
                        ),
                      ),
                      ReorderableDragStartListener(
                        index: index,
                        child: SizedBox(
                          width: GainerRadii.iconButtonDiameter,
                          height: GainerRadii.iconButtonDiameter,
                          child: Icon(
                            CupertinoIcons.line_horizontal_3,
                            color: colors.secondaryText,
                            semanticLabel: 'Verschieben',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  String _subtitle(TrainingPlanModel plan, String? nextId) {
    final count = plan.entries.length;
    final exercises = count == 1 ? '1 Übung' : '$count Übungen';
    final inRotation =
        _viewModel.rotation?.planIds.contains(plan.planId) ?? false;
    return [
      exercises,
      if (inRotation) 'In Rotation',
      if (plan.planId == nextId) 'Nächstes Training',
    ].join(' · ');
  }
}
