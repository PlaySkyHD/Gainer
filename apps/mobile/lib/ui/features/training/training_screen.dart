import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/training/training.dart';
import '../../core/theme.dart';
import 'training_planning_screens.dart';
import 'training_view_model.dart';

class TrainingScreen extends StatefulWidget {
  const TrainingScreen({required this.viewModel, super.key});

  final TrainingViewModel viewModel;

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  final Map<String, _SetEditors> _setEditors = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.viewModel.load(),
    );
  }

  @override
  void dispose() {
    for (final editor in _setEditors.values) {
      editor.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
    value: widget.viewModel,
    child: Consumer<TrainingViewModel>(
      builder: (context, model, _) => CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('Training')),
        child: SafeArea(
          child:
              model.planning == null &&
                  (model.isLoading || model.errorMessage == null)
              ? const Center(child: CupertinoActivityIndicator())
              : _content(context, model),
        ),
      ),
    ),
  );

  Widget _content(BuildContext context, TrainingViewModel model) {
    final plan = model.planning;
    if (plan == null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 24),
          const Icon(CupertinoIcons.exclamationmark_circle, size: 36),
          const SizedBox(height: 12),
          Text(
            model.errorMessage ??
                'Trainingsdaten konnten nicht geladen werden.',
            textAlign: TextAlign.center,
          ),
          CupertinoButton(
            onPressed: model.load,
            child: const Text('Erneut versuchen'),
          ),
        ],
      );
    }
    return ListView(
      key: const ValueKey('training-overview-scroll'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        if (model.errorMessage != null)
          _Notice(model.errorMessage!, error: true),
        if (model.notificationNotice != null)
          _Notice(model.notificationNotice!),
        if (model.runningWorkout != null)
          _runningWorkout(model)
        else
          ..._overview(context, model),
      ],
    );
  }

  List<Widget> _overview(BuildContext context, TrainingViewModel model) {
    final plan = model.planning!;
    final templates = plan.templates
        .where((item) => !item.value.isArchived)
        .toList();
    final nextMatches = templates.where(
      (item) => item.id == plan.nextTemplateId,
    );
    final next = nextMatches.isEmpty ? null : nextMatches.first;
    final last = model.history.isEmpty ? null : model.history.first;
    return [
      Text(
        'Dein Training',
        style: CupertinoTheme.of(context).textTheme.navLargeTitleTextStyle,
      ),
      const SizedBox(height: 4),
      Text(
        templates.isEmpty
            ? 'Plane deine erste Einheit und baue daraus deine Rotation.'
            : '${templates.length} aktive ${templates.length == 1 ? 'Vorlage' : 'Vorlagen'} · dein Plan bleibt offline verfügbar.',
        style: TextStyle(color: GainerTheme.secondaryText(context)),
      ),
      const SizedBox(height: 22),
      _SectionHeading(title: 'Als Nächstes'),
      if (next == null)
        _TrainingCard(
          icon: CupertinoIcons.arrow_2_circlepath,
          title: 'Rotation einrichten',
          subtitle: templates.isEmpty
              ? 'Erstelle eine Vorlage, um dein nächstes Training festzulegen.'
              : 'Lege eine Reihenfolge für deine Vorlagen fest.',
          trailing: CupertinoButton(
            key: const ValueKey('training-open-templates'),
            minimumSize: const Size.square(48),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            onPressed: () =>
                _push(context, TrainingTemplateLibraryScreen(viewModel: model)),
            child: const Text('Vorlagen'),
          ),
        )
      else
        _TrainingCard(
          key: const ValueKey('training-next-card'),
          icon: CupertinoIcons.sportscourt,
          title: next.value.name,
          subtitle:
              '${next.value.items.length} Übungen · nächste Einheit deiner Rotation',
          trailing: CupertinoButton(
            key: ValueKey('training-start-next-${next.id}'),
            minimumSize: const Size.square(48),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            color: GainerTheme.actionColor,
            onPressed: model.isSaving ? null : () => model.start(next.id),
            child: Text(
              'Start',
              style: TextStyle(
                color: model.isSaving
                    ? GainerTheme.secondaryText(context)
                    : CupertinoColors.white,
              ),
            ),
          ),
        ),
      const SizedBox(height: 22),
      _SectionHeading(
        title: 'Deine Vorlagen',
        action: CupertinoButton(
          key: const ValueKey('training-create-template-route'),
          minimumSize: const Size.square(48),
          padding: EdgeInsets.zero,
          onPressed: () =>
              _push(context, TrainingTemplateEditorScreen(viewModel: model)),
          child: const Text('Neu'),
        ),
      ),
      if (templates.isEmpty)
        _EmptyCard(
          title: 'Noch keine Vorlagen',
          subtitle: 'Stelle deine erste Einheit mit deinen Übungen zusammen.',
          actionLabel: 'Vorlage erstellen',
          onPressed: () =>
              _push(context, TrainingTemplateEditorScreen(viewModel: model)),
        )
      else ...[
        for (final template in templates.take(3))
          _TrainingCard(
            key: ValueKey('training-template-card-${template.id}'),
            contentKey: ValueKey('training-template-edit-${template.id}'),
            icon: CupertinoIcons.list_bullet,
            title: template.value.name,
            subtitle: '${template.value.items.length} Übungen',
            trailing: CupertinoButton(
              key: ValueKey('training-start-template-${template.id}'),
              minimumSize: const Size.square(48),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              color: GainerTheme.actionColor,
              onPressed: model.isSaving ? null : () => model.start(template.id),
              child: Text(
                'Start',
                style: TextStyle(
                  color: model.isSaving
                      ? GainerTheme.secondaryText(context)
                      : CupertinoColors.white,
                ),
              ),
            ),
            onPressed: () => _push(
              context,
              TrainingTemplateEditorScreen(
                viewModel: model,
                template: template,
              ),
            ),
          ),
      ],
      const SizedBox(height: 16),
      _SectionHeading(title: 'Training verwalten'),
      _TrainingCard(
        key: const ValueKey('training-open-exercises'),
        icon: CupertinoIcons.search,
        title: 'Übungsbibliothek',
        subtitle:
            '${plan.exercises.length + plan.customExercises.where((e) => !e.isArchived).length} Übungen · suchen und filtern',
        trailing: const Icon(CupertinoIcons.chevron_right, size: 18),
        onPressed: () =>
            _push(context, TrainingExerciseLibraryScreen(viewModel: model)),
      ),
      _TrainingCard(
        icon: CupertinoIcons.arrow_2_circlepath,
        title: 'Vorlagen & Rotation',
        subtitle: plan.rotation == null
            ? 'Rotation noch nicht festgelegt'
            : '${plan.rotation!.value.entries.length} Einheiten in deiner Reihenfolge',
        trailing: const Icon(CupertinoIcons.chevron_right, size: 18),
        onPressed: () =>
            _push(context, TrainingTemplateLibraryScreen(viewModel: model)),
      ),
      const SizedBox(height: 16),
      _SectionHeading(
        title: 'Verlauf',
        action: CupertinoButton(
          key: const ValueKey('training-open-history'),
          minimumSize: const Size.square(48),
          padding: EdgeInsets.zero,
          onPressed: () =>
              _push(context, TrainingHistoryScreen(viewModel: model)),
          child: const Text('Alle'),
        ),
      ),
      if (last == null)
        const _EmptyCard(
          title: 'Noch kein Training abgeschlossen',
          subtitle: 'Deine abgeschlossenen Einheiten erscheinen hier.',
        )
      else
        _TrainingCard(
          key: ValueKey('training-history-${last.id}'),
          icon: CupertinoIcons.clock,
          title: last.value.templateNameSnapshot,
          subtitle: _historySummary(last.value),
          trailing: const Icon(CupertinoIcons.chevron_right, size: 18),
          onPressed: () =>
              _push(context, TrainingHistoryDetailScreen(entry: last)),
        ),
    ];
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(CupertinoPageRoute<void>(builder: (_) => page));
  }

  String _historySummary(WorkoutRecord workout) {
    final completeSets = workout.exercises.fold<int>(
      0,
      (count, exercise) =>
          count + exercise.sets.where((set) => set.isCompleted).length,
    );
    return '${_formatDate(workout.completedAtUtc)} · $completeSets Sätze';
  }

  Future<String?> _chooseExercise(List<({String id, String name})> exercises) =>
      showCupertinoModalPopup<String>(
        context: context,
        builder: (context) => SafeArea(
          child: CupertinoActionSheet(
            title: const Text('Übung hinzufügen'),
            actions: [
              for (final exercise in exercises)
                CupertinoActionSheetAction(
                  key: ValueKey('exercise-choice-${exercise.id}'),
                  onPressed: () => Navigator.of(context).pop(exercise.id),
                  child: Text(exercise.name),
                ),
            ],
            cancelButton: CupertinoActionSheetAction(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Abbrechen'),
            ),
          ),
        ),
      );

  Widget _runningWorkout(TrainingViewModel model) {
    final workout = model.runningWorkout!;
    final activeSetIds = {
      for (final exercise in workout.exercises)
        for (final set in exercise.sets) set.id,
    };
    for (final id in _setEditors.keys.toList()) {
      if (!activeSetIds.contains(id)) {
        _setEditors.remove(id)!.dispose();
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TrainingCard(
          icon: CupertinoIcons.sportscourt,
          title: workout.templateNameSnapshot,
          titleKey: const ValueKey('running-workout-title'),
          subtitle: 'Workout läuft · Änderungen werden lokal gespeichert',
        ),
        CupertinoButton(
          key: const ValueKey('training-add-exercise'),
          minimumSize: const Size.square(48),
          padding: EdgeInsets.zero,
          onPressed: model.isSaving
              ? null
              : () async {
                  final choices = [
                    ...?model.planning?.exercises.map(
                      (entry) => (id: entry.id, name: entry.name),
                    ),
                    ...?model.planning?.customExercises
                        .where((entry) => !entry.isArchived)
                        .map((entry) => (id: entry.id, name: entry.value.name)),
                  ];
                  if (choices.isEmpty) return;
                  final id = await _chooseExercise(choices);
                  if (id != null && mounted) await model.addExercise(id);
                },
          child: const Text('+ Übung hinzufügen'),
        ),
        for (final exercise in workout.exercises)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exercise.exerciseNameSnapshot,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (exercise.sourceExerciseId != null)
                  if (model.previousByExerciseId[exercise.sourceExerciseId]
                      case final previous?)
                    Text(
                      'Vorher: ${previous.sets.map((set) => '${set.weightKg?.toStringAsFixed(1)} kg × ${set.repetitions}').join(', ')}',
                      key: ValueKey('training-previous-${exercise.id}'),
                    ),
                Align(
                  alignment: Alignment.centerRight,
                  child: CupertinoButton(
                    key: ValueKey('training-remove-exercise-${exercise.id}'),
                    minimumSize: const Size.square(48),
                    padding: EdgeInsets.zero,
                    onPressed: model.isSaving
                        ? null
                        : () => model.removeExercise(exercise.id),
                    child: const Text('Übung entfernen'),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    CupertinoButton(
                      key: ValueKey('training-exercise-up-${exercise.id}'),
                      minimumSize: const Size.square(48),
                      padding: EdgeInsets.zero,
                      onPressed: exercise.position == 0 || model.isSaving
                          ? null
                          : () => model.moveExercise(
                              exercise.id,
                              exercise.position - 1,
                            ),
                      child: const Text('↑ Übung'),
                    ),
                    CupertinoButton(
                      key: ValueKey('training-exercise-down-${exercise.id}'),
                      minimumSize: const Size.square(48),
                      padding: EdgeInsets.zero,
                      onPressed:
                          exercise.position == workout.exercises.length - 1 ||
                              model.isSaving
                          ? null
                          : () => model.moveExercise(
                              exercise.id,
                              exercise.position + 1,
                            ),
                      child: const Text('↓ Übung'),
                    ),
                  ],
                ),
                for (final set in exercise.sets)
                  Builder(
                    builder: (context) {
                      final editors = _setEditors.putIfAbsent(
                        set.id,
                        () => _SetEditors.fromRecord(set),
                      );
                      return Container(
                        key: ValueKey('training-set-card-${set.id}'),
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: CupertinoColors
                              .secondarySystemGroupedBackground
                              .resolveFrom(context),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Satz ${set.position + 1}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final fieldWidth =
                                    (constraints.maxWidth - 8) / 2;
                                return Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    SizedBox(
                                      width: fieldWidth,
                                      child: _field(
                                        'kg',
                                        editors.weight,
                                        key: ValueKey('set-weight-${set.id}'),
                                        compact: true,
                                        numeric: true,
                                      ),
                                    ),
                                    SizedBox(
                                      width: fieldWidth,
                                      child: _field(
                                        'Wiederholungen',
                                        editors.repetitions,
                                        key: ValueKey(
                                          'set-repetitions-${set.id}',
                                        ),
                                        compact: true,
                                        numeric: true,
                                      ),
                                    ),
                                    SizedBox(
                                      width: fieldWidth,
                                      child: _field(
                                        'RIR',
                                        editors.rir,
                                        key: ValueKey('set-rir-${set.id}'),
                                        compact: true,
                                        numeric: true,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            _field(
                              'Satznotiz',
                              editors.notes,
                              key: ValueKey('set-notes-${set.id}'),
                              compact: true,
                            ),
                            CupertinoButton(
                              key: ValueKey('training-log-${set.id}'),
                              minimumSize: const Size.square(48),
                              padding: EdgeInsets.zero,
                              onPressed: model.isSaving
                                  ? null
                                  : () => model.logSet(
                                      exerciseId: exercise.id,
                                      setId: set.id,
                                      weightKg: _parseDecimalInput(
                                        editors.weight.text,
                                      ),
                                      repetitions: int.tryParse(
                                        editors.repetitions.text,
                                      ),
                                      rir: _parseDecimalInput(editors.rir.text),
                                      notes: editors.notes.text.trim().isEmpty
                                          ? null
                                          : editors.notes.text.trim(),
                                      complete: true,
                                    ),
                              child: Text(
                                set.isCompleted
                                    ? '✓ Gespeichert'
                                    : 'Satz abschließen',
                              ),
                            ),
                            Wrap(
                              children: [
                                CupertinoButton(
                                  key: ValueKey('training-set-up-${set.id}'),
                                  minimumSize: const Size.square(48),
                                  padding: EdgeInsets.zero,
                                  onPressed: set.position == 0 || model.isSaving
                                      ? null
                                      : () => model.moveSet(
                                          exercise.id,
                                          set.id,
                                          set.position - 1,
                                        ),
                                  child: const Text('↑ Satz'),
                                ),
                                CupertinoButton(
                                  key: ValueKey('training-set-down-${set.id}'),
                                  minimumSize: const Size.square(48),
                                  padding: EdgeInsets.zero,
                                  onPressed:
                                      set.position ==
                                              exercise.sets.length - 1 ||
                                          model.isSaving
                                      ? null
                                      : () => model.moveSet(
                                          exercise.id,
                                          set.id,
                                          set.position + 1,
                                        ),
                                  child: const Text('↓ Satz'),
                                ),
                                CupertinoButton(
                                  key: ValueKey(
                                    'training-remove-set-${set.id}',
                                  ),
                                  minimumSize: const Size.square(48),
                                  padding: EdgeInsets.zero,
                                  onPressed:
                                      exercise.sets.length <= 1 ||
                                          model.isSaving
                                      ? null
                                      : () => model.removeSet(
                                          exercise.id,
                                          set.id,
                                        ),
                                  child: const Text('Satz entfernen'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                CupertinoButton(
                  key: ValueKey('training-add-set-${exercise.id}'),
                  minimumSize: const Size.square(48),
                  padding: EdgeInsets.zero,
                  onPressed: model.isSaving
                      ? null
                      : () => model.addSet(exercise.id),
                  child: const Text('Satz hinzufügen'),
                ),
              ],
            ),
          ),
        if (workout.restTimer != null)
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: CupertinoColors.secondarySystemGroupedBackground
                  .resolveFrom(context),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pause · ${model.remainingRestSeconds ?? 0} s',
                  key: const ValueKey('training-rest-timer'),
                  style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    CupertinoButton(
                      minimumSize: const Size.square(48),
                      onPressed: () => model.timerAction(
                        (id) => model.repository.extendRestTimer(id),
                      ),
                      child: const Text('+30 s'),
                    ),
                    CupertinoButton(
                      minimumSize: const Size.square(48),
                      onPressed: () =>
                          model.timerAction(model.repository.restartRestTimer),
                      child: const Text('Neu starten'),
                    ),
                    CupertinoButton(
                      minimumSize: const Size.square(48),
                      onPressed: () =>
                          model.timerAction(model.repository.skipRestTimer),
                      child: const Text('Überspringen'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        CupertinoButton(
          key: const ValueKey('training-complete-workout'),
          minimumSize: const Size.square(52),
          color: GainerTheme.actionColor,
          onPressed: model.isSaving ? null : model.finish,
          child: Text(
            'Workout abschließen',
            style: TextStyle(
              color: model.isSaving
                  ? GainerTheme.secondaryText(context)
                  : CupertinoColors.white,
            ),
          ),
        ),
        CupertinoButton(
          key: const ValueKey('training-discard-workout'),
          minimumSize: const Size.square(48),
          onPressed: model.isSaving
              ? null
              : () => _confirmDiscard(context, model),
          child: const Text('Workout verwerfen'),
        ),
      ],
    );
  }

  Future<void> _confirmDiscard(
    BuildContext context,
    TrainingViewModel model,
  ) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Workout verwerfen?'),
        content: const Text(
          'Diese laufende Einheit wird verworfen. Bereits abgeschlossene historische Trainings bleiben erhalten.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Weitertrainieren'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Verwerfen'),
          ),
        ],
      ),
    );
    if (confirmed == true) await model.discard();
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    Key? key,
    bool compact = false,
    bool numeric = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: CupertinoTextField(
      key: key,
      controller: controller,
      placeholder: label,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      padding: compact ? const EdgeInsets.all(12) : const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(10),
      ),
    ),
  );
}

class _TrainingCard extends StatelessWidget {
  const _TrainingCard({
    super.key,
    this.contentKey,
    this.titleKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onPressed,
  });

  final IconData icon;
  final Key? contentKey;
  final Key? titleKey;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final secondary = GainerTheme.secondaryText(context);
    final content = CupertinoButton(
      key: contentKey,
      minimumSize: const Size.square(52),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onPressed: onPressed,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 12),
            child: Icon(
              icon,
              size: 21,
              color: CupertinoTheme.of(context).primaryColor,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  key: titleKey,
                  style: TextStyle(
                    color: CupertinoColors.label.resolveFrom(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(color: secondary, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
          context,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final largeText = MediaQuery.textScalerOf(context).scale(14) > 17;
          final stackTrailing =
              trailing != null && (constraints.maxWidth < 360 || largeText);
          if (trailing == null) return content;
          if (stackTrailing) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                content,
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 4),
                    child: trailing!,
                  ),
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: content),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: trailing!,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, this.action});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
          ),
        ),
        ?action,
      ],
    ),
  );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onPressed,
  });
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
        context,
      ),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(color: GainerTheme.secondaryText(context)),
        ),
        if (actionLabel != null && onPressed != null) ...[
          const SizedBox(height: 8),
          CupertinoButton(
            minimumSize: const Size.square(48),
            color: GainerTheme.actionColor,
            onPressed: onPressed,
            child: Text(
              actionLabel!,
              style: const TextStyle(color: CupertinoColors.white),
            ),
          ),
        ],
      ],
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice(this.message, {this.error = false});
  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      message,
      key: ValueKey(error ? 'training-error' : 'training-notification-notice'),
      style: TextStyle(
        color: error
            ? CupertinoColors.systemRed.resolveFrom(context)
            : GainerTheme.secondaryText(context),
      ),
    ),
  );
}

class _SetEditors {
  _SetEditors({
    required this.weight,
    required this.repetitions,
    required this.rir,
    required this.notes,
  });

  factory _SetEditors.fromRecord(WorkoutSetRecord set) => _SetEditors(
    weight: TextEditingController(text: set.weightKg?.toString() ?? ''),
    repetitions: TextEditingController(text: set.repetitions?.toString() ?? ''),
    rir: TextEditingController(text: set.rir?.toString() ?? ''),
    notes: TextEditingController(text: set.notes ?? ''),
  );

  final TextEditingController weight;
  final TextEditingController repetitions;
  final TextEditingController rir;
  final TextEditingController notes;

  void dispose() {
    weight.dispose();
    repetitions.dispose();
    rir.dispose();
    notes.dispose();
  }
}

String _formatDate(String? value) {
  if (value == null) return 'Abgeschlossen';
  final date = DateTime.tryParse(value)?.toLocal();
  if (date == null) return value;
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$day.$month.${date.year} · $hour:$minute';
}

double? _parseDecimalInput(String value) {
  final normalized = value.trim().replaceAll(',', '.');
  if (normalized.isEmpty) return null;
  return double.tryParse(normalized) ?? double.nan;
}
