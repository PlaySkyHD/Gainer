import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import 'training_view_model.dart';

class TrainingScreen extends StatefulWidget {
  const TrainingScreen({required this.viewModel, super.key});

  final TrainingViewModel viewModel;

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  late final TextEditingController _exerciseName = TextEditingController();
  late final TextEditingController _templateName = TextEditingController();
  late final TextEditingController _weight = TextEditingController();
  late final TextEditingController _repetitions = TextEditingController();
  String? _selectedExerciseId;

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
    _templateName.dispose();
    _weight.dispose();
    _repetitions.dispose();
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
              if (model.runningWorkout != null)
                _runningWorkout(model)
              else
                _planning(model),
              const SizedBox(height: 24),
              const Text('Abgeschlossene Workouts'),
              for (final item in model.history)
                Text(
                  '${item.value.templateNameSnapshot} · ${item.value.completedAtUtc ?? ''} · '
                  '${item.value.exercises.fold<int>(0, (count, exercise) => count + exercise.sets.where((set) => set.isCompleted).length)} Sätze',
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
          Row(
            children: [
              Expanded(child: Text(item.name)),
              if (plan?.customExercises.any((entry) => entry.id == item.id) ??
                  false)
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: model.isSaving
                      ? null
                      : () => model.archiveExercise(item.id),
                  child: const Text('Archivieren'),
                ),
            ],
          ),
        _field('Neue eigene Übung', _exerciseName),
        CupertinoButton(
          key: const ValueKey('training-create-exercise'),
          onPressed: model.isSaving
              ? null
              : () async {
                  await model.createExercise(_exerciseName.text);
                  _exerciseName.clear();
                },
          child: const Text('Übung anlegen'),
        ),
        const SizedBox(height: 12),
        const Text(
          'Template erstellen',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        _field('Template-Name', _templateName),
        if (exercises.isNotEmpty)
          CupertinoButton(
            key: const ValueKey('training-select-exercise'),
            padding: EdgeInsets.zero,
            onPressed: () => setState(() {
              final index = exercises.indexWhere(
                (item) => item.id == _selectedExerciseId,
              );
              _selectedExerciseId =
                  exercises[(index + 1) % exercises.length].id;
            }),
            child: Text(
              'Übung: ${exercises.firstWhere((item) => item.id == _selectedExerciseId, orElse: () => exercises.first).name} · wechseln',
            ),
          ),
        CupertinoButton.filled(
          key: const ValueKey('training-create-template'),
          onPressed: exercises.isEmpty || model.isSaving
              ? null
              : () async {
                  await model.createTemplate(
                    name: _templateName.text,
                    exerciseId: _selectedExerciseId ?? exercises.first.id,
                    sets: 3,
                    repetitions: 8,
                  );
                  _templateName.clear();
                },
          child: const Text('Template mit 3 × 8 speichern'),
        ),
        const SizedBox(height: 12),
        const Text(
          'Trainingsplan',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        for (var index = 0; index < templates.length; index++)
          Row(
            children: [
              Expanded(
                child: Text(
                  '${templates[index].value.name} · ${templates[index].value.items.length} Übungen',
                ),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: model.isSaving
                    ? null
                    : () => model.archiveTemplate(templates[index].id),
                child: const Text('Archivieren'),
              ),
              CupertinoButton(
                key: ValueKey('training-rotation-up-${templates[index].id}'),
                padding: EdgeInsets.zero,
                onPressed: index == 0 || model.isSaving
                    ? null
                    : () => model.moveTemplateInRotation(
                        templates.map((entry) => entry.id).toList(),
                        index,
                        index - 1,
                      ),
                child: const Text('↑'),
              ),
              CupertinoButton(
                key: ValueKey('training-rotation-down-${templates[index].id}'),
                padding: EdgeInsets.zero,
                onPressed: index == templates.length - 1 || model.isSaving
                    ? null
                    : () => model.moveTemplateInRotation(
                        templates.map((entry) => entry.id).toList(),
                        index,
                        index + 1,
                      ),
                child: const Text('↓'),
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

  Widget _runningWorkout(TrainingViewModel model) {
    final workout = model.runningWorkout!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          workout.templateNameSnapshot,
          key: const ValueKey('running-workout-title'),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        for (final choice in [
          ...?model.planning?.exercises.map(
            (entry) => (id: entry.id, name: entry.name),
          ),
          ...?model.planning?.customExercises
              .where((entry) => !entry.isArchived)
              .map((entry) => (id: entry.id, name: entry.value.name)),
        ])
          CupertinoButton(
            key: ValueKey('training-add-exercise-${choice.id}'),
            padding: EdgeInsets.zero,
            onPressed: model.isSaving
                ? null
                : () => model.addExercise(choice.id),
            child: Text('+ ${choice.name}'),
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
                for (final set in exercise.sets)
                  Row(
                    children: [
                      Expanded(child: Text('Satz ${set.position + 1}')),
                      Expanded(
                        child: _field(
                          'kg',
                          _weight,
                          compact: true,
                          numeric: true,
                        ),
                      ),
                      Expanded(
                        child: _field(
                          'Wdh.',
                          _repetitions,
                          compact: true,
                          numeric: true,
                        ),
                      ),
                      CupertinoButton(
                        key: ValueKey('training-log-${set.id}'),
                        padding: EdgeInsets.zero,
                        onPressed: model.isSaving
                            ? null
                            : () => model.logSet(
                                exerciseId: exercise.id,
                                setId: set.id,
                                weightKg: double.tryParse(_weight.text),
                                repetitions: int.tryParse(_repetitions.text),
                                complete: true,
                              ),
                        child: Text(set.isCompleted ? '✓' : 'Fertig'),
                      ),
                    ],
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
              Row(
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
    bool compact = false,
    bool numeric = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: CupertinoTextField(
      controller: controller,
      placeholder: label,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      padding: compact ? const EdgeInsets.all(8) : const EdgeInsets.all(12),
    ),
  );
}
