import 'package:flutter/cupertino.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../../domain/models/training/exercise_catalog_model.dart';
import '../../../domain/models/training/workout_model.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'exercise_catalog_format.dart';
import 'exercise_editor_view_model.dart';
import 'exercise_merge_sheet.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _viewModel.load());
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
