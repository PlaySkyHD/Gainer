import 'package:flutter/cupertino.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../../domain/models/training/training_plan_model.dart';
import '../../../domain/models/training/training_schedule.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'active_workout_controller.dart';
import 'category_library_screen.dart';
import 'exercise_library_screen.dart';
import 'plan_editor_screen.dart';
import 'plan_start.dart';
import 'schedule_day_actions.dart';
import 'training_plans_view_model.dart';
import 'training_schedule_sheet.dart';
import 'training_today_card.dart';

/// Pläne-Segment: Karte „Heute“ aus dem Rhythmus, Planliste mit Umordnen,
/// Duplizieren und Archivieren sowie der Rhythmus-Editor.
enum _PlanAction { start, duplicate, archive }

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

  /// Zuletzt gesehenes aktives Training. Endet ein Plan-Training, rückt die
  /// Rotation weiter; der Vorschlag soll das ohne Neustart zeigen.
  late String? _activeWorkoutId = widget.activeWorkout.active?.workoutId;

  @override
  void initState() {
    super.initState();
    widget.activeWorkout.addListener(_onActiveWorkoutChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _viewModel.load());
  }

  @override
  void didUpdateWidget(TrainingPlansSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.activeWorkout, widget.activeWorkout)) return;
    oldWidget.activeWorkout.removeListener(_onActiveWorkoutChanged);
    widget.activeWorkout.addListener(_onActiveWorkoutChanged);
    _activeWorkoutId = widget.activeWorkout.active?.workoutId;
  }

  void _onActiveWorkoutChanged() {
    final workoutId = widget.activeWorkout.active?.workoutId;
    if (workoutId == _activeWorkoutId) return;
    _activeWorkoutId = workoutId;
    _viewModel.load();
  }

  @override
  void dispose() {
    widget.activeWorkout.removeListener(_onActiveWorkoutChanged);
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

  Future<void> _openSchedule() async {
    final changed = await showTrainingScheduleSheet(
      context,
      repository: widget.repository,
    );
    if (changed && mounted) await _viewModel.load();
  }

  Future<void> _openDayActions(ScheduledTraining training) async {
    final projection = _viewModel.projection;
    if (projection == null) return;
    final changed = await showScheduledTrainingActions(
      context,
      repository: widget.repository,
      projection: projection,
      training: training,
    );
    if (changed && mounted) await _viewModel.load();
  }

  Future<void> _openExerciseLibrary() async {
    await Navigator.of(context).push<void>(
      CupertinoPageRoute<void>(
        builder: (_) => ExerciseLibraryScreen(repository: widget.repository),
      ),
    );
  }

  Future<void> _openCategoryLibrary() async {
    await Navigator.of(context).push<void>(
      CupertinoPageRoute<void>(
        builder: (_) => CategoryLibraryScreen(repository: widget.repository),
      ),
    );
  }

  Widget _buildCatalogSection() {
    return GainerGroupedSection(
      header: 'Katalog',
      children: [
        GainerListRow(
          key: const ValueKey('training-plans-exercises'),
          title: 'Übungen verwalten',
          leadingIcon: CupertinoIcons.list_bullet,
          showChevron: true,
          onTap: _openExerciseLibrary,
        ),
        GainerListRow(
          key: const ValueKey('training-plans-categories'),
          title: 'Kategorien verwalten',
          leadingIcon: CupertinoIcons.tag,
          showChevron: true,
          onTap: _openCategoryLibrary,
        ),
      ],
    );
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

  Future<void> _duplicate(TrainingPlanModel plan) async {
    final result = await _viewModel.duplicate(plan.planId);
    if (!mounted) return;
    if (result.error != null) return _showError(result.error!);
    await _openEditor(result.plan!.planId);
  }

  /// Kontext-Sheet eines Plans per langem Drücken.
  Future<void> _showPlanActions(TrainingPlanModel plan) async {
    final action = await showGainerActionSheet<_PlanAction>(
      context: context,
      title: plan.name,
      groups: const [
        [
          GainerSheetAction(
            label: 'Training beginnen',
            icon: CupertinoIcons.play_fill,
            value: _PlanAction.start,
          ),
          GainerSheetAction(
            label: 'Duplizieren',
            icon: CupertinoIcons.doc_on_doc,
            value: _PlanAction.duplicate,
          ),
        ],
        [
          GainerSheetAction(
            label: 'Archivieren',
            icon: CupertinoIcons.archivebox,
            value: _PlanAction.archive,
            destructive: true,
          ),
        ],
      ],
    );
    if (!mounted) return;
    switch (action) {
      case _PlanAction.start:
        await _start(plan.planId);
      case _PlanAction.duplicate:
        await _duplicate(plan);
      case _PlanAction.archive:
        await _archive(plan);
      case null:
    }
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

  List<Widget> _stateChildren(
    List<TrainingPlanModel> plans,
    GainerColors colors,
  ) {
    if (_viewModel.isLoading && _viewModel.plans.isEmpty) {
      return const [Center(child: CupertinoActivityIndicator())];
    }
    if (_viewModel.errorMessage != null) {
      return [
        GainerCard(
          child: Text(
            _viewModel.errorMessage!,
            textAlign: TextAlign.center,
            style: GainerTypography.body.copyWith(color: colors.secondaryText),
          ),
        ),
      ];
    }
    final projection = _viewModel.projection;
    final showToday =
        !_editing &&
        projection != null &&
        (plans.isNotEmpty || projection.schedule != null);
    return [
      if (showToday) ...[
        TrainingTodayCard(
          projection: projection,
          onStart: _start,
          onSetup: _openSchedule,
          onActions: _openDayActions,
        ),
        const SizedBox(height: GainerSpacing.m),
      ],
      if (plans.isEmpty)
        _buildEmpty(colors)
      else if (_editing)
        _buildEditableList(plans)
      else
        _buildList(plans),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final plans = _orderedPlans();
        final colors = GainerDesign.colorsOf(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: GainerSpacing.xs,
              runSpacing: GainerSpacing.xs,
              children: [
                GainerPillButton(
                  label: 'Neuer Plan',
                  icon: CupertinoIcons.add,
                  onPressed: () => _openEditor(null),
                ),
                GainerPillButton(
                  key: const ValueKey('training-plans-schedule'),
                  label: 'Rhythmus',
                  variant: GainerPillVariant.tonal,
                  onPressed: _openSchedule,
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
            ..._stateChildren(plans, colors),
            const SizedBox(height: GainerSpacing.l),
            _buildCatalogSection(),
          ],
        );
      },
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

  Widget _buildList(List<TrainingPlanModel> plans) {
    return GainerGroupedSection(
      header: 'Pläne',
      children: [
        for (final plan in plans)
          GestureDetector(
            key: ValueKey('training-plan-${plan.planId}'),
            behavior: HitTestBehavior.opaque,
            onLongPress: () => _showPlanActions(plan),
            child: GainerListRow(
              title: plan.name,
              subtitle: _subtitle(plan),
              showChevron: true,
              onTap: () => _openEditor(plan.planId),
            ),
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
                  subtitle: _subtitle(plan),
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

  String _subtitle(TrainingPlanModel plan) {
    final count = plan.entries.length;
    final exercises = count == 1 ? '1 Übung' : '$count Übungen';
    final scheduled = _viewModel.scheduledPlanIds.contains(plan.planId);
    return [exercises, if (scheduled) 'Im Rhythmus'].join(' · ');
  }
}
