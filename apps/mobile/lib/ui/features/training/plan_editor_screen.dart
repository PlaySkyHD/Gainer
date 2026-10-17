import 'package:flutter/cupertino.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../../domain/models/training/exercise_catalog_model.dart';
import '../../../domain/models/training/training_plan_model.dart';
import '../../../domain/models/training/workout_model.dart';
import '../../../domain/models/training/workout_validation.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'active_workout_controller.dart';
import 'exercise_picker_sheet.dart';
import 'plan_entry_editor_sheet.dart';
import 'plan_start.dart';
import 'training_plans_view_model.dart';

/// Planeditor. Ohne [planId] entsteht ein neuer Plan; die ID ist ab dem Öffnen stabil.
class PlanEditorScreen extends StatefulWidget {
  const PlanEditorScreen({
    required this.repository,
    required this.activeWorkout,
    this.planId,
    super.key,
  });

  final TrainingLogRepository repository;
  final ActiveWorkoutController activeWorkout;
  final String? planId;

  @override
  State<PlanEditorScreen> createState() => _PlanEditorScreenState();
}

enum _LeaveChoice { save, discard, cancel }

class _PlanEditorScreenState extends State<PlanEditorScreen> {
  final _nameController = TextEditingController();
  final _notesController = TextEditingController();
  late final String _planId = widget.planId ?? widget.repository.newId();
  final Map<String, CatalogExercise> _exercises = {};

  /// Zuletzt gespeicherter Stand; null, solange der Plan noch nicht angelegt ist.
  TrainingPlanModel? _persisted;
  List<PlanEntry> _entries = const [];
  PreviousValueSource _source = PreviousValueSource.exercise;
  Map<String, String> _errors = const {};
  String? _saveError;
  String? _loadError;
  bool _loading = true;
  bool _savedNotice = false;

  @override
  void initState() {
    super.initState();
    if (widget.planId == null) {
      _loading = false;
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final plan = await widget.repository.readPlan(_planId);
      final exercises = await widget.repository.readExercises(
        includeArchived: true,
      );
      if (!mounted) return;
      setState(() {
        _exercises
          ..clear()
          ..addAll({for (final exercise in exercises) exercise.id: exercise});
        if (plan == null) {
          _loadError = 'Der Plan ist nicht verfügbar.';
        } else {
          _applyPlan(plan);
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Der Plan konnte nicht geladen werden.';
        _loading = false;
      });
    }
  }

  void _applyPlan(TrainingPlanModel plan) {
    _persisted = plan;
    _nameController.text = plan.name;
    _notesController.text = plan.notes ?? '';
    _source = plan.previousValueSource;
    _entries = List.of(plan.entries);
  }

  TrainingPlanModel _draft() {
    final notes = _notesController.text.trim();
    return TrainingPlanModel(
      planId: _planId,
      name: _nameController.text.trim(),
      notes: notes.isEmpty ? null : notes,
      previousValueSource: _source,
      entries: _entries,
      sortOrder: _persisted?.sortOrder ?? 0,
    );
  }

  TrainingPlanModel get _baseline =>
      _persisted ??
      TrainingPlanModel(
        planId: _planId,
        name: '',
        previousValueSource: PreviousValueSource.exercise,
      );

  bool get _dirty => _draft() != _baseline;

  /// Jede Änderung blendet alte Fehler und Hinweise aus.
  void _changed(VoidCallback change) {
    setState(() {
      change();
      _errors = const {};
      _saveError = null;
      _savedNotice = false;
    });
  }

  Future<bool> _save() async {
    final draft = _draft();
    try {
      validateTrainingPlan(draft);
    } on WorkoutValidationException catch (error) {
      setState(() {
        _errors = error.fields;
        _saveError = null;
      });
      return false;
    }
    try {
      final saved = _persisted == null
          ? await widget.repository.createPlan(draft)
          : await widget.repository.updatePlan(draft);
      if (!mounted) return false;
      setState(() {
        _persisted = saved;
        _errors = const {};
        _saveError = null;
        _savedNotice = true;
      });
      return true;
    } on WorkoutValidationException catch (error) {
      if (!mounted) return false;
      setState(() => _errors = error.fields);
      return false;
    } catch (error) {
      if (!mounted) return false;
      setState(() {
        _saveError = planErrorMessage(
          error,
          'Der Plan konnte nicht gespeichert werden. Der vorherige Stand bleibt erhalten.',
        );
      });
      return false;
    }
  }

  Future<void> _addExercise() async {
    final result = await showExercisePicker(
      context,
      repository: widget.repository,
    );
    if (result == null || !mounted) return;
    final supersetId = result.asSuperset ? widget.repository.newId() : null;
    _changed(() {
      for (final exercise in result.exercises) {
        _exercises[exercise.id] = exercise;
        _entries = [
          ..._entries,
          PlanEntry(
            entryId: widget.repository.newId(),
            exerciseId: exercise.id,
            supersetId: supersetId,
          ),
        ];
      }
    });
  }

  Future<void> _editEntry(int index) async {
    final entry = _entries[index];
    final edit = await showPlanEntryEditor(
      context,
      entry: entry,
      exerciseName: _nameOf(entry.exerciseId),
    );
    if (edit == null || !mounted) return;
    _changed(() {
      final supersetId = entry.supersetId;
      final updated = edit.entry;
      if (updated == null) {
        _entries = [..._entries]..removeAt(index);
        return;
      }
      _entries = [
        for (var i = 0; i < _entries.length; i++)
          if (i == index)
            edit.unlinkSuperset && supersetId != null
                ? updated.copyWith(supersetId: () => null)
                : updated
          else if (edit.unlinkSuperset &&
              supersetId != null &&
              _entries[i].supersetId == supersetId)
            _entries[i].copyWith(supersetId: () => null)
          else
            _entries[i],
      ];
    });
  }

  Future<void> _startPlan() async {
    await startPlanWorkout(
      context,
      repository: widget.repository,
      activeWorkout: widget.activeWorkout,
      planId: _planId,
    );
    if (mounted) await widget.activeWorkout.load();
  }

  Future<void> _requestLeave() async {
    final choice = await showGainerStackedDialog<_LeaveChoice>(
      context: context,
      title: 'Ungespeicherte Änderungen',
      message: 'Willst du den Plan speichern, bevor du ihn verlässt?',
      actions: const [
        GainerDialogAction(label: 'Speichern', value: _LeaveChoice.save),
        GainerDialogAction(
          label: 'Verwerfen',
          value: _LeaveChoice.discard,
          destructive: true,
        ),
        GainerDialogAction(label: 'Abbrechen', value: _LeaveChoice.cancel),
      ],
    );
    if (!mounted) return;
    switch (choice) {
      case _LeaveChoice.save:
        if (await _save() && mounted) Navigator.of(context).pop();
      case _LeaveChoice.discard:
        Navigator.of(context).pop();
      case _LeaveChoice.cancel:
      case null:
        break;
    }
  }

  String _nameOf(String exerciseId) =>
      _exercises[exerciseId]?.name ?? 'Unbekannte Übung';

  /// Buchstabe der Superset-Gruppe, zu der der Eintrag gehört.
  String? _supersetLetter(int index) {
    final supersetId = _entries[index].supersetId;
    if (supersetId == null) return null;
    var position = 0;
    for (
      var i = index - 1;
      i >= 0 && _entries[i].supersetId == supersetId;
      i--
    ) {
      position++;
    }
    return String.fromCharCode(
      'A'.codeUnitAt(0) + (position < 25 ? position : 25),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = _nameController.text.trim();
    final canStart = _persisted != null && !_dirty;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestLeave();
      },
      child: GainerScaffold(
        title: name.isEmpty ? 'Neuer Plan' : name,
        trailing: [
          GainerPillButton(
            label: 'Speichern',
            onPressed: _dirty || _persisted == null ? _save : null,
          ),
        ],
        children: _loading
            ? const [Center(child: CupertinoActivityIndicator())]
            : _loadError != null
            ? [_buildMessage(_loadError!)]
            : [
                _buildStartCard(canStart),
                const SizedBox(height: GainerSpacing.m),
                _buildDetailsCard(),
                const SizedBox(height: GainerSpacing.m),
                ..._buildEntries(),
                const SizedBox(height: GainerSpacing.s),
                GainerPillButton(
                  label: '+ Übung hinzufügen',
                  variant: GainerPillVariant.tonal,
                  expand: true,
                  onPressed: _addExercise,
                ),
                if (_saveError != null || _errors['entries'] != null) ...[
                  const SizedBox(height: GainerSpacing.m),
                  _buildError(_saveError ?? _errors['entries']!),
                ],
                if (_savedNotice) ...[
                  const SizedBox(height: GainerSpacing.m),
                  _buildNotice('Gespeichert.'),
                ],
              ],
      ),
    );
  }

  Widget _buildStartCard(bool canStart) {
    final colors = GainerDesign.colorsOf(context);
    final hint = canStart
        ? 'Startet ein Training mit diesem Plan.'
        : 'Speichere den Plan, um ein Training zu beginnen.';
    return GainerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Training beginnen',
            style: GainerTypography.cardTitle.copyWith(
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: GainerSpacing.xxs),
          Text(
            hint,
            style: GainerTypography.caption.copyWith(
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: GainerSpacing.s),
          GainerPillButton(
            key: const ValueKey('plan-editor-start'),
            label: 'Training beginnen',
            icon: CupertinoIcons.play_fill,
            expand: true,
            onPressed: canStart ? _startPlan : null,
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsCard() {
    final colors = GainerDesign.colorsOf(context);
    return GainerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _fieldLabel('Name'),
          CupertinoTextField(
            key: const ValueKey('plan-name-field'),
            controller: _nameController,
            placeholder: 'z. B. Push',
            placeholderStyle: GainerTypography.body.copyWith(
              color: colors.placeholderText,
            ),
            style: GainerTypography.body.copyWith(color: colors.primaryText),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(GainerRadii.field),
            ),
            onChanged: (_) => _changed(() {}),
          ),
          if (_errors['name'] != null) _fieldError(_errors['name']!),
          const SizedBox(height: GainerSpacing.m),
          _fieldLabel('Vorwerte'),
          GainerSegmentedControl<PreviousValueSource>(
            options: const {
              PreviousValueSource.exercise: 'Aktuellste',
              PreviousValueSource.plan: 'Trainingsplan',
            },
            value: _source == PreviousValueSource.plan
                ? PreviousValueSource.plan
                : PreviousValueSource.exercise,
            onChanged: (source) => _changed(() => _source = source),
          ),
          const SizedBox(height: GainerSpacing.xs),
          Text(
            'Aktuellste: Vorwerte jeder Übung aus dem letzten Training. '
            'Trainingsplan: Vorwerte aus diesem Plan.',
            style: GainerTypography.caption.copyWith(
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: GainerSpacing.m),
          _fieldLabel('Notizen'),
          CupertinoTextField(
            key: const ValueKey('plan-notes-field'),
            controller: _notesController,
            placeholder: 'Notizen zum Plan',
            placeholderStyle: GainerTypography.body.copyWith(
              color: colors.placeholderText,
            ),
            style: GainerTypography.body.copyWith(color: colors.primaryText),
            minLines: 2,
            maxLines: 5,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(GainerRadii.field),
            ),
            onChanged: (_) => _changed(() {}),
          ),
          if (_errors['notes'] != null) _fieldError(_errors['notes']!),
        ],
      ),
    );
  }

  List<Widget> _buildEntries() {
    final colors = GainerDesign.colorsOf(context);
    if (_entries.isEmpty) {
      return [
        GainerCard(
          child: Text(
            'Noch keine Übungen. Füge die erste Übung hinzu.',
            textAlign: TextAlign.center,
            style: GainerTypography.body.copyWith(color: colors.secondaryText),
          ),
        ),
      ];
    }
    return [
      for (var index = 0; index < _entries.length; index++)
        Padding(
          padding: const EdgeInsets.only(bottom: GainerSpacing.xs),
          child: _buildEntryCard(index, colors),
        ),
    ];
  }

  Widget _buildEntryCard(int index, GainerColors colors) {
    final entry = _entries[index];
    final letter = _supersetLetter(index);
    final entryErrors = [
      _errors['entries[$index].workingSets'],
      _errors['entries[$index].warmupSets'],
      _errors['entries[$index].notes'],
    ].whereType<String>();
    final setCount = entry.warmupSets + entry.workingSets;
    final details = [
      '$setCount Sätze',
      if (entry.warmupSets > 0) '${entry.warmupSets} Aufwärmsätze',
    ].join(' · ');
    return GainerCard(
      child: GestureDetector(
        key: ValueKey('plan-entry-$index'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _editEntry(index),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _nameOf(entry.exerciseId),
                    style: GainerTypography.cardTitle.copyWith(
                      color: colors.primaryText,
                    ),
                  ),
                ),
                if (letter != null) ...[
                  _SupersetBadge(letter: letter),
                  const SizedBox(width: GainerSpacing.xs),
                ],
                Icon(
                  CupertinoIcons.chevron_forward,
                  size: 18,
                  color: colors.secondaryText,
                ),
              ],
            ),
            const SizedBox(height: GainerSpacing.xxs),
            Text(
              details,
              style: GainerTypography.caption.copyWith(
                color: colors.secondaryText,
              ),
            ),
            if (entry.notes != null) ...[
              const SizedBox(height: GainerSpacing.xxs),
              Text(
                entry.notes!,
                style: GainerTypography.caption.copyWith(
                  color: colors.secondaryText,
                ),
              ),
            ],
            for (final message in entryErrors) _fieldError(message),
          ],
        ),
      ),
    );
  }

  Widget _buildMessage(String text) {
    final colors = GainerDesign.colorsOf(context);
    return GainerCard(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: GainerTypography.body.copyWith(color: colors.secondaryText),
      ),
    );
  }

  Widget _buildError(String text) {
    final colors = GainerDesign.colorsOf(context);
    return Text(
      text,
      style: GainerTypography.caption.copyWith(color: colors.destructive),
    );
  }

  Widget _buildNotice(String text) {
    final colors = GainerDesign.colorsOf(context);
    return Text(
      text,
      style: GainerTypography.caption.copyWith(color: colors.secondaryText),
    );
  }

  Widget _fieldLabel(String text) {
    final colors = GainerDesign.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: GainerSpacing.xs),
      child: Text(
        text,
        style: GainerTypography.label.copyWith(color: colors.secondaryText),
      ),
    );
  }

  Widget _fieldError(String text) {
    final colors = GainerDesign.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.only(top: GainerSpacing.xxs),
      child: Text(
        text,
        style: GainerTypography.caption.copyWith(color: colors.destructive),
      ),
    );
  }
}

class _SupersetBadge extends StatelessWidget {
  const _SupersetBadge({required this.letter});

  final String letter;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: colors.accent, shape: BoxShape.circle),
      child: Text(
        letter,
        style: GainerTypography.label.copyWith(color: colors.onAccent),
      ),
    );
  }
}
