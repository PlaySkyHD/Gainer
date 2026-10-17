import 'package:flutter/cupertino.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../../domain/models/training/exercise_catalog_model.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'category_library_view_model.dart';

/// Kategorienverwaltung: Basiskategorien nur lesend, eigene Kategorien anlegen,
/// umbenennen und archivieren.
class CategoryLibraryScreen extends StatefulWidget {
  const CategoryLibraryScreen({required this.repository, super.key});

  final TrainingLogRepository repository;

  @override
  State<CategoryLibraryScreen> createState() => _CategoryLibraryScreenState();
}

class _CategoryLibraryScreenState extends State<CategoryLibraryScreen> {
  late final CategoryLibraryViewModel _viewModel = CategoryLibraryViewModel(
    repository: widget.repository,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _viewModel.load());
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _edit(CatalogCategory? category) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => _CategorySheet(viewModel: _viewModel, category: category),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        return GainerScaffold(
          title: 'Kategorien',
          trailing: [
            GainerToolbarButton(
              icon: CupertinoIcons.add,
              semanticLabel: 'Kategorie anlegen',
              onPressed: () => _edit(null),
            ),
          ],
          children: _sections(colors),
        );
      },
    );
  }

  List<Widget> _sections(GainerColors colors) {
    final loading =
        _viewModel.isLoading &&
        _viewModel.baseCategories.isEmpty &&
        _viewModel.ownCategories.isEmpty;
    return [
      if (loading)
        const Center(child: CupertinoActivityIndicator())
      else if (_viewModel.errorMessage != null)
        GainerCard(
          child: Text(
            _viewModel.errorMessage!,
            textAlign: TextAlign.center,
            style: GainerTypography.body.copyWith(color: colors.secondaryText),
          ),
        )
      else ...[
        GainerGroupedSection(
          header: 'Basis-Kategorien',
          children: [
            for (final category in _viewModel.baseCategories)
              GainerListRow(
                key: ValueKey('category-row-${category.id}'),
                title: category.name,
                subtitle: 'Katalog',
              ),
          ],
        ),
        const SizedBox(height: GainerSpacing.m),
        if (_viewModel.ownCategories.isEmpty)
          GainerCard(
            padding: const EdgeInsets.all(GainerSpacing.l),
            child: Text(
              'Noch keine eigenen Kategorien.',
              textAlign: TextAlign.center,
              style: GainerTypography.body.copyWith(
                color: colors.secondaryText,
              ),
            ),
          )
        else
          GainerGroupedSection(
            header: 'Eigene Kategorien',
            children: [
              for (final category in _viewModel.ownCategories)
                GainerListRow(
                  key: ValueKey('category-row-${category.id}'),
                  title: category.name,
                  showChevron: true,
                  onTap: () => _edit(category),
                ),
            ],
          ),
      ],
      const SizedBox(height: GainerSpacing.l),
    ];
  }
}

/// Sheet zum Anlegen, Umbenennen und Archivieren einer eigenen Kategorie.
class _CategorySheet extends StatefulWidget {
  const _CategorySheet({required this.viewModel, this.category});

  final CategoryLibraryViewModel viewModel;
  final CatalogCategory? category;

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.category?.name ?? '',
  );
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
    final error = await widget.viewModel.save(
      name: _nameController.text,
      categoryId: widget.category?.id,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _archive() async {
    final category = widget.category;
    if (category == null) return;
    final confirmed = await showGainerStackedDialog<bool>(
      context: context,
      title: 'Kategorie archivieren?',
      message:
          '„${category.name}“ verschwindet aus der Auswahl. Zugeordnete Übungen bleiben unverändert erhalten.',
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
    final error = await widget.viewModel.archive(category.id);
    if (!mounted) return;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final editing = widget.category != null;
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
              editing ? 'Kategorie bearbeiten' : 'Neue Kategorie',
              textAlign: TextAlign.center,
              style: GainerTypography.cardTitle.copyWith(
                color: colors.primaryText,
              ),
            ),
            const SizedBox(height: GainerSpacing.m),
            CupertinoTextField(
              key: const ValueKey('category-name'),
              controller: _nameController,
              autofocus: true,
              placeholder: 'Name der Kategorie',
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
            GainerPillButton(
              key: const ValueKey('category-save'),
              label: 'Speichern',
              expand: true,
              isLoading: _saving,
              onPressed: _saving ? null : _save,
            ),
            if (editing) ...[
              const SizedBox(height: GainerSpacing.xs),
              GainerPillButton(
                key: const ValueKey('category-archive'),
                label: 'Archivieren',
                variant: GainerPillVariant.destructive,
                expand: true,
                onPressed: _archive,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
