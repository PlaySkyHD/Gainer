import 'package:flutter/cupertino.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../../domain/models/training/exercise_catalog_model.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'exercise_catalog_format.dart';
import 'exercise_editor_screen.dart';
import 'exercise_library_view_model.dart';

/// Übungsverwaltung: Basis- und eigene Übungen mit Suche, Kategorie-Filter
/// und Archiv-Schalter. Tippen öffnet den Editor.
class ExerciseLibraryScreen extends StatefulWidget {
  const ExerciseLibraryScreen({required this.repository, super.key});

  final TrainingLogRepository repository;

  @override
  State<ExerciseLibraryScreen> createState() => _ExerciseLibraryScreenState();
}

/// Platzhalter für „Alle Kategorien“ im Auswahl-Sheet, da null dort „abbrechen“ bedeutet.
const _allCategories = '';

class _ExerciseLibraryScreenState extends State<ExerciseLibraryScreen> {
  late final ExerciseLibraryViewModel _viewModel = ExerciseLibraryViewModel(
    repository: widget.repository,
  );
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _viewModel.load());
  }

  @override
  void dispose() {
    _viewModel.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openEditor(CatalogExercise? exercise) async {
    final changed = await Navigator.of(context).push<bool>(
      CupertinoPageRoute<bool>(
        builder: (_) => ExerciseEditorScreen(
          repository: widget.repository,
          exercise: exercise,
        ),
      ),
    );
    if (changed == true && mounted) await _viewModel.load();
  }

  Future<void> _pickCategory() async {
    final picked = await showGainerActionSheet<String>(
      context: context,
      title: 'Kategorie',
      groups: [
        [
          const GainerSheetAction(
            label: 'Alle Kategorien',
            icon: CupertinoIcons.square_grid_2x2,
            value: _allCategories,
          ),
        ],
        [
          for (final category in _viewModel.categories)
            GainerSheetAction(
              label: category.name,
              icon: CupertinoIcons.tag,
              value: category.id,
            ),
        ],
      ],
    );
    if (picked == null || !mounted) return;
    _viewModel.setCategory(picked == _allCategories ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final exercises = _viewModel.visibleExercises;
        final categoryId = _viewModel.categoryId;
        final categoryName = categoryId == null
            ? 'Alle'
            : _viewModel.categoryById(categoryId)?.name ?? 'Alle';
        return GainerScaffold(
          title: 'Übungen',
          trailing: [
            GainerToolbarButton(
              icon: CupertinoIcons.add,
              semanticLabel: 'Übung anlegen',
              onPressed: () => _openEditor(null),
            ),
          ],
          children: [
            GainerSearchField(
              controller: _searchController,
              placeholder: 'Übung suchen',
              onChanged: _viewModel.setQuery,
            ),
            const SizedBox(height: GainerSpacing.m),
            GainerGroupedSection(
              children: [
                GainerListRow(
                  key: const ValueKey('exercise-library-category'),
                  title: 'Kategorie',
                  value: categoryName,
                  showChevron: true,
                  onTap: _pickCategory,
                ),
                GainerListRow(
                  title: 'Archivierte anzeigen',
                  trailing: CupertinoSwitch(
                    key: const ValueKey('exercise-library-archived'),
                    value: _viewModel.showArchived,
                    onChanged: _viewModel.setShowArchived,
                  ),
                ),
              ],
            ),
            const SizedBox(height: GainerSpacing.m),
            if (_viewModel.isLoading && _viewModel.exercises.isEmpty)
              const Center(child: CupertinoActivityIndicator())
            else if (_viewModel.errorMessage != null)
              GainerCard(
                child: Text(
                  _viewModel.errorMessage!,
                  textAlign: TextAlign.center,
                  style: GainerTypography.body.copyWith(
                    color: colors.secondaryText,
                  ),
                ),
              )
            else if (exercises.isEmpty)
              GainerCard(
                padding: const EdgeInsets.all(GainerSpacing.l),
                child: Text(
                  'Keine Übungen gefunden.',
                  textAlign: TextAlign.center,
                  style: GainerTypography.body.copyWith(
                    color: colors.secondaryText,
                  ),
                ),
              )
            else
              GainerGroupedSection(
                header: 'Übungen',
                children: [
                  for (final exercise in exercises)
                    GainerListRow(
                      key: ValueKey('exercise-row-${exercise.id}'),
                      title: exercise.name,
                      subtitle: _subtitle(exercise),
                      showChevron: true,
                      onTap: () => _openEditor(exercise),
                    ),
                ],
              ),
            const SizedBox(height: GainerSpacing.l),
          ],
        );
      },
    );
  }

  String _subtitle(CatalogExercise exercise) => [
    exercise.isBase ? 'Katalog' : 'Eigene',
    catalogKindLabel(exercise.exerciseType),
    if (exercise.isArchived) 'Archiviert',
  ].join(' · ');
}
