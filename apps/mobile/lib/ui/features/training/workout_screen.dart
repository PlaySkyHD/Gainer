import 'package:flutter/cupertino.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../../domain/models/training/workout_input.dart';
import '../../../domain/models/training/workout_model.dart';
import '../../../domain/models/training/workout_rules.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'active_workout_controller.dart';
import 'set_row.dart';
import 'training_format.dart';
import 'workout_block_card.dart';
import 'workout_metadata_card.dart';
import 'workout_view_model.dart';

/// Öffnet ein Training als Vollbild-Modal über der Shell.
Future<void> openWorkoutScreen(
  BuildContext context, {
  required TrainingLogRepository repository,
  required ActiveWorkoutController activeWorkout,
  required String workoutId,
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    CupertinoPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => WorkoutScreen(
        repository: repository,
        activeWorkout: activeWorkout,
        workoutId: workoutId,
      ),
    ),
  );
}

/// Trainingsscreen. Aktive Trainings lassen sich minimieren oder beenden,
/// historische Trainings nur schließen.
class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({
    required this.repository,
    required this.activeWorkout,
    required this.workoutId,
    super.key,
  });

  final TrainingLogRepository repository;
  final ActiveWorkoutController activeWorkout;
  final String workoutId;

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

enum _WorkoutMenuAction { toggleWeightUnit, toggleRir, delete }

class _WorkoutScreenState extends State<WorkoutScreen> {
  late final WorkoutViewModel _viewModel;

  /// Zahl der Zahlenfelder mit Fokus; die Leiste über der Tastatur hängt daran.
  int _numericFocusCount = 0;
  final ValueNotifier<bool> _editingNumber = ValueNotifier(false);
  final SetFieldFocus _fieldFocus = SetFieldFocus();

  @override
  void initState() {
    super.initState();
    _viewModel = WorkoutViewModel(
      repository: widget.repository,
      activeWorkout: widget.activeWorkout,
      workoutId: widget.workoutId,
    );
    _viewModel.load();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    _editingNumber.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).pop();

  Future<void> _finish() async {
    final outcome = await _viewModel.requestFinish();
    if (outcome == WorkoutFinishOutcome.finished && mounted) _close();
  }

  void _onEditingChanged(bool focused) {
    _numericFocusCount = (_numericFocusCount + (focused ? 1 : -1)).clamp(
      0,
      1 << 20,
    );
    _editingNumber.value = _numericFocusCount > 0;
  }

  /// Kg → Wdh. → (RIR) → Kg des nächsten Satzes → … in Lesereihenfolge.
  void _moveFocus({required bool forward}) {
    final workout = _viewModel.workout;
    if (workout == null) return;
    _fieldFocus.move(_fieldOrder(workout), forward: forward);
  }

  Iterable<(String, SetField)> _fieldOrder(Workout workout) sync* {
    for (final block in workout.exercises) {
      for (final set in block.sets) {
        if (block.exerciseTypeSnapshot != ExerciseKind.bodyweightOnly) {
          yield (set.setId, SetField.weight);
        }
        yield (set.setId, SetField.repetitions);
        if (_viewModel.showRir) yield (set.setId, SetField.rir);
      }
    }
  }

  void _unfocus() => FocusManager.instance.primaryFocus?.unfocus();

  Future<void> _showMenu(Workout workout) async {
    final choice = await showGainerActionSheet<_WorkoutMenuAction>(
      context: context,
      title: workout.title,
      quickActions: const [
        GainerSheetAction(
          label: 'Löschen',
          icon: CupertinoIcons.trash,
          value: _WorkoutMenuAction.delete,
          destructive: true,
        ),
      ],
      groups: [
        [
          GainerSheetAction(
            label: 'Gewichtseinheit: ${_viewModel.weightUnit.label}',
            icon: CupertinoIcons.arrow_2_squarepath,
            value: _WorkoutMenuAction.toggleWeightUnit,
          ),
          GainerSheetAction(
            label: _viewModel.showRir ? 'RIR ausblenden' : 'RIR anzeigen',
            icon: CupertinoIcons.gauge,
            value: _WorkoutMenuAction.toggleRir,
          ),
        ],
      ],
    );
    if (!mounted) return;
    switch (choice) {
      case _WorkoutMenuAction.toggleWeightUnit:
        await _viewModel.setWeightUnit(
          _viewModel.weightUnit == WeightUnit.kg
              ? WeightUnit.lbs
              : WeightUnit.kg,
        );
      case _WorkoutMenuAction.toggleRir:
        await _viewModel.setShowRir(!_viewModel.showRir);
      case _WorkoutMenuAction.delete:
        await _confirmDelete();
      case null:
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showGainerStackedDialog<bool>(
      context: context,
      title: 'Training löschen?',
      message: 'Das Training verschwindet sofort aus dem Tagebuch und wird beim nächsten Sync entfernt.',
      actions: const [
        GainerDialogAction(label: 'Löschen', value: true, destructive: true),
        GainerDialogAction(label: 'Abbrechen', value: false),
      ],
    );
    if (confirmed != true || !mounted) return;
    if (await _viewModel.deleteWorkout() && mounted) _close();
  }

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final workout = _viewModel.workout;
        return CupertinoPageScaffold(
          backgroundColor: colors.background,
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _Header(
                  leading: _leading(workout),
                  title: workout == null
                      ? ''
                      : formatShortDate(workout.startedAtUtc.toLocal()),
                  trailing: GainerToolbarGroup(
                    actions: [
                      GainerToolbarAction(
                        icon: CupertinoIcons.timer,
                        semanticLabel: 'Timer',
                        onPressed: () {},
                      ),
                      GainerToolbarAction(
                        icon: CupertinoIcons.ellipsis,
                        semanticLabel: 'Weitere Aktionen',
                        onPressed: workout == null
                            ? null
                            : () => _showMenu(workout),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      GainerSpacing.m,
                      GainerSpacing.xs,
                      GainerSpacing.m,
                      GainerSpacing.l,
                    ),
                    children: [
                      if (_viewModel.errorMessage case final message?) ...[
                        _NoticeCard(
                          message: message,
                          onRetry: _viewModel.hasUnsavedChanges
                              ? _viewModel.retrySave
                              : null,
                        ),
                        const SizedBox(height: GainerSpacing.s),
                      ],
                      if (workout == null && _viewModel.isLoading)
                        const Center(child: CupertinoActivityIndicator()),
                      if (workout != null) ..._content(workout),
                    ],
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: _editingNumber,
                  builder: (context, editing, _) => editing
                      ? TextFieldTapRegion(
                          child: GainerNumericAccessoryBar(
                            onPrevious: () => _moveFocus(forward: false),
                            onNext: () => _moveFocus(forward: true),
                            onDone: _unfocus,
                            onHideKeyboard: _unfocus,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Minimieren und Beenden (aktiv) bzw. Schließen (historisch). Die Pille
  /// wächst nur mit ihrem Inhalt.
  Widget _leading(Workout? workout) {
    if (workout != null && workout.isActive) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GainerToolbarButton(
            icon: CupertinoIcons.chevron_down,
            semanticLabel: 'Minimieren',
            onPressed: _close,
          ),
          const SizedBox(width: GainerSpacing.xs),
          GainerPillButton(label: 'Beenden', onPressed: _finish),
        ],
      );
    }
    return _AccentCloseButton(onPressed: _close);
  }

  List<Widget> _content(Workout workout) {
    return [
      WorkoutMetadataCard(viewModel: _viewModel, workout: workout),
      const SizedBox(height: GainerSpacing.m),
      if (workout.exercises.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: GainerSpacing.l),
          child: Text(
            'Noch keine Übungen.',
            textAlign: TextAlign.center,
            style: GainerTypography.body.copyWith(
              color: GainerDesign.colorsOf(context).secondaryText,
            ),
          ),
        ),
      ..._blocks(workout),
    ];
  }

  /// Benachbarte Blöcke mit gleichem Superset stehen in einer gemeinsamen
  /// Gruppe mit Akzentlinie; die Karten tragen ihre Buchstaben A, B, …
  List<Widget> _blocks(Workout workout) {
    final accent = GainerDesign.colorsOf(context).accent;
    return [
      for (final group in supersetGroups(workout.exercises))
        Padding(
          padding: const EdgeInsets.only(bottom: GainerSpacing.s),
          child: group.isSuperset
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(left: BorderSide(color: accent, width: 3)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(left: GainerSpacing.xs),
                    child: Column(
                      children: [
                        for (
                          var position = 0;
                          position < group.blockIndexes.length;
                          position++
                        )
                          Padding(
                            padding: EdgeInsets.only(
                              bottom: position == group.blockIndexes.length - 1
                                  ? 0
                                  : GainerSpacing.s,
                            ),
                            child: _blockCard(
                              workout.exercises[group.blockIndexes[position]],
                              supersetLabel: group.labelAt(position),
                            ),
                          ),
                      ],
                    ),
                  ),
                )
              : _blockCard(workout.exercises[group.blockIndexes.single]),
        ),
    ];
  }

  Widget _blockCard(WorkoutBlock block, {String? supersetLabel}) {
    return WorkoutBlockCard(
      viewModel: _viewModel,
      block: block,
      fieldFocus: _fieldFocus,
      supersetLabel: supersetLabel,
      onEditingChanged: _onEditingChanged,
    );
  }
}

/// Kopfzeile: Datum liegt zwischen den Seitenaktionen und wird bei Platzmangel gekürzt.
class _Header extends StatelessWidget {
  const _Header({
    required this.leading,
    required this.title,
    required this.trailing,
  });

  final Widget leading;
  final String title;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: GainerSpacing.s,
        vertical: GainerSpacing.xs,
      ),
      child: Row(
        children: [
          leading,
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GainerTypography.title.copyWith(color: colors.primaryText),
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

class _AccentCloseButton extends StatelessWidget {
  const _AccentCloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Semantics(
      button: true,
      label: 'Schließen',
      excludeSemantics: true,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size.square(GainerRadii.iconButtonDiameter),
        color: colors.accent,
        borderRadius: BorderRadius.circular(GainerRadii.iconButtonDiameter / 2),
        onPressed: onPressed,
        child: Icon(CupertinoIcons.checkmark, size: 22, color: colors.onAccent),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return GainerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            message,
            style: GainerTypography.body.copyWith(color: colors.destructive),
          ),
          if (onRetry case final retry?) ...[
            const SizedBox(height: GainerSpacing.s),
            GainerPillButton(
              label: 'Erneut speichern',
              variant: GainerPillVariant.tonal,
              expand: true,
              onPressed: retry,
            ),
          ],
        ],
      ),
    );
  }
}
