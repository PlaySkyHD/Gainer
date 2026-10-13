import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/training/training.dart';
import 'training_view_model.dart';

class TrainingScreen extends StatefulWidget {
  const TrainingScreen({required this.viewModel, super.key});

  final TrainingViewModel viewModel;

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  late final TextEditingController _exerciseName = TextEditingController();
  late final TextEditingController _exerciseDescription =
      TextEditingController();
  late final TextEditingController _exerciseTargetMuscle =
      TextEditingController();
  late final TextEditingController _exerciseMuscleGroup =
      TextEditingController();
  late final TextEditingController _exerciseEquipment = TextEditingController();
  late final TextEditingController _templateName = TextEditingController();
  final Map<String, _SetEditors> _setEditors = {};
  final List<_TemplateDraftItem> _templateItems = [];
  String? _selectedExerciseId;
  String? _editingExerciseId;
  String? _editingTemplateId;
  String? _expandedHistoryId;
  bool _exerciseEditorExpanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.viewModel.load(),
    );
  }

  @override
  void dispose() {
    _exerciseName.dispose();
    _exerciseDescription.dispose();
    _exerciseTargetMuscle.dispose();
    _exerciseMuscleGroup.dispose();
    _exerciseEquipment.dispose();
    _templateName.dispose();
    for (final item in _templateItems) {
      item.dispose();
    }
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
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (model.isLoading && model.planning == null)
                const Center(child: CupertinoActivityIndicator()),
              if (model.errorMessage != null)
                Text(
                  model.errorMessage!,
                  key: const ValueKey('training-error'),
                  style: const TextStyle(color: CupertinoColors.systemRed),
                ),
              if (model.notificationNotice != null)
                Text(
                  model.notificationNotice!,
                  key: const ValueKey('training-notification-notice'),
                  style: TextStyle(
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
              if (model.runningWorkout != null)
                _runningWorkout(model)
              else
                _planning(model),
              const SizedBox(height: 24),
              const Text('Abgeschlossene Workouts'),
              for (final item in model.history)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CupertinoButton(
                      key: ValueKey('training-history-${item.id}'),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      onPressed: () => setState(() {
                        _expandedHistoryId = _expandedHistoryId == item.id
                            ? null
                            : item.id;
                      }),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${item.value.templateNameSnapshot} · ${item.value.completedAtUtc ?? ''} · '
                          '${item.value.exercises.fold<int>(0, (count, exercise) => count + exercise.sets.where((set) => set.isCompleted).length)} Sätze',
                        ),
                      ),
                    ),
                    if (_expandedHistoryId == item.id)
                      _historyDetail(item.value),
                  ],
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _planning(TrainingViewModel model) {
    final plan = model.planning;
    final exercises = [
      ...?plan?.exercises.map((entry) => (id: entry.id, name: entry.name)),
      ...?plan?.customExercises
          .where((entry) => !entry.isArchived)
          .map((entry) => (id: entry.id, name: entry.value.name)),
    ];
    final templates =
        plan?.templates.where((item) => !item.value.isArchived).toList() ??
        const [];
    if (_selectedExerciseId == null && exercises.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedExerciseId == null) {
          setState(() => _selectedExerciseId = exercises.first.id);
        }
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Übungen',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        for (final item in exercises)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.name),
              if (plan?.customExercises.any((entry) => entry.id == item.id) ??
                  false)
                Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  children: [
                    CupertinoButton(
                      key: ValueKey('training-edit-exercise-${item.id}'),
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        final existing = plan!.customExercises.firstWhere(
                          (entry) => entry.id == item.id,
                        );
                        setState(() {
                          _exerciseEditorExpanded = true;
                          _editingExerciseId = item.id;
                          _exerciseName.text = existing.value.name;
                          _exerciseDescription.text =
                              existing.value.description ?? '';
                          _exerciseTargetMuscle.text =
                              existing.value.targetMuscle ?? '';
                          _exerciseMuscleGroup.text =
                              existing.value.muscleGroup ?? '';
                          _exerciseEquipment.text =
                              existing.value.equipment ?? '';
                        });
                      },
                      child: const Text('Bearbeiten'),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: model.isSaving
                          ? null
                          : () => model.archiveExercise(item.id),
                      child: const Text('Archivieren'),
                    ),
                  ],
                ),
            ],
          ),
        CupertinoButton(
          key: const ValueKey('training-toggle-exercise-editor'),
          padding: EdgeInsets.zero,
          onPressed: () => setState(() {
            _exerciseEditorExpanded = !_exerciseEditorExpanded;
          }),
          child: Text(
            _exerciseEditorExpanded
                ? 'Eigene Übung schließen'
                : 'Eigene Übung anlegen oder bearbeiten',
          ),
        ),
        if (_exerciseEditorExpanded) ...[
          _field(
            _editingExerciseId == null ? 'Neue eigene Übung' : 'Übungsname',
            _exerciseName,
          ),
          _field('Beschreibung', _exerciseDescription),
          _field('Zielmuskel', _exerciseTargetMuscle),
          _field('Muskelgruppe', _exerciseMuscleGroup),
          _field('Ausrüstung', _exerciseEquipment),
          CupertinoButton(
            key: const ValueKey('training-create-exercise'),
            onPressed: model.isSaving
                ? null
                : () async {
                    await model.saveExercise(
                      _editingExerciseId,
                      ExerciseValues(
                        name: _exerciseName.text,
                        description: _exerciseDescription.text,
                        targetMuscle: _exerciseTargetMuscle.text,
                        muscleGroup: _exerciseMuscleGroup.text,
                        equipment: _exerciseEquipment.text,
                      ),
                    );
                    _clearExerciseEditor();
                  },
            child: Text(
              _editingExerciseId == null ? 'Übung anlegen' : 'Übung speichern',
            ),
          ),
        ],
        const SizedBox(height: 12),
        const Text(
          'Template erstellen und bearbeiten',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        _field('Template-Name', _templateName),
        for (var index = 0; index < _templateItems.length; index++)
          _templateItemEditor(exercises, index),
        if (exercises.isNotEmpty)
          CupertinoButton(
            key: const ValueKey('training-add-template-exercise'),
            onPressed: () => setState(() {
              _templateItems.add(
                _TemplateDraftItem(
                  id: widget.viewModel.repository.ids(),
                  exerciseId: _selectedExerciseId ?? exercises.first.id,
                ),
              );
            }),
            child: const Text('Übung zum Template hinzufügen'),
          ),
        CupertinoButton.filled(
          key: const ValueKey('training-create-template'),
          onPressed:
              exercises.isEmpty || _templateItems.isEmpty || model.isSaving
              ? null
              : () async {
                  await model.saveTemplate(
                    id: _editingTemplateId,
                    name: _templateName.text,
                    items: [
                      for (final item in _templateItems)
                        TrainingTemplateItem(
                          id: item.id,
                          exerciseId: item.exerciseId,
                          plannedSets: int.tryParse(item.sets.text) ?? 0,
                          minimumRepetitions:
                              int.tryParse(item.minimumRepetitions.text) ?? 0,
                          maximumRepetitions:
                              int.tryParse(item.maximumRepetitions.text) ?? 0,
                          targetRir: double.tryParse(item.targetRir.text),
                          restSeconds: int.tryParse(item.restSeconds.text),
                          notes: item.notes.text,
                        ),
                    ],
                  );
                  _clearTemplateEditor();
                },
          child: Text(
            _editingTemplateId == null
                ? 'Template speichern'
                : 'Template-Änderungen speichern',
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Trainingsplan',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        for (var index = 0; index < templates.length; index++)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${templates[index].value.name} · ${templates[index].value.items.length} Übungen',
              ),
              Wrap(
                spacing: 4,
                runSpacing: 2,
                children: [
                  CupertinoButton(
                    key: ValueKey(
                      'training-template-edit-${templates[index].id}',
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: model.isSaving
                        ? null
                        : () => _editTemplate(templates[index]),
                    child: const Text('Bearbeiten'),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: model.isSaving
                        ? null
                        : () => model.archiveTemplate(templates[index].id),
                    child: const Text('Archivieren'),
                  ),
                  CupertinoButton(
                    key: ValueKey(
                      'training-rotation-up-${templates[index].id}',
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: index == 0 || model.isSaving
                        ? null
                        : () => model.moveTemplateInRotation(
                            templates.map((entry) => entry.id).toList(),
                            index,
                            index - 1,
                          ),
                    child: const Text('↑ Reihenfolge'),
                  ),
                  CupertinoButton(
                    key: ValueKey(
                      'training-rotation-down-${templates[index].id}',
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: index == templates.length - 1 || model.isSaving
                        ? null
                        : () => model.moveTemplateInRotation(
                            templates.map((entry) => entry.id).toList(),
                            index,
                            index + 1,
                          ),
                    child: const Text('↓ Reihenfolge'),
                  ),
                  CupertinoButton(
                    key: ValueKey('training-start-${templates[index].id}'),
                    onPressed: model.isSaving
                        ? null
                        : () => model.start(templates[index].id),
                    child: const Text('Start'),
                  ),
                ],
              ),
            ],
          ),
        if (templates.isNotEmpty)
          CupertinoButton(
            key: const ValueKey('training-save-rotation'),
            onPressed: model.isSaving
                ? null
                : () => model.saveRotation(
                    templates.map((entry) => entry.id).toList(),
                  ),
            child: const Text('Rotation speichern'),
          ),
      ],
    );
  }

  Widget _templateItemEditor(
    List<({String id, String name})> exercises,
    int index,
  ) {
    final item = _templateItems[index];
    final selected = exercises.where(
      (exercise) => exercise.id == item.exerciseId,
    );
    final exerciseName = selected.isEmpty
        ? 'Übung auswählen'
        : selected.first.name;
    return Container(
      key: ValueKey('training-template-item-${item.id}'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: CupertinoColors.separator),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Template-Übung ${index + 1}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Wrap(
            spacing: 6,
            children: [
              CupertinoButton(
                key: ValueKey('training-template-select-exercise-${item.id}'),
                padding: EdgeInsets.zero,
                onPressed: exercises.isEmpty
                    ? null
                    : () async {
                        final id = await _chooseExercise(exercises);
                        if (id != null && mounted) {
                          setState(() => item.exerciseId = id);
                        }
                      },
                child: Text(exerciseName),
              ),
              CupertinoButton(
                key: ValueKey('training-template-up-${item.id}'),
                padding: EdgeInsets.zero,
                onPressed: index == 0
                    ? null
                    : () => setState(() {
                        _templateItems.removeAt(index);
                        _templateItems.insert(index - 1, item);
                      }),
                child: const Text('↑'),
              ),
              CupertinoButton(
                key: ValueKey('training-template-down-${item.id}'),
                padding: EdgeInsets.zero,
                onPressed: index == _templateItems.length - 1
                    ? null
                    : () => setState(() {
                        _templateItems.removeAt(index);
                        _templateItems.insert(index + 1, item);
                      }),
                child: const Text('↓'),
              ),
              CupertinoButton(
                key: ValueKey('training-template-remove-${item.id}'),
                padding: EdgeInsets.zero,
                onPressed: () => setState(() {
                  _templateItems.removeAt(index).dispose();
                }),
                child: const Text('Entfernen'),
              ),
            ],
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final fieldWidth = (constraints.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  SizedBox(
                    width: fieldWidth,
                    child: _field(
                      'Sätze',
                      item.sets,
                      key: ValueKey('training-item-sets-${item.id}'),
                      numeric: true,
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _field(
                      'Wdh. min.',
                      item.minimumRepetitions,
                      key: ValueKey('training-item-min-${item.id}'),
                      numeric: true,
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _field(
                      'Wdh. max.',
                      item.maximumRepetitions,
                      key: ValueKey('training-item-max-${item.id}'),
                      numeric: true,
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _field(
                      'Ziel-RIR',
                      item.targetRir,
                      key: ValueKey('training-item-rir-${item.id}'),
                      numeric: true,
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _field(
                      'Pause in Sekunden',
                      item.restSeconds,
                      key: ValueKey('training-item-rest-${item.id}'),
                      numeric: true,
                    ),
                  ),
                  SizedBox(
                    width: constraints.maxWidth,
                    child: _field(
                      'Übungsnotiz',
                      item.notes,
                      key: ValueKey('training-item-notes-${item.id}'),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<String?> _chooseExercise(
    List<({String id, String name})> exercises,
  ) async {
    final search = TextEditingController();
    try {
      return await showCupertinoModalPopup<String>(
        context: context,
        builder: (context) => SafeArea(
          child: CupertinoPopupSurface(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.75,
              child: StatefulBuilder(
                builder: (context, setSheetState) {
                  final query = search.text.trim().toLowerCase();
                  final matches = exercises
                      .where((item) => item.name.toLowerCase().contains(query))
                      .toList();
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: CupertinoTextField(
                          controller: search,
                          placeholder: 'Übung suchen',
                          prefix: const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Icon(CupertinoIcons.search),
                          ),
                          onChanged: (_) => setSheetState(() {}),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: matches.length,
                          itemBuilder: (context, index) => CupertinoButton(
                            key: ValueKey(
                              'exercise-choice-${matches[index].id}',
                            ),
                            alignment: Alignment.centerLeft,
                            onPressed: () =>
                                Navigator.of(context).pop(matches[index].id),
                            child: Text(matches[index].name),
                          ),
                        ),
                      ),
                      CupertinoButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Abbrechen'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
    } finally {
      search.dispose();
    }
  }

  void _editTemplate(({String id, TrainingTemplate value}) template) {
    for (final item in _templateItems) {
      item.dispose();
    }
    setState(() {
      _editingTemplateId = template.id;
      _templateName.text = template.value.name;
      _templateItems
        ..clear()
        ..addAll(template.value.items.map(_TemplateDraftItem.fromRecord));
    });
  }

  void _clearTemplateEditor() {
    for (final item in _templateItems) {
      item.dispose();
    }
    setState(() {
      _templateItems.clear();
      _templateName.clear();
      _editingTemplateId = null;
    });
  }

  void _clearExerciseEditor() {
    setState(() {
      _editingExerciseId = null;
      _exerciseName.clear();
      _exerciseDescription.clear();
      _exerciseTargetMuscle.clear();
      _exerciseMuscleGroup.clear();
      _exerciseEquipment.clear();
    });
  }

  Widget _historyDetail(WorkoutRecord workout) => Padding(
    padding: const EdgeInsets.only(left: 12, bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final exercise in workout.exercises)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exercise.exerciseNameSnapshot,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${exercise.plannedSets} Sätze · ${exercise.minimumRepetitions}–${exercise.maximumRepetitions} Wdh. geplant',
                ),
                for (final set in exercise.sets.where(
                  (entry) => entry.isCompleted,
                ))
                  Text(
                    'Satz ${set.position + 1}: ${set.weightKg?.toStringAsFixed(1) ?? '–'} kg × ${set.repetitions ?? '–'} Wdh.'
                    '${set.rir == null ? '' : ' · RIR ${set.rir}'}${set.notes == null || set.notes!.isEmpty ? '' : ' · ${set.notes}'}',
                  ),
              ],
            ),
          ),
      ],
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
        Text(
          workout.templateNameSnapshot,
          key: const ValueKey('running-workout-title'),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        CupertinoButton(
          key: const ValueKey('training-add-exercise'),
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
                          border: Border.all(color: CupertinoColors.separator),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text('Satz ${set.position + 1}'),
                                ),
                                CupertinoButton(
                                  key: ValueKey('training-set-up-${set.id}'),
                                  padding: EdgeInsets.zero,
                                  onPressed: set.position == 0 || model.isSaving
                                      ? null
                                      : () => model.moveSet(
                                          exercise.id,
                                          set.id,
                                          set.position - 1,
                                        ),
                                  child: const Text('↑'),
                                ),
                                CupertinoButton(
                                  key: ValueKey('training-set-down-${set.id}'),
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
                                  child: const Text('↓'),
                                ),
                                CupertinoButton(
                                  key: ValueKey(
                                    'training-remove-set-${set.id}',
                                  ),
                                  padding: EdgeInsets.zero,
                                  onPressed:
                                      exercise.sets.length <= 1 ||
                                          model.isSaving
                                      ? null
                                      : () => model.removeSet(
                                          exercise.id,
                                          set.id,
                                        ),
                                  child: const Text('Entfernen'),
                                ),
                              ],
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
                              padding: EdgeInsets.zero,
                              onPressed: model.isSaving
                                  ? null
                                  : () => model.logSet(
                                      exerciseId: exercise.id,
                                      setId: set.id,
                                      weightKg: double.tryParse(
                                        editors.weight.text,
                                      ),
                                      repetitions: int.tryParse(
                                        editors.repetitions.text,
                                      ),
                                      rir: double.tryParse(editors.rir.text),
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
                          ],
                        ),
                      );
                    },
                  ),
                CupertinoButton(
                  key: ValueKey('training-add-set-${exercise.id}'),
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pause: ${model.remainingRestSeconds ?? 0} s',
                key: const ValueKey('training-rest-timer'),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  CupertinoButton(
                    onPressed: () => model.timerAction(
                      (id) => model.repository.extendRestTimer(id),
                    ),
                    child: const Text('+30 s'),
                  ),
                  CupertinoButton(
                    onPressed: () =>
                        model.timerAction(model.repository.restartRestTimer),
                    child: const Text('Neu starten'),
                  ),
                  CupertinoButton(
                    onPressed: () =>
                        model.timerAction(model.repository.skipRestTimer),
                    child: const Text('Überspringen'),
                  ),
                ],
              ),
            ],
          ),
        CupertinoButton.filled(
          key: const ValueKey('training-complete-workout'),
          onPressed: model.isSaving ? null : model.finish,
          child: const Text('Workout abschließen'),
        ),
        CupertinoButton(
          key: const ValueKey('training-discard-workout'),
          onPressed: model.isSaving ? null : model.discard,
          child: const Text('Verwerfen'),
        ),
      ],
    );
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
      padding: compact ? const EdgeInsets.all(8) : const EdgeInsets.all(12),
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

class _TemplateDraftItem {
  _TemplateDraftItem({required this.id, required this.exerciseId});

  factory _TemplateDraftItem.fromRecord(TrainingTemplateItem item) =>
      _TemplateDraftItem(id: item.id, exerciseId: item.exerciseId)
        ..sets.text = item.plannedSets.toString()
        ..minimumRepetitions.text = item.minimumRepetitions.toString()
        ..maximumRepetitions.text = item.maximumRepetitions.toString()
        ..targetRir.text = item.targetRir?.toString() ?? ''
        ..restSeconds.text = item.restSeconds?.toString() ?? ''
        ..notes.text = item.notes ?? '';

  final String id;
  String exerciseId;
  final TextEditingController sets = TextEditingController();
  final TextEditingController minimumRepetitions = TextEditingController();
  final TextEditingController maximumRepetitions = TextEditingController();
  final TextEditingController targetRir = TextEditingController();
  final TextEditingController restSeconds = TextEditingController();
  final TextEditingController notes = TextEditingController();

  void dispose() {
    sets.dispose();
    minimumRepetitions.dispose();
    maximumRepetitions.dispose();
    targetRir.dispose();
    restSeconds.dispose();
    notes.dispose();
  }
}
