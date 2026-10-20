import 'package:flutter/cupertino.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../../domain/models/training/exercise_catalog_model.dart';
import '../../../domain/models/training/muscle_suggestion.dart';
import '../../../domain/models/training/muscles.dart';
import '../../../domain/models/training/warmup.dart';
import '../../../domain/models/training/workout_input.dart';
import '../../../domain/models/training/workout_model.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'body_map.dart';
import 'exercise_catalog_format.dart';
import 'exercise_editor_view_model.dart';
import 'exercise_merge_sheet.dart';
import 'muscle_map_widgets.dart';
import 'muscle_picker_sheet.dart';
import 'warmup_steps_editor.dart';

/// Öffnet den Editor der Übung [exerciseId], z. B. aus dem Training oder der
/// Muskelübersicht. Liefert true, wenn etwas gespeichert wurde. Eine
/// unbekannte Übung öffnet nichts.
Future<bool> openExerciseEditorById(
  BuildContext context, {
  required TrainingLogRepository repository,
  required String exerciseId,
}) async {
  final exercises = await repository.readExercises(includeArchived: true);
  final exercise = exercises.where((item) => item.id == exerciseId).firstOrNull;
  if (exercise == null || !context.mounted) return false;
  final changed = await Navigator.of(context).push<bool>(
    CupertinoPageRoute<bool>(
      builder: (_) =>
          ExerciseEditorScreen(repository: repository, exercise: exercise),
    ),
  );
  return changed == true;
}

/// Editor für eigene Übungen. Basis- und archivierte Übungen werden nur gelesen.
/// Liefert true, wenn etwas gespeichert, archiviert oder zusammengeführt wurde.
class ExerciseEditorScreen extends StatefulWidget {
  const ExerciseEditorScreen({
    required this.repository,
    this.exercise,
    super.key,
  });

  final TrainingLogRepository repository;

  /// Übung zum Bearbeiten oder Anzeigen; null legt eine neue eigene Übung an.
  final CatalogExercise? exercise;

  @override
  State<ExerciseEditorScreen> createState() => _ExerciseEditorScreenState();
}

class _ExerciseEditorScreenState extends State<ExerciseEditorScreen> {
  late final ExerciseEditorViewModel _viewModel = ExerciseEditorViewModel(
    repository: widget.repository,
    exercise: widget.exercise,
  );
  late final TextEditingController _nameController;
  late final TextEditingController _notesController;
  late final TextEditingController _bodyweightController;
  late final TextEditingController _weightController;
  late ExerciseKind _kind;
  late Set<String> _categoryIds;
  late List<Muscle> _primaryMuscles;
  late List<Muscle> _secondaryMuscles;

  @override
  void initState() {
    super.initState();
    final exercise = widget.exercise;
    _nameController = TextEditingController(text: exercise?.name ?? '');
    _notesController = TextEditingController(text: exercise?.notes ?? '');
    _bodyweightController = TextEditingController(
      text: exercise?.bodyweightFactor == null
          ? ''
          : formatBodyweightPercent(exercise!.bodyweightFactor!),
    );
    _weightController = TextEditingController(
      text: exercise?.weightFactor == null
          ? ''
          : formatWeightFactor(exercise!.weightFactor!),
    );
    _kind = exercise?.exerciseType ?? ExerciseKind.strength;
    _categoryIds = {...?exercise?.categoryIds};
    _nameController.addListener(_nameChanged);
    _primaryMuscles = [...?exercise?.primaryMuscles];
    _secondaryMuscles = [...?exercise?.secondaryMuscles];
    WidgetsBinding.instance.addPostFrameCallback((_) => _viewModel.load());
  }

  /// Der Muskel-Vorschlag folgt dem Namen.
  void _nameChanged() {
    if (_primaryMuscles.isEmpty && _secondaryMuscles.isEmpty) setState(() {});
  }

  @override
  void dispose() {
    _viewModel.dispose();
    _nameController.dispose();
    _notesController.dispose();
    _bodyweightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  ExerciseEditorInput _input() => ExerciseEditorInput(
    name: _nameController.text,
    kind: _kind,
    categoryIds: [
      for (final category in _viewModel.categories)
        if (_categoryIds.contains(category.id)) category.id,
    ],
    notes: _notesController.text,
    bodyweightPercent: _bodyweightController.text,
    weightFactor: _weightController.text,
    primaryMuscles: _primaryMuscles,
    secondaryMuscles: _secondaryMuscles,
  );

  Future<void> _save() async {
    if (_viewModel.needsTypeChangeConfirmation(_kind)) {
      final confirmed = await showGainerStackedDialog<bool>(
        context: context,
        title: 'Übungstyp ändern?',
        message: 'Bestehende Sätze werden nach dem neuen Typ ausgewertet.',
        actions: const [
          GainerDialogAction(label: 'Ändern', value: true),
          GainerDialogAction(label: 'Abbrechen', value: false),
        ],
      );
      if (confirmed != true || !mounted) return;
    }
    final saved = await _viewModel.save(_input());
    if (saved && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _archive() async {
    final confirmed = await showGainerStackedDialog<bool>(
      context: context,
      title: 'Übung archivieren?',
      message:
          '„${_nameController.text.trim()}“ wird für neue Trainings nicht mehr angeboten. Historie, Pläne und Statistiken bleiben erhalten.',
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
    final archived = await _viewModel.archive();
    if (archived && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _merge() async {
    final source = widget.exercise;
    if (source == null) return;
    final merged = await showExerciseMergeSheet(
      context,
      repository: widget.repository,
      source: source,
    );
    if (merged && mounted) Navigator.of(context).pop(true);
  }

  /// Abschnitt „Aufwärmen“: Standard, eigene Stufen oder aus, dazu die Rundung.
  /// Wirkt lokal und sofort; nur für bestehende Übungen.
  List<Widget> _warmupSection(BuildContext context) {
    if (_viewModel.isNew) return const [];
    final colors = GainerDesign.colorsOf(context);
    final override = _viewModel.warmupOverride;
    final unit = _viewModel.settings.weightUnit;
    final global = _viewModel.settings.warmup;
    final mode = override?.enabled == false
        ? _WarmupMode.off
        : override?.steps != null
        ? _WarmupMode.custom
        : _WarmupMode.standard;
    final rounding = resolveWarmup(global, override, unit).rounding;
    return [
      _Section(
        header: 'Aufwärmen',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GainerSegmentedControl<_WarmupMode>(
              options: const {
                _WarmupMode.standard: 'Standard',
                _WarmupMode.custom: 'Eigene Stufen',
                _WarmupMode.off: 'Aus',
              },
              value: mode,
              onChanged: _setWarmupMode,
            ),
            if (mode == _WarmupMode.custom) ...[
              const SizedBox(height: GainerSpacing.s),
              WarmupStepsEditor(
                initialSteps: override?.steps ?? global.steps,
                onChanged: (steps) => _viewModel.updateWarmupOverride(
                  (current) => current.copyWith(steps: () => steps),
                ),
              ),
            ],
            if (mode != _WarmupMode.off) ...[
              const SizedBox(height: GainerSpacing.xs),
              GainerGroupedSection(
                children: [
                  GainerListRow(
                    key: const ValueKey('warmup-rounding'),
                    title: 'Rundung',
                    value:
                        '${formatWeight(unit.toKg(rounding), unit)} ${unit.label}',
                    showChevron: true,
                    onTap: () => _pickRounding(unit),
                  ),
                ],
              ),
            ],
            Padding(
              padding: const EdgeInsets.only(
                top: GainerSpacing.xs,
                left: GainerSpacing.m,
              ),
              child: Text(
                'Standard nutzt die Einstellung „Aufwärmhinweis“ im Trainingsmenü.',
                style: GainerTypography.caption.copyWith(
                  color: colors.secondaryText,
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Future<void> _setWarmupMode(_WarmupMode mode) {
    final global = _viewModel.settings.warmup;
    return _viewModel.updateWarmupOverride(
      (current) => switch (mode) {
        _WarmupMode.standard => current.copyWith(
          enabled: () => null,
          steps: () => null,
        ),
        _WarmupMode.custom => current.copyWith(
          enabled: () => null,
          steps: () => current.steps ?? global.steps,
        ),
        _WarmupMode.off => current.copyWith(enabled: () => false),
      },
    );
  }

  Future<void> _pickRounding(WeightUnit unit) async {
    final options = warmupRoundingOptions(unit);
    final picked = await showGainerActionSheet<double>(
      context: context,
      title: 'Rundung',
      groups: [
        [
          for (final option in options)
            GainerSheetAction(
              label:
                  '${formatWeight(unit.toKg(option), unit)} ${unit.label}'
                  '${option == defaultWarmupRounding(unit) ? ' (Standard)' : ''}',
              icon: CupertinoIcons.arrow_up_arrow_down,
              value: option,
            ),
        ],
      ],
    );
    if (picked == null) return;
    await _viewModel.updateWarmupOverride(
      (current) => current.copyWith(
        rounding: () => picked == defaultWarmupRounding(unit) ? null : picked,
      ),
    );
  }

  /// Abschnitt „Muskeln“: Karte mit Haupt- (voll) und Hilfsmuskeln (halb).
  /// Im Formular schaltet ein Tipp auf die Karte Haupt → Hilfs → keiner.
  Widget _muscleSection(BuildContext context, {required bool editable}) {
    final colors = GainerDesign.colorsOf(context);
    String names(List<Muscle> muscles) => muscles.isEmpty
        ? 'Keine'
        : muscles.map((muscle) => muscle.label).join(', ');
    return _Section(
      header: 'Muskeln',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (editable) ..._suggestion(colors),
          GainerCard(
            child: Center(
              child: SizedBox(
                height: 200,
                child: BodyMap(
                  key: const ValueKey('exercise-muscle-map'),
                  fills: roleFills(_primaryMuscles, _secondaryMuscles, colors),
                  onMuscleTap: editable ? _cycleMuscle : null,
                  semanticLabel:
                      'Hauptmuskeln: ${names(_primaryMuscles)}. '
                      'Hilfsmuskeln: ${names(_secondaryMuscles)}.',
                ),
              ),
            ),
          ),
          const SizedBox(height: GainerSpacing.xs),
          GainerGroupedSection(
            footer: editable
                ? 'Tippe auf die Karte: einmal Hauptmuskel, zweimal Hilfsmuskel, '
                      'dreimal entfernen. Hilfsmuskeln zählen einen halben Satz.'
                : null,
            children: [
              GainerListRow(
                key: const ValueKey('exercise-primary-muscles'),
                title: 'Hauptmuskeln',
                value: names(_primaryMuscles),
                showChevron: editable,
                onTap: editable ? () => _pickMuscles(primary: true) : null,
              ),
              GainerListRow(
                key: const ValueKey('exercise-secondary-muscles'),
                title: 'Hilfsmuskeln',
                value: names(_secondaryMuscles),
                showChevron: editable,
                onTap: editable ? () => _pickMuscles(primary: false) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Vorschlag aus dem Katalog, solange noch keine Muskeln gewählt sind.
  List<Widget> _suggestion(GainerColors colors) {
    if (_primaryMuscles.isNotEmpty || _secondaryMuscles.isNotEmpty) {
      return const [];
    }
    final source = suggestMuscleSource(
      _nameController.text,
      _viewModel.suggestionSources,
    );
    if (source == null) return const [];
    final muscles = [
      ...source.primaryMuscles,
      ...source.secondaryMuscles,
    ].map((muscle) => muscle.label).join(', ');
    return [
      GainerCard(
        key: const ValueKey('exercise-muscle-suggestion'),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Vorschlag: wie „${source.name}“',
                    style: GainerTypography.body.copyWith(
                      color: colors.primaryText,
                    ),
                  ),
                  const SizedBox(height: GainerSpacing.xxs),
                  Text(
                    muscles,
                    style: GainerTypography.caption.copyWith(
                      color: colors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: GainerSpacing.xs),
            GainerPillButton(
              key: const ValueKey('exercise-muscle-suggestion-apply'),
              label: 'Übernehmen',
              variant: GainerPillVariant.tonal,
              onPressed: () => setState(() {
                _primaryMuscles = [...source.primaryMuscles];
                _secondaryMuscles = [...source.secondaryMuscles];
              }),
            ),
          ],
        ),
      ),
      const SizedBox(height: GainerSpacing.xs),
    ];
  }

  void _cycleMuscle(Muscle muscle) {
    setState(() {
      if (_primaryMuscles.remove(muscle)) {
        if (_secondaryMuscles.length < maxSecondaryMuscles) {
          _secondaryMuscles.add(muscle);
        }
      } else if (!_secondaryMuscles.remove(muscle)) {
        if (_primaryMuscles.length < maxPrimaryMuscles) {
          _primaryMuscles.add(muscle);
        } else if (_secondaryMuscles.length < maxSecondaryMuscles) {
          _secondaryMuscles.add(muscle);
        }
      }
    });
  }

  Future<void> _pickMuscles({required bool primary}) async {
    final picked = await showMusclePickerSheet(
      context,
      title: primary ? 'Hauptmuskeln' : 'Hilfsmuskeln',
      selected: primary ? _primaryMuscles : _secondaryMuscles,
      maximum: primary ? maxPrimaryMuscles : maxSecondaryMuscles,
      locked: {
        for (final muscle in primary ? _secondaryMuscles : _primaryMuscles)
          muscle: primary ? 'Hilfsmuskel' : 'Hauptmuskel',
      },
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (primary) {
        _primaryMuscles = picked;
      } else {
        _secondaryMuscles = picked;
      }
    });
  }

  void _toggleCategory(String id) {
    setState(() {
      if (!_categoryIds.remove(id)) _categoryIds.add(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final exercise = widget.exercise;
        return GainerScaffold(
          title: exercise?.name ?? 'Neue Übung',
          trailing: [
            if (!_viewModel.readOnly)
              GainerPillButton(
                key: const ValueKey('exercise-save'),
                label: 'Speichern',
                isLoading: _viewModel.isSaving,
                onPressed: _viewModel.isSaving ? null : _save,
              ),
          ],
          children: [
            if (_viewModel.readOnly)
              ..._readOnlyChildren(context)
            else
              ..._formChildren(context),
            const SizedBox(height: GainerSpacing.l),
          ],
        );
      },
    );
  }

  List<Widget> _formChildren(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final errors = _viewModel.fieldErrors;
    return [
      if (_viewModel.errorMessage != null) _ErrorText(_viewModel.errorMessage!),
      _Section(
        header: 'Name',
        child: _textField(
          fieldKey: const ValueKey('exercise-name'),
          controller: _nameController,
          placeholder: 'Name der Übung',
          error: errors['name'],
        ),
      ),
      GainerGroupedSection(
        header: 'Typ',
        children: [
          for (final kind in ExerciseKind.values)
            GainerListRow(
              key: ValueKey('exercise-kind-${kind.name}'),
              title: catalogKindLabel(kind),
              trailing: kind == _kind ? _checkmark(colors) : null,
              onTap: () => setState(() => _kind = kind),
            ),
        ],
      ),
      if (_viewModel.isUsed)
        Padding(
          padding: const EdgeInsets.only(
            top: GainerSpacing.xs,
            left: GainerSpacing.m,
          ),
          child: Text(
            'Die Übung wurde bereits verwendet. Ein Typwechsel wird vor dem Speichern bestätigt.',
            style: GainerTypography.caption.copyWith(
              color: colors.secondaryText,
            ),
          ),
        ),
      _Section(
        header: 'Kategorien',
        child: _categoryList(colors, errors['categoryIds']),
      ),
      _Section(
        header: 'Faktoren',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _textField(
              fieldKey: const ValueKey('exercise-bodyweight'),
              controller: _bodyweightController,
              placeholder: 'Körpergewicht in % (leer = Standard)',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              error: errors['bodyweightFactor'],
            ),
            const SizedBox(height: GainerSpacing.xs),
            _textField(
              fieldKey: const ValueKey('exercise-weight-factor'),
              controller: _weightController,
              placeholder: 'Zusatzgewicht-Faktor (leer = 1)',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              error: errors['weightFactor'],
            ),
          ],
        ),
      ),
      _Section(
        header: 'Notiz',
        child: _textField(
          fieldKey: const ValueKey('exercise-notes'),
          controller: _notesController,
          placeholder: 'Notiz zur Übung',
          maxLines: 4,
          error: errors['notes'],
        ),
      ),
      _muscleSection(context, editable: true),
      if (errors['primaryMuscles'] case final error?) _ErrorText(error),
      ..._warmupSection(context),
      if (!_viewModel.isNew) ...[
        const SizedBox(height: GainerSpacing.m),
        GainerPillButton(
          key: const ValueKey('exercise-merge'),
          label: 'Mit anderer Übung zusammenführen',
          variant: GainerPillVariant.tonal,
          expand: true,
          onPressed: _merge,
        ),
        const SizedBox(height: GainerSpacing.xs),
        GainerPillButton(
          key: const ValueKey('exercise-archive'),
          label: 'Archivieren',
          variant: GainerPillVariant.destructive,
          expand: true,
          onPressed: _archive,
        ),
      ],
    ];
  }

  Widget _categoryList(GainerColors colors, String? error) {
    final categories = _viewModel.categories;
    if (categories.isEmpty) {
      return Text(
        'Noch keine Kategorien. Lege sie unter „Kategorien verwalten“ an.',
        style: GainerTypography.body.copyWith(color: colors.secondaryText),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GainerCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final category in categories)
                GainerListRow(
                  key: ValueKey('exercise-category-${category.id}'),
                  title: category.name,
                  trailing: _categoryIds.contains(category.id)
                      ? _checkmark(colors)
                      : null,
                  onTap: () => _toggleCategory(category.id),
                ),
            ],
          ),
        ),
        if (error != null) _ErrorText(error),
      ],
    );
  }

  List<Widget> _readOnlyChildren(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final exercise = widget.exercise!;
    final names = [
      for (final category in _viewModel.categories)
        if (exercise.categoryIds.contains(category.id)) category.name,
    ];
    final bodyweight = exercise.bodyweightFactor;
    final weight = exercise.weightFactor;
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: GainerSpacing.s),
        child: Text(
          exercise.isBase
              ? 'Basisübung. Sie ist schreibgeschützt.'
              : 'Archiviert. Sie wird nicht mehr zur Auswahl angeboten.',
          style: GainerTypography.body.copyWith(color: colors.secondaryText),
        ),
      ),
      GainerGroupedSection(
        header: 'Übung',
        children: [
          GainerListRow(title: 'Name', value: exercise.name),
          GainerListRow(
            title: 'Typ',
            value: catalogKindLabel(exercise.exerciseType),
          ),
          GainerListRow(
            title: 'Kategorien',
            value: names.isEmpty ? 'Keine' : names.join(', '),
          ),
          if (exercise.equipment case final equipment?)
            GainerListRow(title: 'Equipment', value: equipment),
          GainerListRow(
            title: 'Körpergewichtsfaktor',
            value: bodyweight == null
                ? 'Standard'
                : '${formatBodyweightPercent(bodyweight)} %',
          ),
          GainerListRow(
            title: 'Zusatzgewichtsfaktor',
            value: weight == null ? 'Standard' : formatWeightFactor(weight),
          ),
          if (exercise.notes case final notes?)
            GainerListRow(title: 'Notiz', value: notes),
        ],
      ),
      const SizedBox(height: GainerSpacing.m),
      if (exercise.description case final description?)
        _Section(
          header: 'Anleitung',
          child: GainerCard(
            key: const ValueKey('exercise-description'),
            child: Text(
              description,
              style: GainerTypography.body.copyWith(color: colors.primaryText),
            ),
          ),
        ),
      _muscleSection(context, editable: false),
      ..._warmupSection(context),
    ];
  }

  Widget _textField({
    required Key fieldKey,
    required TextEditingController controller,
    required String placeholder,
    String? error,
    int? maxLines = 1,
    TextInputType? keyboardType,
  }) {
    final colors = GainerDesign.colorsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CupertinoTextField(
          key: fieldKey,
          controller: controller,
          placeholder: placeholder,
          maxLines: maxLines,
          keyboardType: keyboardType,
          placeholderStyle: GainerTypography.body.copyWith(
            color: colors.placeholderText,
          ),
          style: GainerTypography.body.copyWith(color: colors.primaryText),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
          decoration: BoxDecoration(
            color: colors.elevatedSurface,
            borderRadius: BorderRadius.circular(GainerRadii.field),
          ),
        ),
        if (error != null) _ErrorText(error),
      ],
    );
  }

  Widget _checkmark(GainerColors colors) =>
      Icon(CupertinoIcons.checkmark, color: colors.accent, size: 20);
}

enum _WarmupMode { standard, custom, off }

class _Section extends StatelessWidget {
  const _Section({required this.header, required this.child});

  final String header;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: GainerSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              GainerSpacing.m,
              0,
              GainerSpacing.m,
              GainerSpacing.xs,
            ),
            child: Text(
              header,
              style: GainerTypography.label.copyWith(
                color: colors.secondaryText,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: GainerSpacing.xs),
      child: Text(
        message,
        style: GainerTypography.caption.copyWith(
          color: GainerDesign.colorsOf(context).destructive,
        ),
      ),
    );
  }
}
