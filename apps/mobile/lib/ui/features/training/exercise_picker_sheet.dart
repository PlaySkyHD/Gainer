import 'package:flutter/cupertino.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../../domain/models/training/exercise_catalog_model.dart';
import '../../../domain/models/training/workout_model.dart';
import '../../../domain/models/training/workout_validation.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';

/// Ergebnis der Übungsauswahl. Im Normalmodus liefert sie genau eine Übung,
/// im Supersatz-Modus mehrere in gewählter Reihenfolge.
class ExercisePickerResult {
  const ExercisePickerResult({
    required this.exercises,
    required this.asSuperset,
  });

  final List<CatalogExercise> exercises;
  final bool asSuperset;
}

/// Zeigt die Übungsauswahl als Sheet. Liefert null, wenn ohne Auswahl geschlossen wird.
Future<ExercisePickerResult?> showExercisePicker(
  BuildContext context, {
  required TrainingLogRepository repository,
  bool allowSuperset = true,
  String title = 'Übung auswählen',
}) {
  return showCupertinoModalPopup<ExercisePickerResult>(
    context: context,
    builder: (_) => _ExercisePickerSheet(
      repository: repository,
      allowSuperset: allowSuperset,
      title: title,
    ),
  );
}

enum _PickerMode { normal, superset }

const _recentLimit = 5;

class _PickerData {
  const _PickerData({
    required this.exercises,
    required this.categories,
    required this.recent,
  });

  final List<CatalogExercise> exercises;
  final List<CatalogCategory> categories;
  final List<CatalogExercise> recent;
}

class _ExercisePickerSheet extends StatefulWidget {
  const _ExercisePickerSheet({
    required this.repository,
    required this.allowSuperset,
    required this.title,
  });

  final TrainingLogRepository repository;
  final bool allowSuperset;
  final String title;

  @override
  State<_ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<_ExercisePickerSheet> {
  final _searchController = TextEditingController();
  final List<CatalogExercise> _selected = [];
  _PickerData? _data;
  bool _failed = false;
  _PickerMode _mode = _PickerMode.normal;
  String _query = '';

  /// Kategorie, deren Übungen gerade angezeigt werden. Ohne Auswahl steht
  /// die Kategorienliste; „Alle Übungen“ ist [_browsing] ohne Kategorie.
  bool _browsing = false;
  CatalogCategory? _category;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final exercises = await widget.repository.readExercises();
      final categories = await widget.repository.readCategories();
      final recent = await _recentExercises(exercises);
      if (!mounted) return;
      setState(() {
        _data = _PickerData(
          exercises: exercises,
          categories: categories,
          recent: recent,
        );
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  /// Zuletzt verwendete Übungen aus dem Tagebuch, neueste zuerst, ohne Dubletten.
  Future<List<CatalogExercise>> _recentExercises(
    List<CatalogExercise> exercises,
  ) async {
    final byId = {for (final exercise in exercises) exercise.id: exercise};
    final recent = <CatalogExercise>[];
    for (final workout in await widget.repository.readDiary()) {
      for (final block in workout.exercises) {
        final exercise = byId[block.sourceExerciseId];
        if (exercise == null || recent.any((item) => item.id == exercise.id)) {
          continue;
        }
        recent.add(exercise);
        if (recent.length == _recentLimit) return recent;
      }
    }
    return recent;
  }

  List<CatalogExercise> _visibleExercises(_PickerData data) {
    final query = _fold(_query.trim());
    if (query.isNotEmpty) {
      return [
        for (final exercise in data.exercises)
          if (_fold(exercise.name).contains(query)) exercise,
      ];
    }
    final category = _category;
    return [
      for (final exercise in data.exercises)
        if (category == null || exercise.categoryIds.contains(category.id))
          exercise,
    ];
  }

  void _onTap(CatalogExercise exercise) {
    if (_mode == _PickerMode.normal) {
      Navigator.of(context)
          .pop(ExercisePickerResult(exercises: [exercise], asSuperset: false));
      return;
    }
    setState(() {
      final index = _selected.indexWhere((item) => item.id == exercise.id);
      if (index >= 0) {
        _selected.removeAt(index);
      } else {
        _selected.add(exercise);
      }
    });
  }

  void _confirmSuperset() {
    Navigator.of(context).pop(
      ExercisePickerResult(exercises: List.of(_selected), asSuperset: true),
    );
  }

  Future<void> _createExercise() async {
    final created = await showCupertinoModalPopup<CatalogExercise>(
      context: context,
      builder: (_) => _QuickCreateSheet(repository: widget.repository),
    );
    final data = _data;
    if (created == null || data == null || !mounted) return;
    setState(() {
      _data = _PickerData(
        exercises: [...data.exercises, created]..sort(_byName),
        categories: data.categories,
        recent: data.recent,
      );
    });
    _onTap(created);
  }

  void _setMode(_PickerMode mode) {
    setState(() {
      _mode = mode;
      if (mode == _PickerMode.normal) _selected.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return SafeArea(
      top: false,
      child: Container(
        height: MediaQuery.sizeOf(context).height * 0.9,
        margin: const EdgeInsets.all(GainerSpacing.xs),
        decoration: BoxDecoration(
          color: colors.elevatedSurface,
          borderRadius: BorderRadius.circular(GainerRadii.card),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                GainerSpacing.xs,
                GainerSpacing.s,
                GainerSpacing.xs,
                0,
              ),
              child: Row(
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Abbrechen',
                      style: GainerTypography.body.copyWith(
                        color: colors.accent,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: GainerTypography.cardTitle.copyWith(
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                  GainerToolbarButton(
                    icon: CupertinoIcons.add,
                    semanticLabel: 'Eigene Übung anlegen',
                    onPressed: _data == null ? null : _createExercise,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                GainerSpacing.m,
                GainerSpacing.s,
                GainerSpacing.m,
                GainerSpacing.xs,
              ),
              child: GainerSearchField(
                controller: _searchController,
                placeholder: 'Übung suchen',
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(child: _buildBody(colors)),
            if (widget.allowSuperset) _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(GainerColors colors) {
    final data = _data;
    if (_failed) {
      return _message(colors, 'Die Übungen konnten nicht geladen werden.');
    }
    if (data == null) return const Center(child: CupertinoActivityIndicator());

    if (_query.trim().isNotEmpty) return _searchBody(colors, data);
    if (_browsing) return _categoryBody(colors, data);

    return _list([
      if (data.recent.isNotEmpty) ...[
        _sectionHeader(colors, 'Zuletzt verwendet'),
        for (final exercise in data.recent) _exerciseRow(exercise),
      ],
      _sectionHeader(colors, 'Kategorien'),
      GainerListRow(
        title: 'Alle Übungen',
        showChevron: true,
        onTap: () => setState(() => _browsing = true),
      ),
      for (final category in data.categories)
        GainerListRow(
          title: category.name,
          showChevron: true,
          onTap: () => setState(() {
            _browsing = true;
            _category = category;
          }),
        ),
    ]);
  }

  Widget _searchBody(GainerColors colors, _PickerData data) {
    final matches = _visibleExercises(data);
    if (matches.isEmpty) {
      return _message(colors, 'Keine Treffer für „${_query.trim()}“.');
    }
    return _list([for (final exercise in matches) _exerciseRow(exercise)]);
  }

  Widget _categoryBody(GainerColors colors, _PickerData data) {
    final exercises = _visibleExercises(data);
    return _list([
      GainerListRow(
        title: 'Kategorien',
        leadingIcon: CupertinoIcons.chevron_back,
        onTap: () => setState(() {
          _browsing = false;
          _category = null;
        }),
      ),
      if (exercises.isEmpty)
        _messageRow(colors, 'Keine Übungen in dieser Kategorie.')
      else
        for (final exercise in exercises) _exerciseRow(exercise),
    ]);
  }

  Widget _list(List<Widget> rows) {
    return ListView(
      padding: const EdgeInsets.only(bottom: GainerSpacing.m),
      children: rows,
    );
  }

  Widget _exerciseRow(CatalogExercise exercise) {
    final index = _selected.indexWhere((item) => item.id == exercise.id);
    return GainerListRow(
      title: exercise.name,
      subtitle: _kindLabel(exercise.exerciseType),
      trailing: _mode == _PickerMode.superset
          ? _SelectionMark(selected: index >= 0)
          : null,
      onTap: () => _onTap(exercise),
    );
  }

  Widget _sectionHeader(GainerColors colors, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(
      GainerSpacing.m,
      GainerSpacing.m,
      GainerSpacing.m,
      GainerSpacing.xs,
    ),
    child: Text(
      text,
      style: GainerTypography.label.copyWith(color: colors.secondaryText),
    ),
  );

  Widget _message(GainerColors colors, String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(GainerSpacing.l),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: GainerTypography.body.copyWith(color: colors.secondaryText),
      ),
    ),
  );

  Widget _messageRow(GainerColors colors, String text) => Padding(
    padding: const EdgeInsets.all(GainerSpacing.m),
    child: Text(
      text,
      style: GainerTypography.body.copyWith(color: colors.secondaryText),
    ),
  );

  Widget _buildFooter() {
    final showSuperset = _mode == _PickerMode.superset;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GainerSpacing.m,
        GainerSpacing.xs,
        GainerSpacing.m,
        GainerSpacing.s,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GainerSegmentedControl<_PickerMode>(
            options: const {
              _PickerMode.normal: 'Normal',
              _PickerMode.superset: 'Supersatz',
            },
            value: _mode,
            onChanged: _setMode,
          ),
          if (showSuperset) ...[
            const SizedBox(height: GainerSpacing.s),
            GainerPillButton(
              label: 'Als Superset hinzufügen',
              expand: true,
              onPressed: _selected.length >= 2 ? _confirmSuperset : null,
            ),
          ],
        ],
      ),
    );
  }
}

/// Haken im Supersatz-Modus; ohne Auswahl ein leerer Kreis.
class _SelectionMark extends StatelessWidget {
  const _SelectionMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    if (selected) {
      return Icon(
        CupertinoIcons.checkmark_circle_fill,
        color: colors.accent,
        size: 26,
        semanticLabel: 'ausgewählt',
      );
    }
    return Container(
      width: 24,
      height: 24,
      margin: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: colors.separator, width: 1.5),
      ),
    );
  }
}

/// Schnelles Anlegen einer eigenen Übung mit Name und Typ.
class _QuickCreateSheet extends StatefulWidget {
  const _QuickCreateSheet({required this.repository});

  final TrainingLogRepository repository;

  @override
  State<_QuickCreateSheet> createState() => _QuickCreateSheetState();
}

class _QuickCreateSheetState extends State<_QuickCreateSheet> {
  final _nameController = TextEditingController();
  ExerciseKind _kind = ExerciseKind.strength;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final exercise = await widget.repository.createCustomExercise(
        CatalogExercise(
          id: widget.repository.newId(),
          name: _nameController.text.trim(),
          exerciseType: _kind,
          isBase: false,
        ),
      );
      if (mounted) Navigator.of(context).pop(exercise);
    } on WorkoutValidationException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.fields.values.isEmpty
            ? 'Die Übung ist ungültig.'
            : error.fields.values.first;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Die Übung konnte nicht angelegt werden.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(GainerSpacing.xs),
        padding: const EdgeInsets.all(GainerSpacing.m),
        decoration: BoxDecoration(
          color: colors.elevatedSurface,
          borderRadius: BorderRadius.circular(GainerRadii.card),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Neue Übung',
              textAlign: TextAlign.center,
              style: GainerTypography.cardTitle.copyWith(
                color: colors.primaryText,
              ),
            ),
            const SizedBox(height: GainerSpacing.m),
            CupertinoTextField(
              key: const ValueKey('quick-create-name'),
              controller: _nameController,
              autofocus: true,
              placeholder: 'Name der Übung',
              placeholderStyle: GainerTypography.body.copyWith(
                color: colors.placeholderText,
              ),
              style: GainerTypography.body.copyWith(color: colors.primaryText),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(GainerRadii.field),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: GainerSpacing.xs),
                child: Text(
                  _error!,
                  style: GainerTypography.caption.copyWith(
                    color: colors.destructive,
                  ),
                ),
              ),
            const SizedBox(height: GainerSpacing.m),
            GainerCard(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final kind in ExerciseKind.values)
                    GainerListRow(
                      title: _kindLabel(kind),
                      trailing: kind == _kind
                          ? Icon(
                              CupertinoIcons.checkmark,
                              color: colors.accent,
                              size: 20,
                            )
                          : null,
                      onTap: () => setState(() => _kind = kind),
                    ),
                ],
              ),
            ),
            const SizedBox(height: GainerSpacing.m),
            GainerPillButton(
              label: 'Anlegen',
              expand: true,
              isLoading: _saving,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}

int _byName(CatalogExercise a, CatalogExercise b) =>
    a.name.toLowerCase().compareTo(b.name.toLowerCase());

/// Suchnormalisierung: Groß-/Kleinschreibung und Umlaut-Schreibweise sind gleich.
String _fold(String value) => value
    .toLowerCase()
    .replaceAll('ä', 'ae')
    .replaceAll('ö', 'oe')
    .replaceAll('ü', 'ue')
    .replaceAll('ß', 'ss');

String _kindLabel(ExerciseKind kind) => switch (kind) {
  ExerciseKind.strength => 'Kraft',
  ExerciseKind.bodyweightLoaded => 'Körpergewicht mit Zusatzlast',
  ExerciseKind.bodyweightOnly => 'Reines Körpergewicht',
  ExerciseKind.assisted => 'Assistiert',
};
