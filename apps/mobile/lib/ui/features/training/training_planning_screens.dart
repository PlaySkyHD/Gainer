import 'package:flutter/cupertino.dart';

import '../../../data/repositories/training/training_repository.dart';
import '../../../domain/models/training/training.dart';
import '../../core/theme.dart';
import 'training_view_model.dart';

const _customExerciseLabel = 'Eigene Übung';

class TrainingExerciseLibraryScreen extends StatefulWidget {
  const TrainingExerciseLibraryScreen({required this.viewModel, super.key});

  final TrainingViewModel viewModel;

  @override
  State<TrainingExerciseLibraryScreen> createState() =>
      _TrainingExerciseLibraryScreenState();
}

class _TrainingExerciseLibraryScreenState
    extends State<TrainingExerciseLibraryScreen> {
  final _search = TextEditingController();
  String _source = 'all';
  String? _muscleGroup;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.viewModel;
    final exercises = _exerciseSummaries(model.planning);
    final groups = _muscleGroups(exercises);
    final matches = _matchingExercises(exercises);

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Übungsbibliothek'),
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: constraints.maxWidth > 640 ? 640 : null,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                children: [
                  Text(
                    'Finde deine Übung',
                    style: CupertinoTheme.of(context)
                        .textTheme
                        .navLargeTitleTextStyle,
                  ),
                  const SizedBox(height: 12),
                  CupertinoSearchTextField(
                    key: const ValueKey('training-exercise-search'),
                    controller: _search,
                    placeholder: 'Name, Muskel oder Equipment',
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  CupertinoSlidingSegmentedControl<String>(
                    groupValue: _source,
                    children: const {
                      'all': Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('Alle'),
                      ),
                      'catalog': Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('Katalog'),
                      ),
                      'custom': Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('Eigene'),
                      ),
                    },
                    onValueChanged: (value) {
                      if (value != null) setState(() => _source = value);
                    },
                  ),
                  if (groups.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _muscleGroupFilters(groups),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${matches.length} ${matches.length == 1 ? 'Übung' : 'Übungen'}',
                          style: CupertinoTheme.of(context)
                              .textTheme
                              .navTitleTextStyle,
                        ),
                      ),
                      CupertinoButton(
                        key: const ValueKey('training-new-custom-exercise'),
                        minimumSize: const Size.square(48),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        color: GainerTheme.actionColor(context),
                        onPressed: () => _editExercise(context, null),
                        child: const Text(
                          _customExerciseLabel,
                          style: TextStyle(color: CupertinoColors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._exerciseListChildren(context, matches),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<String> _muscleGroups(List<TrainingExerciseSummary> exercises) =>
      exercises
          .map((item) => item.value.muscleGroup?.trim())
          .whereType<String>()
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

  List<TrainingExerciseSummary> _matchingExercises(
    List<TrainingExerciseSummary> exercises,
  ) {
    final query = _search.text.trim().toLowerCase();
    return exercises.where((item) {
      final value = item.value;
      final text = [
        value.name,
        value.description,
        value.targetMuscle,
        value.muscleGroup,
        value.equipment,
      ].whereType<String>().join(' ').toLowerCase();
      return (_source == 'all' || (_source == 'custom') == item.isCustom) &&
          (_muscleGroup == null || value.muscleGroup == _muscleGroup) &&
          (query.isEmpty || text.contains(query));
    }).toList();
  }

  Widget _muscleGroupFilters(List<String> groups) => SizedBox(
    height: 48,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        _FilterChip(
          label: 'Alle Muskelgruppen',
          selected: _muscleGroup == null,
          onPressed: () => setState(() => _muscleGroup = null),
        ),
        for (final group in groups)
          _FilterChip(
            label: group,
            selected: _muscleGroup == group,
            onPressed: () => setState(() => _muscleGroup = group),
          ),
      ],
    ),
  );

  List<Widget> _exerciseListChildren(
    BuildContext context,
    List<TrainingExerciseSummary> matches,
  ) {
    if (matches.isEmpty) {
      return const [
        _PlanningEmptyCard(
          title: 'Keine passenden Übungen',
          subtitle: 'Ändere deine Suche oder wähle eine andere Muskelgruppe.',
        ),
      ];
    }
    return [
      for (final item in matches)
        _ExerciseCard(
          key: ValueKey('training-exercise-${item.id}'),
          summary: item,
          onEdit: item.isCustom ? () => _editExercise(context, item) : null,
          onArchive: item.isCustom
              ? () => _archiveExercise(context, item)
              : null,
        ),
    ];
  }

  Future<void> _editExercise(
    BuildContext context,
    TrainingExerciseSummary? item,
  ) async {
    await Navigator.of(context).push<bool>(
      CupertinoPageRoute<bool>(
        builder: (_) => TrainingExerciseEditorScreen(
          viewModel: widget.viewModel,
          exercise: item,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _archiveExercise(
    BuildContext context,
    TrainingExerciseSummary item,
  ) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Übung archivieren?'),
        content: const Text(
          'Vorhandene Vorlagen und abgeschlossene Trainings behalten ihre gespeicherten Übungsdaten.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archivieren'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.viewModel.archiveExercise(item.id);
    if (mounted) setState(() {});
  }
}

class TrainingExerciseEditorScreen extends StatefulWidget {
  const TrainingExerciseEditorScreen({
    required this.viewModel,
    this.exercise,
    super.key,
  });

  final TrainingViewModel viewModel;
  final TrainingExerciseSummary? exercise;

  @override
  State<TrainingExerciseEditorScreen> createState() =>
      _TrainingExerciseEditorScreenState();
}

class _TrainingExerciseEditorScreenState
    extends State<TrainingExerciseEditorScreen> {
  late final _name = TextEditingController(text: widget.exercise?.value.name);
  late final _description = TextEditingController(
    text: widget.exercise?.value.description,
  );
  late final _target = TextEditingController(
    text: widget.exercise?.value.targetMuscle,
  );
  late final _group = TextEditingController(
    text: widget.exercise?.value.muscleGroup,
  );
  late final _equipment = TextEditingController(
    text: widget.exercise?.value.equipment,
  );
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _target.dispose();
    _group.dispose();
    _equipment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: CupertinoNavigationBar(
      middle: Text(
        widget.exercise == null ? _customExerciseLabel : 'Übung bearbeiten',
      ),
      trailing: CupertinoButton(
        key: const ValueKey('training-cancel-exercise'),
        minimumSize: const Size.square(48),
        padding: EdgeInsets.zero,
        onPressed: () => Navigator.of(context).maybePop(false),
        child: const Text('Abbrechen'),
      ),
    ),
    child: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: constraints.maxWidth > 600 ? 600 : null,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                20,
                18,
                20,
                MediaQuery.viewInsetsOf(context).bottom + 24,
              ),
              children: [
                Text(
                  widget.exercise == null
                      ? 'Neue Übung'
                      : widget.exercise!.value.name,
                  style: CupertinoTheme.of(context)
                      .textTheme
                      .navLargeTitleTextStyle,
                ),
                const SizedBox(height: 18),
                _FormField(
                  label: 'Name',
                  controller: _name,
                  key: const ValueKey('training-exercise-name'),
                ),
                _FormField(label: 'Muskelgruppe', controller: _group),
                _FormField(label: 'Equipment', controller: _equipment),
                _FormField(label: 'Zielmuskel', controller: _target),
                _FormField(
                  label: 'Beschreibung',
                  controller: _description,
                  maxLines: 3,
                ),
                if (widget.viewModel.errorMessage case final message?)
                  _FormNotice(message: message),
                const SizedBox(height: 12),
                CupertinoButton(
                  key: const ValueKey('training-save-exercise'),
                  minimumSize: const Size.square(52),
                  color: GainerTheme.actionColor(context),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? CupertinoActivityIndicator(
                          color: GainerTheme.secondaryText(context),
                        )
                      : Text(
                          'Übung speichern',
                          style: TextStyle(
                            color: _saving
                                ? GainerTheme.secondaryText(context)
                                : CupertinoColors.white,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.viewModel.saveExercise(
      widget.exercise?.id,
      ExerciseValues(
        name: _name.text,
        description: _description.text,
        targetMuscle: _target.text,
        muscleGroup: _group.text,
        equipment: _equipment.text,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (widget.viewModel.errorMessage == null) {
      Navigator.of(context).pop(true);
    }
  }
}

class TrainingTemplateLibraryScreen extends StatefulWidget {
  const TrainingTemplateLibraryScreen({required this.viewModel, super.key});
  final TrainingViewModel viewModel;

  @override
  State<TrainingTemplateLibraryScreen> createState() =>
      _TrainingTemplateLibraryScreenState();
}

class _TrainingTemplateLibraryScreenState
    extends State<TrainingTemplateLibraryScreen> {
  late List<String> _rotationIds = _readRotation();

  List<String> _readRotation() =>
      widget.viewModel.planning?.rotation?.value.entries
          .map((entry) => entry.templateId)
          .toList() ??
      <String>[];

  @override
  Widget build(BuildContext context) {
    final model = widget.viewModel;
    final templates = model.planning?.templates ?? const [];
    final active = templates.where((item) => !item.value.isArchived).toList();
    final archived = templates.where((item) => item.value.isArchived).toList();
    final nextId = model.planning?.nextTemplateId;
    final nextName = _firstOrNull(
      active.where((item) => item.id == nextId).map((item) => item.value.name),
    );

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Vorlagen & Rotation'),
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: constraints.maxWidth > 640 ? 640 : null,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
                children: [
                  Text(
                    'Trainingsplan',
                    style: CupertinoTheme.of(context)
                        .textTheme
                        .navLargeTitleTextStyle,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    nextName == null
                        ? 'Noch keine nächste Einheit ausgewählt.'
                        : 'Nächstes Training: $nextName',
                    style: TextStyle(color: GainerTheme.secondaryText(context)),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Vorlagen',
                          style: CupertinoTheme.of(context)
                              .textTheme
                              .navTitleTextStyle,
                        ),
                      ),
                      CupertinoButton(
                        key: const ValueKey('training-template-new'),
                        minimumSize: const Size.square(48),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        color: GainerTheme.actionColor(context),
                        onPressed: () => _openEditor(context, null),
                        child: const Text(
                          'Neue Vorlage',
                          style: TextStyle(color: CupertinoColors.white),
                        ),
                      ),
                    ],
                  ),
                  ..._templateListChildren(context, model, active, nextId),
                  const SizedBox(height: 18),
                  Text(
                    'Rotation',
                    style: CupertinoTheme.of(context)
                        .textTheme
                        .navTitleTextStyle,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Die Reihenfolge wechselt nach jeder abgeschlossenen Einheit weiter.',
                    style: TextStyle(color: GainerTheme.secondaryText(context)),
                  ),
                  ..._rotationChildren(context, templates),
                  if (active.any((item) => !_rotationIds.contains(item.id)))
                    CupertinoButton(
                      key: const ValueKey('training-rotation-add'),
                      minimumSize: const Size.square(48),
                      onPressed: () => _addToRotation(context, active),
                      child: const Text('Vorlage zur Rotation hinzufügen'),
                    ),
                  _saveRotationButton(context, model),
                  if (model.errorMessage case final message?)
                    _FormNotice(message: message),
                  if (archived.isNotEmpty) ..._archivedRows(context, archived),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _templateListChildren(
    BuildContext context,
    TrainingViewModel model,
    List<({String id, TrainingTemplate value})> active,
    String? nextId,
  ) {
    if (active.isEmpty) {
      return [
        _PlanningEmptyCard(
          title: 'Noch keine Vorlagen',
          subtitle: 'Erstelle eine Einheit und füge passende Übungen hinzu.',
          actionLabel: 'Vorlage erstellen',
          onPressed: () => _openEditor(context, null),
        ),
      ];
    }
    return [
      for (final template in active)
        _TemplateCard(
          key: ValueKey('training-template-${template.id}'),
          template: template,
          isNext: template.id == nextId,
          onEdit: () => _openEditor(context, template),
          onStart: model.isSaving
              ? null
              : () => _startFromTemplate(context, model, template.id),
          onArchive: () => _archiveTemplate(context, template),
        ),
    ];
  }

  Future<void> _startFromTemplate(
    BuildContext context,
    TrainingViewModel model,
    String templateId,
  ) async {
    await model.start(templateId);
    if (context.mounted && model.runningWorkout != null) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  List<Widget> _rotationChildren(
    BuildContext context,
    List<({String id, TrainingTemplate value})> templates,
  ) {
    if (_rotationIds.isEmpty) {
      return const [
        _PlanningEmptyCard(
          title: 'Rotation noch leer',
          subtitle: 'Füge unten Vorlagen hinzu. Ohne Rotation kannst du jede Vorlage direkt starten.',
        ),
      ];
    }
    return [
      for (var index = 0; index < _rotationIds.length; index++)
        _RotationRow(
          key: ValueKey('training-rotation-${_rotationIds[index]}'),
          position: index + 1,
          name: _templateName(templates, _rotationIds[index]),
          canMoveUp: index > 0,
          canMoveDown: index < _rotationIds.length - 1,
          onUp: () => setState(() => _move(index, index - 1)),
          onDown: () => setState(() => _move(index, index + 1)),
          onRemove: () => setState(() => _rotationIds.removeAt(index)),
        ),
    ];
  }

  Widget _saveRotationButton(BuildContext context, TrainingViewModel model) =>
      CupertinoButton(
        key: const ValueKey('training-save-rotation'),
        minimumSize: const Size.square(52),
        color: GainerTheme.actionColor(context),
        onPressed: model.isSaving ? null : _saveRotation,
        child: Text(
          'Rotation speichern',
          style: TextStyle(
            color: model.isSaving
                ? GainerTheme.secondaryText(context)
                : CupertinoColors.white,
          ),
        ),
      );

  List<Widget> _archivedRows(
    BuildContext context,
    List<({String id, TrainingTemplate value})> archived,
  ) => [
    const SizedBox(height: 22),
    Text(
      'Archiviert',
      style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
    ),
    for (final item in archived)
      _PlanningRow(
        title: item.value.name,
        subtitle: '${item.value.items.length} Übungen · archiviert',
        muted: true,
      ),
  ];

  Future<void> _openEditor(
    BuildContext context,
    ({String id, TrainingTemplate value})? template,
  ) async {
    await Navigator.of(context).push<bool>(
      CupertinoPageRoute<bool>(
        builder: (_) => TrainingTemplateEditorScreen(
          viewModel: widget.viewModel,
          template: template,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _saveRotation() async {
    await widget.viewModel.saveRotation(_rotationIds);
    if (mounted) setState(() {});
  }

  void _move(int from, int to) {
    final item = _rotationIds.removeAt(from);
    _rotationIds.insert(to, item);
  }

  String _templateName(
    List<({String id, TrainingTemplate value})> templates,
    String id,
  ) =>
      _firstOrNull(
        templates.where((item) => item.id == id).map((item) => item.value.name),
      ) ??
      'Nicht verfügbare Vorlage';

  Future<void> _addToRotation(
    BuildContext context,
    List<({String id, TrainingTemplate value})> active,
  ) async {
    final available = active
        .where((item) => !_rotationIds.contains(item.id))
        .toList();
    final selected = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Vorlage hinzufügen'),
        actions: [
          for (final item in available)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, item.id),
              child: Text(item.value.name),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
      ),
    );
    if (selected != null && mounted) setState(() => _rotationIds.add(selected));
  }

  Future<void> _archiveTemplate(
    BuildContext context,
    ({String id, TrainingTemplate value}) template,
  ) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Vorlage archivieren?'),
        content: const Text(
          'Die Vorlage wird in der Rotation übersprungen. Abgeschlossene Trainings behalten ihren historischen Stand.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archivieren'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.viewModel.archiveTemplate(template.id);
    if (mounted) setState(() => _rotationIds = _readRotation());
  }
}

class TrainingTemplateEditorScreen extends StatefulWidget {
  const TrainingTemplateEditorScreen({
    required this.viewModel,
    this.template,
    super.key,
  });
  final TrainingViewModel viewModel;
  final ({String id, TrainingTemplate value})? template;

  @override
  State<TrainingTemplateEditorScreen> createState() =>
      _TrainingTemplateEditorScreenState();
}

class _TrainingTemplateEditorScreenState
    extends State<TrainingTemplateEditorScreen> {
  late final _name = TextEditingController(text: widget.template?.value.name);
  late final List<_TemplateDraft> _items = [
    for (final item
        in widget.template?.value.items ?? const <TrainingTemplateItem>[])
      _TemplateDraft.fromRecord(item),
  ];
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.viewModel;
    final exercises = _exerciseSummaries(model.planning);
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          widget.template == null ? 'Vorlage erstellen' : 'Vorlage bearbeiten',
        ),
        trailing: CupertinoButton(
          key: const ValueKey('training-cancel-template'),
          minimumSize: const Size.square(48),
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).maybePop(false),
          child: const Text('Abbrechen'),
        ),
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: constraints.maxWidth > 640 ? 640 : null,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  18,
                  20,
                  MediaQuery.viewInsetsOf(context).bottom + 28,
                ),
                children: [
                  Text(
                    widget.template == null
                        ? 'Deine Einheit'
                        : widget.template!.value.name,
                    style: CupertinoTheme.of(context)
                        .textTheme
                        .navLargeTitleTextStyle,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Name und Übungen bleiben als lokaler Entwurf erhalten, bis du speicherst.',
                    style: TextStyle(color: GainerTheme.secondaryText(context)),
                  ),
                  const SizedBox(height: 16),
                  _FormField(
                    label: 'Vorlagenname',
                    controller: _name,
                    key: const ValueKey('training-template-name'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Übungen',
                    style: CupertinoTheme.of(context)
                        .textTheme
                        .navTitleTextStyle,
                  ),
                  ..._itemCards(context, exercises),
                  CupertinoButton(
                    key: const ValueKey('training-add-template-exercise'),
                    minimumSize: const Size.square(48),
                    onPressed: exercises.isEmpty
                        ? null
                        : () => _chooseExercise(context, exercises, null),
                    child: const Text('+ Übung hinzufügen'),
                  ),
                  if (model.errorMessage case final message?)
                    _FormNotice(message: message),
                  const SizedBox(height: 12),
                  _saveButton(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _itemCards(
    BuildContext context,
    List<TrainingExerciseSummary> exercises,
  ) => [
    if (_items.isEmpty)
      const _PlanningEmptyCard(
        title: 'Füge zuerst eine Übung hinzu',
        subtitle: 'Du kannst Reihenfolge, Sätze und Wiederholungsbereich jederzeit ändern.',
      ),
    for (var index = 0; index < _items.length; index++)
      _TemplateDraftCard(
        key: ValueKey('training-template-item-${_items[index].id}'),
        item: _items[index],
        position: index,
        exerciseName: _exerciseName(exercises, _items[index].exerciseId),
        onChooseExercise: exercises.isEmpty
            ? null
            : () => _chooseExercise(context, exercises, _items[index]),
        onMoveUp: index == 0
            ? null
            : () => setState(() => _move(index, index - 1)),
        onMoveDown: index == _items.length - 1
            ? null
            : () => setState(() => _move(index, index + 1)),
        onRemove: () => setState(() => _items.removeAt(index).dispose()),
      ),
  ];

  Widget _saveButton(BuildContext context) => CupertinoButton(
    key: const ValueKey('training-create-template'),
    minimumSize: const Size.square(52),
    color: GainerTheme.actionColor(context),
    onPressed: _saving || _items.isEmpty ? null : _save,
    child: _saving
        ? CupertinoActivityIndicator(color: GainerTheme.secondaryText(context))
        : Text(
            widget.template == null
                ? 'Vorlage speichern'
                : 'Änderungen speichern',
            style: TextStyle(
              color: _items.isEmpty
                  ? GainerTheme.secondaryText(context)
                  : CupertinoColors.white,
            ),
          ),
  );

  String _exerciseName(List<TrainingExerciseSummary> exercises, String id) =>
      _firstOrNull(
        exercises.where((item) => item.id == id).map((item) => item.value.name),
      ) ??
      'Übung auswählen';

  Future<void> _chooseExercise(
    BuildContext context,
    List<TrainingExerciseSummary> exercises,
    _TemplateDraft? existing,
  ) async {
    final id = await Navigator.of(context).push<String>(
      CupertinoPageRoute<String>(
        builder: (_) => _TrainingExercisePickerScreen(exercises: exercises),
      ),
    );
    if (id == null || !mounted) return;
    setState(() {
      if (existing != null) {
        existing.exerciseId = id;
      } else {
        _items.add(
          _TemplateDraft(id: widget.viewModel.repository.ids(), exerciseId: id),
        );
      }
    });
  }

  void _move(int from, int to) {
    final item = _items.removeAt(from);
    _items.insert(to, item);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.viewModel.saveTemplate(
      id: widget.template?.id,
      name: _name.text,
      items: [for (final item in _items) item.toRecord()],
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (widget.viewModel.errorMessage == null) Navigator.of(context).pop(true);
  }
}

class _TrainingExercisePickerScreen extends StatefulWidget {
  const _TrainingExercisePickerScreen({required this.exercises});
  final List<TrainingExerciseSummary> exercises;

  @override
  State<_TrainingExercisePickerScreen> createState() =>
      _TrainingExercisePickerScreenState();
}

class _TrainingExercisePickerScreenState
    extends State<_TrainingExercisePickerScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final matches = widget.exercises
        .where((item) => item.value.name.toLowerCase().contains(query))
        .toList();
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Übung auswählen'),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          children: [
            CupertinoSearchTextField(
              key: const ValueKey('training-template-exercise-search'),
              controller: _search,
              placeholder: 'Übung suchen',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            for (final item in matches)
              _ExerciseCard(
                key: ValueKey('exercise-choice-${item.id}'),
                summary: item,
                onPressed: () => Navigator.of(context).pop(item.id),
              ),
            if (matches.isEmpty)
              const _PlanningEmptyCard(
                title: 'Keine Treffer',
                subtitle: 'Probiere einen anderen Namen.',
              ),
          ],
        ),
      ),
    );
  }
}

class TrainingHistoryScreen extends StatelessWidget {
  const TrainingHistoryScreen({required this.viewModel, super.key});
  final TrainingViewModel viewModel;

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(
      middle: Text('Trainingsverlauf'),
    ),
    child: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: constraints.maxWidth > 640 ? 640 : null,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
              children: [
                Text(
                  'Abgeschlossene Einheiten',
                  style: CupertinoTheme.of(context)
                      .textTheme
                      .navLargeTitleTextStyle,
                ),
                const SizedBox(height: 6),
                Text(
                  'Der Verlauf zeigt die beim Abschluss gespeicherten Trainingsdaten.',
                  style: TextStyle(color: GainerTheme.secondaryText(context)),
                ),
                const SizedBox(height: 16),
                if (viewModel.history.isEmpty)
                  const _PlanningEmptyCard(
                    title: 'Noch kein Verlauf',
                    subtitle: 'Wenn du ein Training abschließt, findest du es hier wieder.',
                  ),
                for (final entry in viewModel.history)
                  _TrainingHistoryRow(entry: entry),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _TrainingHistoryRow extends StatelessWidget {
  const _TrainingHistoryRow({required this.entry});
  final TrainingHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final workout = entry.value;
    final sets = workout.exercises.fold<int>(
      0,
      (count, exercise) =>
          count + exercise.sets.where((set) => set.isCompleted).length,
    );
    return _PlanningRow(
      key: ValueKey('training-history-${entry.id}'),
      title: workout.templateNameSnapshot,
      subtitle:
          '${_dateLabel(workout.completedAtUtc)} · ${workout.exercises.length} Übungen · $sets Sätze',
      trailing: const Icon(CupertinoIcons.chevron_right, size: 18),
      onPressed: () => Navigator.of(context).push(
        CupertinoPageRoute<void>(
          builder: (_) => TrainingHistoryDetailScreen(entry: entry),
        ),
      ),
    );
  }
}

class TrainingHistoryDetailScreen extends StatelessWidget {
  const TrainingHistoryDetailScreen({required this.entry, super.key});
  final TrainingHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final workout = entry.value;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(workout.templateNameSnapshot),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          children: [
            Text(
              workout.templateNameSnapshot,
              style: CupertinoTheme.of(context)
                  .textTheme
                  .navLargeTitleTextStyle,
            ),
            const SizedBox(height: 4),
            Text(
              _dateLabel(workout.completedAtUtc),
              style: TextStyle(color: GainerTheme.secondaryText(context)),
            ),
            const SizedBox(height: 20),
            for (final exercise in workout.exercises)
              _HistoryExerciseCard(exercise: exercise),
          ],
        ),
      ),
    );
  }
}

class _HistoryExerciseCard extends StatelessWidget {
  const _HistoryExerciseCard({required this.exercise});
  final WorkoutExerciseRecord exercise;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
        context,
      ),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          exercise.exerciseNameSnapshot,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 3),
        Text(
          '${exercise.plannedSets} geplante Sätze · ${exercise.minimumRepetitions}–${exercise.maximumRepetitions} Wdh.',
          style: TextStyle(color: GainerTheme.secondaryText(context)),
        ),
        const SizedBox(height: 12),
        for (final set in exercise.sets.where((item) => item.isCompleted))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'Satz ${set.position + 1}: ${set.weightKg?.toStringAsFixed(1) ?? '–'} kg × ${set.repetitions ?? '–'} Wdh.'
              '${set.rir == null ? '' : ' · RIR ${set.rir}'}${set.notes == null || set.notes!.isEmpty ? '' : ' · ${set.notes}'}',
            ),
          ),
      ],
    ),
  );
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    super.key,
    required this.template,
    required this.isNext,
    required this.onEdit,
    required this.onStart,
    required this.onArchive,
  });
  final ({String id, TrainingTemplate value}) template;
  final bool isNext;
  final VoidCallback onEdit;
  final VoidCallback? onStart;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
        context,
      ),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                template.value.name,
                style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
              ),
            ),
            if (isNext) const _NextBadge(),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${template.value.items.length} Übungen',
          style: TextStyle(color: GainerTheme.secondaryText(context)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            CupertinoButton(
              key: ValueKey('training-template-edit-${template.id}'),
              minimumSize: const Size.square(48),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              onPressed: onEdit,
              child: const Text('Bearbeiten'),
            ),
            CupertinoButton(
              minimumSize: const Size.square(48),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              onPressed: onStart,
              child: const Text('Starten'),
            ),
            CupertinoButton(
              minimumSize: const Size.square(48),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              onPressed: onArchive,
              child: const Text('Archivieren'),
            ),
          ],
        ),
      ],
    ),
  );
}

class _RotationRow extends StatelessWidget {
  const _RotationRow({
    super.key,
    required this.position,
    required this.name,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onUp,
    required this.onDown,
    required this.onRemove,
  });
  final int position;
  final String name;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
    decoration: BoxDecoration(
      color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
        context,
      ),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$position. $name',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            _SmallAction(
              label: 'Nach oben',
              icon: CupertinoIcons.arrow_up,
              enabled: canMoveUp,
              onPressed: onUp,
            ),
            _SmallAction(
              label: 'Nach unten',
              icon: CupertinoIcons.arrow_down,
              enabled: canMoveDown,
              onPressed: onDown,
            ),
            _SmallAction(
              label: 'Entfernen',
              icon: CupertinoIcons.minus_circle,
              enabled: true,
              onPressed: onRemove,
            ),
          ],
        ),
      ],
    ),
  );
}

class TrainingExerciseSummary {
  const TrainingExerciseSummary({
    required this.id,
    required this.value,
    required this.isCustom,
  });
  final String id;
  final ExerciseValues value;
  final bool isCustom;
}

List<TrainingExerciseSummary> _exerciseSummaries(
  TrainingPlanningSnapshot? planning,
) => [
  for (final entry in planning?.exercises ?? const <ExerciseCatalogEntry>[])
    TrainingExerciseSummary(id: entry.id, value: entry, isCustom: false),
  for (final entry in planning?.customExercises ?? const [])
    if (!entry.isArchived)
      TrainingExerciseSummary(id: entry.id, value: entry.value, isCustom: true),
];

T? _firstOrNull<T>(Iterable<T> values) {
  final iterator = values.iterator;
  return iterator.moveNext() ? iterator.current : null;
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({
    super.key,
    required this.summary,
    this.onEdit,
    this.onArchive,
    this.onPressed,
  });
  final TrainingExerciseSummary summary;
  final VoidCallback? onEdit;
  final VoidCallback? onArchive;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 9),
    padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
    decoration: BoxDecoration(
      color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
        context,
      ),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CupertinoButton(
          minimumSize: const Size.square(48),
          padding: EdgeInsets.zero,
          onPressed: onPressed,
          child: Row(
            children: [
              Icon(
                CupertinoIcons.sportscourt,
                size: 19,
                color: CupertinoTheme.of(context).primaryColor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  summary.value.name,
                  style: TextStyle(
                    color: CupertinoColors.label.resolveFrom(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        Text(
          [
                summary.value.muscleGroup,
                summary.value.equipment,
                summary.isCustom ? _customExerciseLabel : 'Katalog',
              ]
              .whereType<String>()
              .where((item) => item.trim().isNotEmpty)
              .join(' · '),
          style: TextStyle(
            color: GainerTheme.secondaryText(context),
            fontSize: 13,
          ),
        ),
        if (onEdit != null || onArchive != null)
          Wrap(
            spacing: 4,
            children: [
              if (onEdit != null)
                CupertinoButton(
                  key: ValueKey('training-edit-exercise-${summary.id}'),
                  minimumSize: const Size.square(48),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  onPressed: onEdit,
                  child: const Text('Bearbeiten'),
                ),
              if (onArchive != null)
                CupertinoButton(
                  minimumSize: const Size.square(48),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  onPressed: onArchive,
                  child: const Text('Archivieren'),
                ),
            ],
          ),
      ],
    ),
  );
}

class _PlanningRow extends StatelessWidget {
  const _PlanningRow({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onPressed,
    this.muted = false,
  });
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onPressed;
  final bool muted;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
        context,
      ),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Expanded(
          child: CupertinoButton(
            minimumSize: const Size.square(52),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            onPressed: onPressed,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: CupertinoColors.label.resolveFrom(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(color: GainerTheme.secondaryText(context)),
                ),
              ],
            ),
          ),
        ),
        if (trailing != null)
          Padding(padding: const EdgeInsets.only(right: 12), child: trailing!),
      ],
    ),
  );
}

class _PlanningEmptyCard extends StatelessWidget {
  const _PlanningEmptyCard({
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
    padding: const EdgeInsets.all(16),
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
            color: GainerTheme.actionColor(context),
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

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onPressed,
  });
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: CupertinoButton(
      minimumSize: const Size.square(48),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: selected
          ? GainerTheme.actionColor(context)
          : CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
              context,
            ),
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(
          color: selected
              ? CupertinoColors.white
              : CupertinoColors.label.resolveFrom(context),
        ),
      ),
    ),
  );
}

class _SmallAction extends StatelessWidget {
  const _SmallAction({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    enabled: enabled,
    child: CupertinoButton(
      minimumSize: const Size.square(48),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      onPressed: enabled ? onPressed : null,
      child: Icon(icon, size: 18),
    ),
  );
}

class _NextBadge extends StatelessWidget {
  const _NextBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: GainerTheme.actionColor(context),
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Text(
      'Nächste',
      style: TextStyle(
        color: CupertinoColors.white,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _FormField extends StatelessWidget {
  const _FormField({
    super.key,
    required this.label,
    required this.controller,
    this.maxLines = 1,
  });
  final String label;
  final TextEditingController controller;
  final int maxLines;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 5),
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
        CupertinoTextField(
          key: key,
          controller: controller,
          minLines: maxLines,
          maxLines: maxLines,
          keyboardType: TextInputType.text,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
              context,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ],
    ),
  );
}

class _FormNotice extends StatelessWidget {
  const _FormNotice({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Text(
      message,
      style: TextStyle(color: CupertinoColors.systemRed.resolveFrom(context)),
    ),
  );
}

class _TemplateDraftCard extends StatelessWidget {
  const _TemplateDraftCard({
    super.key,
    required this.item,
    required this.position,
    required this.exerciseName,
    required this.onChooseExercise,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRemove,
  });
  final _TemplateDraft item;
  final int position;
  final String exerciseName;
  final VoidCallback? onChooseExercise;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
        context,
      ),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${position + 1}. $exerciseName',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Wrap(
          spacing: 2,
          runSpacing: 2,
          children: [
            CupertinoButton(
              minimumSize: const Size.square(48),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: onChooseExercise,
              child: const Text('Übung ändern'),
            ),
            _SmallAction(
              label: 'Nach oben',
              icon: CupertinoIcons.arrow_up,
              enabled: onMoveUp != null,
              onPressed: onMoveUp ?? () {},
            ),
            _SmallAction(
              label: 'Nach unten',
              icon: CupertinoIcons.arrow_down,
              enabled: onMoveDown != null,
              onPressed: onMoveDown ?? () {},
            ),
            _SmallAction(
              label: 'Entfernen',
              icon: CupertinoIcons.minus_circle,
              enabled: true,
              onPressed: onRemove,
            ),
          ],
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth < 300 ? 1 : 2;
            final width = columns == 1
                ? constraints.maxWidth
                : (constraints.maxWidth - 8) / 2;
            return Wrap(
              spacing: 8,
              runSpacing: 2,
              children: [
                _numberField(context, 'Sätze', item.sets, width, minLines: 1),
                _numberField(
                  context,
                  'Wdh. min.',
                  item.minimumRepetitions,
                  width,
                  minLines: 1,
                ),
                _numberField(
                  context,
                  'Wdh. max.',
                  item.maximumRepetitions,
                  width,
                  minLines: 1,
                ),
                _numberField(context, 'Ziel-RIR', item.targetRir, width),
                _numberField(context, 'Pause (s)', item.restSeconds, width),
                _numberField(
                  context,
                  'Notiz',
                  item.notes,
                  constraints.maxWidth,
                  numeric: false,
                ),
              ],
            );
          },
        ),
      ],
    ),
  );

  Widget _numberField(
    BuildContext context,
    String label,
    TextEditingController controller,
    double width, {
    bool numeric = true,
    int minLines = 1,
  }) => SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 5),
            child: Text(
              label,
              style: TextStyle(
                color: GainerTheme.secondaryText(context),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          CupertinoTextField(
            key: ValueKey('training-item-${_key(label)}-${item.id}'),
            controller: controller,
            minLines: minLines,
            maxLines: label == 'Notiz' ? 2 : 1,
            keyboardType: numeric
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: CupertinoColors.systemBackground.resolveFrom(context),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ],
      ),
    ),
  );

  String _key(String label) => switch (label) {
    'Sätze' => 'sets',
    'Wdh. min.' => 'min',
    'Wdh. max.' => 'max',
    'Ziel-RIR' => 'rir',
    'Pause (s)' => 'rest',
    _ => 'notes',
  };
}

class _TemplateDraft {
  _TemplateDraft({required this.id, required this.exerciseId});
  factory _TemplateDraft.fromRecord(TrainingTemplateItem item) =>
      _TemplateDraft(id: item.id, exerciseId: item.exerciseId)
        ..sets.text = item.plannedSets.toString()
        ..minimumRepetitions.text = item.minimumRepetitions.toString()
        ..maximumRepetitions.text = item.maximumRepetitions.toString()
        ..targetRir.text = item.targetRir?.toString() ?? ''
        ..restSeconds.text = item.restSeconds?.toString() ?? ''
        ..notes.text = item.notes ?? '';

  final String id;
  String exerciseId;
  final sets = TextEditingController(text: '3');
  final minimumRepetitions = TextEditingController(text: '8');
  final maximumRepetitions = TextEditingController(text: '12');
  final targetRir = TextEditingController(text: '2');
  final restSeconds = TextEditingController(text: '90');
  final notes = TextEditingController();

  TrainingTemplateItem toRecord() => TrainingTemplateItem(
    id: id,
    exerciseId: exerciseId,
    plannedSets: int.tryParse(sets.text) ?? 0,
    minimumRepetitions: int.tryParse(minimumRepetitions.text) ?? 0,
    maximumRepetitions: int.tryParse(maximumRepetitions.text) ?? 0,
    targetRir: _parseDecimalInput(targetRir.text),
    restSeconds: int.tryParse(restSeconds.text),
    notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
  );

  void dispose() {
    sets.dispose();
    minimumRepetitions.dispose();
    maximumRepetitions.dispose();
    targetRir.dispose();
    restSeconds.dispose();
    notes.dispose();
  }
}

String _dateLabel(String? value) {
  final date = value == null ? null : DateTime.tryParse(value)?.toLocal();
  if (date == null) return value ?? 'Abgeschlossen';
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
