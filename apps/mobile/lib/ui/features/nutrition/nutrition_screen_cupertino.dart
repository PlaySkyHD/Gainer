import 'package:flutter/cupertino.dart';

import '../../../data/repositories/nutrition/nutrition_repository.dart';
import '../../../domain/models/nutrition/nutrition.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'food_add_target.dart';
import 'nutrition_averages_view.dart';
import 'nutrition_view_model.dart';

const _notRecognizedLabel = 'nicht erkannt';

enum _NutritionEntryMode {
  choices,
  recent,
  meals,
  manual,
  search,
  barcode,
  estimate,
  label,
}

extension on _NutritionEntryMode {
  String get title => switch (this) {
    _NutritionEntryMode.choices => 'Lebensmittel hinzufügen',
    _NutritionEntryMode.recent => 'Zuletzt verwendet',
    _NutritionEntryMode.meals => 'Gespeicherte Gerichte',
    _NutritionEntryMode.manual => 'Manuell erfassen',
    _NutritionEntryMode.search => 'Lebensmittel suchen',
    _NutritionEntryMode.barcode => 'Barcode',
    _NutritionEntryMode.estimate => 'Mahlzeit schätzen',
    _NutritionEntryMode.label => 'Etikett erfassen',
  };

  String get description => switch (this) {
    _NutritionEntryMode.choices => 'Erfassungsart auswählen',
    _NutritionEntryMode.recent => 'Lebensmittel von früheren Einträgen',
    _NutritionEntryMode.meals => 'Ein gespeichertes Gericht übernehmen',
    _NutritionEntryMode.manual => 'Nährwerte selbst eingeben',
    _NutritionEntryMode.search => 'Online nach Produkt oder Marke suchen',
    _NutritionEntryMode.barcode => 'Produkt über den Barcode finden',
    _NutritionEntryMode.estimate => 'Text oder Foto als Vorschlag prüfen',
    _NutritionEntryMode.label => 'Nährwertetikett fotografieren und prüfen',
  };

  IconData get icon => switch (this) {
    _NutritionEntryMode.choices => CupertinoIcons.add,
    _NutritionEntryMode.recent => CupertinoIcons.clock,
    _NutritionEntryMode.meals => CupertinoIcons.book,
    _NutritionEntryMode.manual => CupertinoIcons.pencil,
    _NutritionEntryMode.search => CupertinoIcons.search,
    _NutritionEntryMode.barcode => CupertinoIcons.barcode_viewfinder,
    _NutritionEntryMode.estimate => CupertinoIcons.sparkles,
    _NutritionEntryMode.label => CupertinoIcons.doc_text_viewfinder,
  };
}

/// Erfassungswege je Ziel. Mehrteilige Schätzung, Etikettenscan und das
/// Übernehmen gespeicherter Gerichte sind nur für Tagesmahlzeiten verfügbar.
List<_NutritionEntryMode> _modesFor(FoodAddTarget target) => [
  for (final mode in _NutritionEntryMode.values)
    if (mode != _NutritionEntryMode.choices &&
        (target is DayMealTarget ||
            const {
              _NutritionEntryMode.recent,
              _NutritionEntryMode.manual,
              _NutritionEntryMode.search,
              _NutritionEntryMode.barcode,
            }.contains(mode)))
      mode,
];

class NutritionScreen extends StatefulWidget {
  const NutritionScreen({super.key, required this.viewModel});
  final NutritionViewModel viewModel;

  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends State<NutritionScreen> {
  final _name = TextEditingController();
  final _brand = TextEditingController();
  final _amount = TextEditingController(text: '100');
  final _kcal = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  final _search = TextEditingController();
  final _estimateText = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.viewModel.load();
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _brand,
      _amount,
      _kcal,
      _protein,
      _carbs,
      _fat,
      _search,
      _estimateText,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.viewModel,
    builder: (context, _) {
      final vm = widget.viewModel;
      final snapshot = vm.snapshot;
      final dayView = GainerScaffold(
        title: 'Ernährung',
        leading: _DayNavigator(
          label: _dateLabel(vm.localDate, _dateString(vm.repository.clock())),
          onPrevious: () => _shiftDay(-1),
          onNext: () => _shiftDay(1),
          onPick: () => _pickDay(context),
        ),
        trailing: [
          GainerToolbarButton(
            key: const ValueKey('nutrition-add-food'),
            icon: CupertinoIcons.add,
            semanticLabel: 'Lebensmittel hinzufügen',
            onPressed: _openEntry,
          ),
          GainerToolbarButton(
            key: const ValueKey('nutrition-more-menu'),
            icon: CupertinoIcons.ellipsis,
            semanticLabel: 'Weitere Aktionen',
            onPressed: _showMenu,
          ),
        ],
        children: [
          if (vm.errorMessage != null &&
              vm.errorOperation == NutritionErrorOperation.day) ...[
            _notice(context, vm.errorMessage!, isError: true),
            GainerPillButton(
              label: 'Tagebuch erneut laden',
              icon: CupertinoIcons.refresh,
              variant: GainerPillVariant.tonal,
              expand: true,
              onPressed: vm.load,
            ),
          ],
          if (snapshot == null && vm.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: CupertinoActivityIndicator()),
            ),
          if (snapshot != null) ..._dayChildren(context, vm, snapshot),
          if (vm.isSaving || vm.isOnlineOperation)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CupertinoActivityIndicator()),
            ),
        ],
      );
      if (vm.errorMessage == null ||
          vm.errorOperation != NutritionErrorOperation.diary) {
        return dayView;
      }
      // Fehler des Tagebuchs bleiben oberhalb der Liste sichtbar, auch wenn
      // der Nutzer nach unten scrollt.
      return Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _notice(context, vm.errorMessage!, isError: true),
            ),
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: dayView,
            ),
          ),
        ],
      );
    },
  );

  List<Widget> _dayChildren(
    BuildContext context,
    NutritionViewModel vm,
    NutritionSnapshot snapshot,
  ) => [
    _DayCard(
      totals: snapshot.day.totals,
      target: _targetFor(vm.localDate, snapshot.targetSchedule),
      onManage: _openPlanning,
    ),
    NutritionAveragesEntry(repository: vm.repository, refreshKey: snapshot),
    if (vm.statusMessage != null)
      Semantics(liveRegion: true, child: _notice(context, vm.statusMessage!)),
    for (final meal in NutritionMeal.values)
      Padding(
        padding: const EdgeInsets.only(top: GainerSpacing.l),
        child: _MealSection(
          key: ValueKey('meal-${meal.name}'),
          meal: meal,
          entries: snapshot.day.entries
              .where((entry) => entry.meal == meal)
              .toList(),
          onAdd: () {
            vm.selectMeal(meal);
            _openEntry();
          },
          onEdit: _editEntry,
          onRemove: (entry) => vm.removeEntry(entry.entryId),
          onConfirmRemove: (entry) => confirmGainerDelete(
            context,
            title: 'Eintrag löschen?',
            message: '„${entry.productName}“ wird aus dem Tagebuch entfernt.',
          ),
          onMoveTo: (entries, orderedIds) =>
              _applyEntryOrder(meal, entries, orderedIds),
        ),
      ),
  ];

  /// Ordnet die Einträge einer Mahlzeit per Einzelschritten in [targetIds]
  /// um. Jeder Schritt ist ein `moveEntry` wie bisher beim Nach-oben-Schieben.
  Future<void> _applyEntryOrder(
    NutritionMeal meal,
    List<NutritionEntry> entries,
    List<String> targetIds,
  ) async {
    final current = [for (final entry in entries) entry.entryId];
    for (var target = 0; target < targetIds.length; target++) {
      final id = targetIds[target];
      final from = current.indexOf(id);
      if (from == target) continue;
      current
        ..removeAt(from)
        ..insert(target, id);
      await widget.viewModel.moveEntry(id, meal, target);
      if (!mounted) return;
    }
  }

  /// Menü der Seitenaktionen (…): Gerichte und Ziele.
  Future<void> _showMenu() async {
    final choice = await showGainerActionSheet<_NutritionMenuAction>(
      context: context,
      title: 'Ernährung',
      groups: const [
        [
          GainerSheetAction(
            label: 'Gerichte und Ziele verwalten',
            icon: CupertinoIcons.slider_horizontal_3,
            value: _NutritionMenuAction.planning,
          ),
        ],
      ],
    );
    if (choice == _NutritionMenuAction.planning && mounted) {
      await _openPlanning();
    }
  }

  /// Öffnet den gemeinsamen Hinzufügen-Dialog als Sheet. Für [DayMealTarget]
  /// schreibt er Einträge in die gewählte Mahlzeit und liefert `null`. Für
  /// [MealDraftTarget] liefert er das bestätigte Lebensmittel als Draft zurück
  /// und verändert keinen Ernährungstag; Abbrechen liefert `null`.
  Future<FoodComponentDraft?> _openEntry({
    FoodAddTarget target = const DayMealTarget(),
  }) {
    final vm = widget.viewModel;
    vm.dismissActionError();
    var mode = _NutritionEntryMode.choices;
    return showGainerSheet<FoodComponentDraft>(
      context: context,
      heightFactor: 0.9,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => AnimatedBuilder(
          animation: vm,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _entryHeader(
                sheetContext,
                target,
                mode,
                onBack: () => setSheetState(() {
                  vm.dismissActionError();
                  mode = _NutritionEntryMode.choices;
                }),
              ),
              if (target is DayMealTarget) _mealSegment(vm),
              Expanded(
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(
                    GainerSpacing.m,
                    GainerSpacing.m,
                    GainerSpacing.m,
                    GainerSpacing.l,
                  ),
                  children: mode == _NutritionEntryMode.choices
                      ? _choiceChildren(
                          target,
                          (option) => setSheetState(() => mode = option),
                        )
                      : _entryChildren(
                          context,
                          vm,
                          mode,
                          target,
                          (draft) => Navigator.of(sheetContext).pop(draft),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _entryHeader(
    BuildContext sheetContext,
    FoodAddTarget target,
    _NutritionEntryMode mode, {
    required VoidCallback onBack,
  }) {
    final atChoices = mode == _NutritionEntryMode.choices;
    return GainerSheetHeader(
      title: atChoices
          ? (target is MealDraftTarget
                ? 'Bestandteil hinzufügen'
                : 'Hinzufügen')
          : mode.title,
      leading: GainerToolbarButton(
        key: ValueKey(
          atChoices ? 'nutrition-entry-close' : 'nutrition-entry-options',
        ),
        icon: atChoices ? CupertinoIcons.xmark : CupertinoIcons.chevron_left,
        semanticLabel: atChoices ? 'Schließen' : 'Optionen',
        onPressed: atChoices ? () => Navigator.of(sheetContext).pop() : onBack,
      ),
    );
  }

  Widget _mealSegment(NutritionViewModel vm) => Padding(
    padding: const EdgeInsets.fromLTRB(
      GainerSpacing.m,
      GainerSpacing.s,
      GainerSpacing.m,
      0,
    ),
    child: GainerSegmentedControl<NutritionMeal>(
      options: {
        for (final meal in NutritionMeal.values) meal: _mealShortName(meal),
      },
      value: vm.selectedMeal,
      onChanged: vm.selectMeal,
    ),
  );

  List<Widget> _choiceChildren(
    FoodAddTarget target,
    ValueChanged<_NutritionEntryMode> onSelectMode,
  ) => [
    GainerGroupedSection(
      children: [
        for (final option in _modesFor(target))
          GainerListRow(
            key: ValueKey('nutrition-mode-${option.name}'),
            leadingIcon: option.icon,
            title: option.title,
            subtitle: option.description,
            showChevron: true,
            onTap: () => onSelectMode(option),
          ),
      ],
    ),
  ];

  List<Widget> _entryChildren(
    BuildContext context,
    NutritionViewModel vm,
    _NutritionEntryMode mode,
    FoodAddTarget target,
    ValueChanged<FoodComponentDraft> onDraft,
  ) => [
    if (vm.errorMessage != null &&
        vm.errorOperation != null &&
        vm.errorOperation != NutritionErrorOperation.day)
      _notice(context, vm.errorMessage!, isError: true),
    if (vm.statusMessage != null && target is DayMealTarget)
      Semantics(liveRegion: true, child: _notice(context, vm.statusMessage!)),
    ..._entryTools(context, vm, mode, target, onDraft),
    if (vm.isSaving || vm.isOnlineOperation)
      const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CupertinoActivityIndicator()),
      ),
  ];

  Widget _amountGroup() => GainerGroupedSection(
    children: [
      GainerTextFieldRow(
        label: 'Menge',
        unit: 'g',
        controller: _amount,
        keyboardType: _decimalKeyboard,
        fieldKey: const ValueKey('nutrition-entry-amount'),
      ),
    ],
  );

  List<Widget> _entryTools(
    BuildContext context,
    NutritionViewModel vm,
    _NutritionEntryMode mode,
    FoodAddTarget target,
    ValueChanged<FoodComponentDraft> onDraft,
  ) {
    void submit(NutritionFood food) => _submitFood(food, target, onDraft);
    return switch (mode) {
      _NutritionEntryMode.manual => [
        ..._foodFormGroups(
          name: _name,
          brand: _brand,
          amount: _amount,
          kcal: _kcal,
          protein: _protein,
          carbs: _carbs,
          fat: _fat,
          nameKey: const ValueKey('nutrition-entry-name'),
          brandKey: const ValueKey('nutrition-entry-brand'),
          amountKey: const ValueKey('nutrition-entry-amount'),
          kcalKey: const ValueKey('nutrition-entry-kcal'),
        ),
        const SizedBox(height: GainerSpacing.l),
        GainerPillButton(
          key: const ValueKey('nutrition-entry-save'),
          label: target is DayMealTarget ? 'Manuell speichern' : 'Übernehmen',
          expand: true,
          onPressed: vm.isSaving ? null : () => _addManual(target, onDraft),
        ),
      ],
      _NutritionEntryMode.recent => _recentTools(vm, submit),
      _NutritionEntryMode.meals => _mealTools(vm),
      _NutritionEntryMode.search => _searchTools(vm, submit),
      _NutritionEntryMode.barcode => _barcodeTools(vm, submit),
      _NutritionEntryMode.estimate => _estimateTools(vm),
      _NutritionEntryMode.label => [
        GainerPillButton(
          label: 'Nährwertetikett erfassen',
          icon: CupertinoIcons.doc_text_viewfinder,
          variant: GainerPillVariant.tonal,
          expand: true,
          onPressed: vm.isOnlineOperation ? null : _scanLabel,
        ),
      ],
      _NutritionEntryMode.choices => const [],
    };
  }

  /// Ergebniszeilen von „Zuletzt“, Suche und Barcode. Antippen übernimmt das
  /// Lebensmittel mit der eingegebenen Menge.
  Widget _foodResults(
    List<NutritionFood> foods,
    String fallback,
    ValueChanged<NutritionFood> onSelect,
  ) => GainerGroupedSection(
    children: [
      for (final food in foods)
        GainerListRow(
          title: food.name,
          subtitle:
              '${food.brand ?? food.source.provider ?? fallback} · ${_fmtKcal(food.per100Grams.kilocalories)} kcal / 100 g',
          trailing: const _AddGlyph(),
          onTap: () => onSelect(food),
        ),
    ],
  );

  List<Widget> _recentTools(
    NutritionViewModel vm,
    ValueChanged<NutritionFood> onSelect,
  ) {
    final foods = vm.snapshot?.recentFoods ?? const <NutritionFood>[];
    return [
      _amountGroup(),
      const SizedBox(height: GainerSpacing.m),
      if (foods.isEmpty)
        _hint('Noch keine zuletzt verwendeten Lebensmittel.')
      else
        _foodResults(foods, 'Lebensmittel', onSelect),
    ];
  }

  List<Widget> _mealTools(NutritionViewModel vm) {
    final meals = [
      for (final meal in vm.snapshot?.meals ?? const [])
        if (meal.value.status == 'Active') meal,
    ];
    if (meals.isEmpty) return [_hint('Noch keine gespeicherten Gerichte.')];
    return [
      GainerGroupedSection(
        children: [
          for (final meal in meals)
            _ReusableMealRow(
              meal: meal.value,
              onAdd: () => _addReusableMeal(meal.id, meal.value),
              onEdit: null,
              onArchive: null,
            ),
        ],
      ),
    ];
  }

  List<Widget> _searchTools(
    NutritionViewModel vm,
    ValueChanged<NutritionFood> onSelect,
  ) => [
    GainerSearchField(
      key: const ValueKey('nutrition-entry-search'),
      controller: _search,
      placeholder: 'Produkt oder Marke',
      onSubmitted: (query) => _searchFoods(vm, query),
    ),
    const SizedBox(height: GainerSpacing.m),
    _amountGroup(),
    if (vm.searchResults.isNotEmpty) ...[
      const SizedBox(height: GainerSpacing.m),
      _foodResults(vm.searchResults, 'Lebensmittel', onSelect),
    ],
  ];

  List<Widget> _barcodeTools(
    NutritionViewModel vm,
    ValueChanged<NutritionFood> onSelect,
  ) => [
    _amountGroup(),
    const SizedBox(height: GainerSpacing.m),
    GainerPillButton(
      label: 'Barcode scannen',
      icon: CupertinoIcons.barcode_viewfinder,
      variant: GainerPillVariant.tonal,
      expand: true,
      onPressed: vm.isOnlineOperation ? null : vm.lookupBarcode,
    ),
    if (vm.barcodeFood case final food?) ...[
      const SizedBox(height: GainerSpacing.m),
      _foodResults([food], 'Barcode', onSelect),
    ],
  ];

  List<Widget> _estimateTools(NutritionViewModel vm) => [
    GainerGroupedSection(
      footer: 'Vorschläge werden erst nach deiner Bestätigung gespeichert.',
      children: [
        GainerTextFieldRow(
          label: 'Beschreibung',
          placeholder: 'z. B. Haferflocken mit Banane',
          controller: _estimateText,
          textAlign: TextAlign.end,
        ),
      ],
    ),
    const SizedBox(height: GainerSpacing.m),
    ValueListenableBuilder<TextEditingValue>(
      valueListenable: _estimateText,
      builder: (context, value, _) => GainerPillButton(
        label: 'Mahlzeit schätzen',
        icon: CupertinoIcons.sparkles,
        variant: GainerPillVariant.tonal,
        expand: true,
        onPressed: vm.isOnlineOperation || value.text.trim().isEmpty
            ? null
            : () => vm.estimateMeal(_estimateText.text),
      ),
    ),
    const SizedBox(height: GainerSpacing.xs),
    GainerPillButton(
      label: 'Foto aufnehmen',
      icon: CupertinoIcons.camera,
      variant: GainerPillVariant.tonal,
      expand: true,
      onPressed: vm.isOnlineOperation ? null : _captureMealEstimate,
    ),
    if (vm.mealEstimateDraft case final estimate?) ...[
      const SizedBox(height: GainerSpacing.l),
      GainerSectionHeader(title: 'Vorschlag prüfen · ${estimate.provider}'),
      const SizedBox(height: GainerSpacing.xs),
      GainerGroupedSection(
        children: [
          for (var index = 0; index < estimate.components.length; index++)
            GainerListRow(
              title: estimate.components[index].name,
              subtitle:
                  '${_fmtGrams(estimate.components[index].amountGrams)} g · ${_fmtKcal(estimate.components[index].totals.kilocalories)} kcal · ${estimate.components[index].confidence}',
              trailing: const _AddGlyph(),
              onTap: () => vm.confirmEstimatedComponent(index),
            ),
        ],
      ),
      const SizedBox(height: GainerSpacing.m),
      GainerPillButton(
        label: 'Schätzung verwerfen',
        variant: GainerPillVariant.tonal,
        expand: true,
        onPressed: vm.discardEstimate,
      ),
    ],
  ];

  Widget _hint(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: GainerSpacing.s),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: GainerTypography.label.copyWith(
        color: GainerDesign.colorsOf(context).secondaryText,
      ),
    ),
  );

  /// Übernimmt ein gefundenes Lebensmittel in das [target].
  void _submitFood(
    NutritionFood food,
    FoodAddTarget target,
    ValueChanged<FoodComponentDraft> onDraft,
  ) {
    final amount = _parse(_amount.text) ?? 100;
    switch (target) {
      case DayMealTarget():
        widget.viewModel.addFood(food, amountGrams: amount);
      case MealDraftTarget():
        _commitDraft(
          FoodComponentDraft(
            name: food.name,
            brand: food.brand,
            amountGrams: amount,
            per100Grams: food.per100Grams,
            source: food.source,
          ),
          onDraft,
        );
    }
  }

  /// Gibt einen gültigen Draft an den Aufrufer zurück. Bei ungültigen Werten
  /// bleibt der Dialog offen und zeigt den Fehler; der Entwurf bleibt
  /// unverändert.
  bool _commitDraft(
    FoodComponentDraft draft,
    ValueChanged<FoodComponentDraft> onDraft,
  ) {
    final problem = draft.validate();
    if (problem != null) {
      widget.viewModel.reportInputError(
        problem,
        operation: NutritionErrorOperation.entry,
      );
      return false;
    }
    onDraft(draft);
    return true;
  }

  void _searchFoods(NutritionViewModel vm, String query) {
    final value = query.trim();
    if (value.length < 2) {
      vm.reportInputError(
        'Bitte mindestens zwei Zeichen eingeben.',
        operation: NutritionErrorOperation.search,
      );
      return;
    }
    vm.searchFoods(value);
  }

  Future<void> _openPlanning() {
    final vm = widget.viewModel;
    vm.dismissActionError();
    return Navigator.of(context).push<void>(
      CupertinoPageRoute<void>(
        builder: (_) => AnimatedBuilder(
          animation: vm,
          builder: (context, _) => GainerScaffold(
            title: 'Gerichte und Ziele',
            leading: GainerToolbarButton(
              key: const ValueKey('nutrition-planning-back'),
              icon: CupertinoIcons.chevron_left,
              semanticLabel: 'Zurück',
              onPressed: () => Navigator.of(context).pop(),
            ),
            children: [
              if (vm.errorMessage != null &&
                  vm.errorOperation == NutritionErrorOperation.planning)
                _notice(context, vm.errorMessage!, isError: true),
              const GainerSectionHeader(title: 'Gespeicherte Gerichte'),
              const SizedBox(height: GainerSpacing.xs),
              GainerGroupedSection(
                children: [
                  GainerListRow(
                    title: 'Neues Gericht anlegen',
                    leadingIcon: CupertinoIcons.add,
                    showChevron: true,
                    onTap: () => _editReusableMeal(),
                  ),
                  ..._mealRows(vm),
                ],
              ),
              const SizedBox(height: GainerSpacing.l),
              const GainerSectionHeader(title: 'Zielphasen'),
              const SizedBox(height: GainerSpacing.xs),
              GainerGroupedSection(
                children: [
                  GainerListRow(
                    title: 'Zielphase hinzufügen',
                    leadingIcon: CupertinoIcons.add,
                    showChevron: true,
                    onTap: () => _editTargetPhase(),
                  ),
                  ..._targetPhaseRows(vm),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _mealRows(NutritionViewModel vm) => [
    for (final meal in vm.snapshot?.meals ?? const [])
      _ReusableMealRow(
        meal: meal.value,
        onAdd: () => _addReusableMeal(meal.id, meal.value),
        onEdit: meal.value.status == 'Active'
            ? () => _editReusableMeal(id: meal.id, existing: meal.value)
            : null,
        onArchive: meal.value.status == 'Active'
            ? () => vm.archiveReusableMeal(meal.id)
            : null,
      ),
  ];

  List<Widget> _targetPhaseRows(NutritionViewModel vm) => [
    for (final phase in vm.snapshot?.targetSchedule?.versions ?? const [])
      _TargetPhaseRow(
        key: ValueKey('target-phase-${phase.targetVersionId}'),
        phase: phase,
        onEdit: _isUpcomingPhase(vm, phase)
            ? () => _editTargetPhase(existing: phase)
            : null,
        onDelete: _isUpcomingPhase(vm, phase)
            ? () => vm.removeTargetPhase(phase.targetVersionId)
            : null,
        onConfirmDelete: _isUpcomingPhase(vm, phase)
            ? () => _confirmRemoveTargetPhase(phase)
            : null,
      ),
  ];

  bool _isUpcomingPhase(NutritionViewModel vm, NutritionTargetVersion phase) =>
      phase.effectiveFrom.compareTo(_dateString(vm.repository.clock())) > 0;

  Future<void> _shiftDay(int days) {
    final date = DateTime.parse(widget.viewModel.localDate)
        .add(Duration(days: days));
    return widget.viewModel.selectDate(_dateString(date));
  }

  Future<void> _pickDay(BuildContext context) async {
    final initial = DateTime.parse(widget.viewModel.localDate);
    final date = await showGainerDatePicker(
      context: context,
      title: 'Tag auswählen',
      initial: initial,
      maximum: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date != null && mounted) {
      await widget.viewModel.selectDate(_dateString(date));
    }
  }

  Future<void> _editEntry(NutritionEntry entry) async {
    final c = _EntryEditControllers(entry);
    var meal = entry.meal;
    try {
      await Navigator.of(context).push<({NutritionMeal meal})>(
        CupertinoPageRoute<({NutritionMeal meal})>(
          builder: (routeContext) => AnimatedBuilder(
            animation: widget.viewModel,
            builder: (routeContext, _) => StatefulBuilder(
              builder: (routeContext, setRouteState) => _FormPage(
                title: 'Eintrag bearbeiten',
                closeKey: const ValueKey('nutrition-edit-close'),
                onSave: _isEntryEditBlocked(c)
                    ? null
                    : () => _saveEntryEdit(routeContext, c, entry, meal),
                children: _entryEditFields(
                  routeContext,
                  c,
                  entry,
                  meal,
                  refresh: () => setRouteState(() {}),
                  onMealChanged: (selected) =>
                      setRouteState(() => meal = selected),
                ),
              ),
            ),
          ),
        ),
      );
    } finally {
      c.dispose();
    }
  }

  bool _isEntryEditBlocked(_EntryEditControllers c) =>
      _parse(c.amount.text) == null ||
      _parse(c.kcal.text) == null ||
      c.name.text.trim().isEmpty ||
      widget.viewModel.isSaving;

  Future<void> _saveEntryEdit(
    BuildContext routeContext,
    _EntryEditControllers c,
    NutritionEntry entry,
    NutritionMeal meal,
  ) async {
    await widget.viewModel.updateEntry(
      original: entry,
      meal: meal,
      productName: c.name.text,
      brand: c.brand.text.trim().isEmpty ? null : c.brand.text,
      amountGrams: _parse(c.amount.text)!,
      per100Grams: NutritionTotals(
        kilocalories: _parse(c.kcal.text)!,
        proteinGrams: _nullable(c.protein.text),
        carbohydrateGrams: _nullable(c.carbs.text),
        fatGrams: _nullable(c.fat.text),
      ),
    );
    if (widget.viewModel.errorMessage == null &&
        routeContext.mounted &&
        ModalRoute.of(routeContext)?.isCurrent == true) {
      Navigator.pop(routeContext, (meal: meal));
    }
  }

  List<Widget> _entryEditFields(
    BuildContext routeContext,
    _EntryEditControllers c,
    NutritionEntry entry,
    NutritionMeal meal, {
    required VoidCallback refresh,
    required ValueChanged<NutritionMeal> onMealChanged,
  }) => [
    if (widget.viewModel.errorMessage != null &&
        widget.viewModel.errorOperation == NutritionErrorOperation.diary)
      _notice(routeContext, widget.viewModel.errorMessage!, isError: true),
    if (widget.viewModel.isSaving)
      const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CupertinoActivityIndicator()),
      ),
    ..._foodFormGroups(
      name: c.name,
      brand: c.brand,
      amount: c.amount,
      kcal: c.kcal,
      protein: c.protein,
      carbs: c.carbs,
      fat: c.fat,
      nameKey: const ValueKey('nutrition-edit-name'),
      amountKey: const ValueKey('nutrition-edit-amount'),
      kcalKey: const ValueKey('nutrition-edit-kcal'),
      onChanged: (_) => refresh(),
    ),
    const SizedBox(height: GainerSpacing.m),
    GainerGroupedSection(
      footer: entry.source == null
          ? 'Manueller Eintrag'
          : 'Quelle ${entry.source!.provider ?? entry.source!.barcode ?? 'Lebensmittelkatalog'} bleibt erhalten.',
      children: [
        GainerListRow(
          title: 'Mahlzeit',
          value: _mealName(meal),
          showChevron: true,
          onTap: () async {
            final selected = await _chooseMealValue();
            if (selected != null) onMealChanged(selected);
          },
        ),
      ],
    ),
  ];

  Future<NutritionMeal?> _chooseMealValue() => _chooseFromSheet<NutritionMeal>(
    title: 'Mahlzeit auswählen',
    options: [
      for (final item in NutritionMeal.values)
        (label: _mealName(item), icon: _mealIcon(item), value: item),
    ],
  );

  Future<void> _editReusableMeal({String? id, ReusableMeal? existing}) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final description = TextEditingController(
      text: existing?.description ?? '',
    );
    final portion = TextEditingController(
      text: _grams(existing?.standardPortion ?? 1),
    );
    // Lokaler Entwurf: bleibt bis „Sichern“ unverändert gegenüber dem
    // gespeicherten Gericht und berührt nie einen Ernährungstag.
    final components = <ReusableMealComponent>[...?existing?.components];
    try {
      final save = await Navigator.of(context).push<bool>(
        CupertinoPageRoute<bool>(
          builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => _recipeEditorPage(
              context,
              setDialogState,
              existing: existing,
              name: name,
              description: description,
              portion: portion,
              components: components,
            ),
          ),
        ),
      );
      if (save != true || !mounted) return;
      final value = _reusableMealFromDraft(
        name: name,
        description: description,
        portion: portion,
        components: components,
      );
      await widget.viewModel.saveReusableMeal(
        id: id,
        meal: value,
        operation: NutritionErrorOperation.planning,
      );
    } catch (error) {
      widget.viewModel.reportInputError(
        error.toString(),
        operation: NutritionErrorOperation.planning,
      );
    } finally {
      name.dispose();
      description.dispose();
      portion.dispose();
    }
  }

  Widget _recipeEditorPage(
    BuildContext context,
    StateSetter setDialogState, {
    required ReusableMeal? existing,
    required TextEditingController name,
    required TextEditingController description,
    required TextEditingController portion,
    required List<ReusableMealComponent> components,
  }) {
    void refresh() => setDialogState(() {});
    final totalKcal = components.fold<double>(
      0,
      (sum, item) => sum + item.totals.kilocalories,
    );
    return _FormPage(
      title: existing == null ? 'Neues Gericht' : 'Gericht bearbeiten',
      closeKey: const ValueKey('nutrition-recipe-close'),
      onSave: _canSaveRecipe(name, portion, components)
          ? () => Navigator.pop(context, true)
          : null,
      children: [
        GainerGroupedSection(
          children: [
            GainerTextFieldRow(
              label: 'Name',
              placeholder: 'Gerichtsname',
              controller: name,
              fieldKey: const ValueKey('nutrition-recipe-name'),
              onChanged: (_) => refresh(),
            ),
            GainerTextFieldRow(
              label: 'Beschreibung',
              placeholder: 'Optional',
              controller: description,
              onChanged: (_) => refresh(),
            ),
            GainerTextFieldRow(
              label: 'Standardportion',
              unit: '×',
              controller: portion,
              keyboardType: _decimalKeyboard,
              onChanged: (_) => refresh(),
            ),
          ],
        ),
        const SizedBox(height: GainerSpacing.l),
        GainerSectionHeader(
          title: 'Bestandteile',
          trailing: components.isEmpty ? null : '${_fmtKcal(totalKcal)} kcal',
        ),
        const SizedBox(height: GainerSpacing.xs),
        GainerGroupedSection(
          footer: 'Änderungen ändern keine bereits eingetragenen Mahlzeiten.',
          children: [
            for (final component in components)
              _componentRow(context, setDialogState, components, component),
            _addComponentRow(setDialogState, components),
          ],
        ),
      ],
    );
  }

  Widget _componentRow(
    BuildContext context,
    StateSetter setDialogState,
    List<ReusableMealComponent> components,
    ReusableMealComponent component,
  ) {
    void remove() => setDialogState(
      () => components.removeWhere(
        (item) => item.componentId == component.componentId,
      ),
    );
    Future<bool> confirmRemove() => confirmGainerDelete(
      context,
      title: 'Bestandteil entfernen?',
      message: '„${component.name}“ wird aus dem Gericht entfernt.',
      deleteLabel: 'Entfernen',
    );
    return GainerSwipeToDelete(
      dismissKey: ValueKey('meal-component-swipe-${component.componentId}'),
      label: 'Entfernen',
      confirm: confirmRemove,
      onDeleted: remove,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () async {
          final action = await showGainerActionSheet<_EntryAction>(
            context: context,
            title: component.name,
            groups: [
              if (components.length > 1)
                const [
                  GainerSheetAction(
                    label: 'Verschieben',
                    icon: CupertinoIcons.arrow_up_arrow_down,
                    value: _EntryAction.move,
                  ),
                ],
              const [
                GainerSheetAction(
                  label: 'Entfernen',
                  icon: CupertinoIcons.trash,
                  value: _EntryAction.remove,
                  destructive: true,
                ),
              ],
            ],
          );
          if (!context.mounted) return;
          switch (action) {
            case _EntryAction.move:
              final ids = await showGainerSheet<List<String>>(
                context: context,
                builder: (_) => _ReorderSheet(
                  title: 'Bestandteile anordnen',
                  items: [
                    for (final item in components)
                      (id: item.componentId, title: item.name),
                  ],
                ),
              );
              if (ids == null) return;
              final byId = {
                for (final item in components) item.componentId: item,
              };
              setDialogState(() {
                final ordered = [for (final id in ids) byId[id]!];
                components
                  ..clear()
                  ..addAll(ordered);
              });
            case _EntryAction.remove:
              if (await confirmRemove()) remove();
            case null:
          }
        },
        child: GainerListRow(
          key: ValueKey('meal-component-${component.componentId}'),
          title: component.name,
          value:
              '${_fmtGrams(component.amountGrams)} g · ${_fmtKcal(component.totals.kilocalories)} kcal',
          onTap: () => _editComponent(component, components, setDialogState),
        ),
      ),
    );
  }

  Widget _addComponentRow(
    StateSetter setDialogState,
    List<ReusableMealComponent> components,
  ) => _AddRow(
    key: const ValueKey('meal-component-add'),
    label: 'Bestandteil hinzufügen',
    onPressed: components.length >= 50
        ? null
        : () => _addComponent(components, setDialogState),
  );

  /// Öffnet denselben Dialog wie bei Mahlzeiten, aber mit Ziel Gerichtsentwurf.
  Future<void> _addComponent(
    List<ReusableMealComponent> components,
    StateSetter setDialogState,
  ) async {
    final draft = await _openEntry(target: const MealDraftTarget());
    if (draft == null || !mounted) return;
    try {
      final component = draft.toComponent(
        componentId: widget.viewModel.repository.ids(),
        position: components.length,
      );
      setDialogState(() => components.add(component));
    } catch (error) {
      widget.viewModel.reportInputError(
        error.toString(),
        operation: NutritionErrorOperation.planning,
      );
    }
  }

  /// Bearbeitet einen Bestandteil des Entwurfs in einem Sheet mit denselben
  /// Feldern wie die manuelle Erfassung.
  Future<void> _editComponent(
    ReusableMealComponent component,
    List<ReusableMealComponent> components,
    StateSetter setDialogState,
  ) async {
    final c = _IngredientControllers.fromComponent(component);
    try {
      final updated = await showGainerSheet<FoodComponentDraft>(
        context: context,
        heightFactor: 0.9,
        builder: (sheetContext) => StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final draft = _draftFrom(c, source: component.source);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GainerSheetHeader(
                  title: 'Bestandteil bearbeiten',
                  trailing: GainerPillButton(
                    label: 'Sichern',
                    onPressed: draft.validate() == null
                        ? () => Navigator.of(sheetContext).pop(draft)
                        : null,
                  ),
                ),
                Expanded(
                  child: ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(
                      GainerSpacing.m,
                      GainerSpacing.m,
                      GainerSpacing.m,
                      GainerSpacing.l,
                    ),
                    children: _foodFormGroups(
                      name: c.name,
                      brand: c.brand,
                      amount: c.amount,
                      kcal: c.kcal,
                      protein: c.protein,
                      carbs: c.carbs,
                      fat: c.fat,
                      nameKey: const ValueKey('meal-component-name'),
                      amountKey: const ValueKey('meal-component-amount'),
                      kcalKey: const ValueKey('meal-component-kcal'),
                      onChanged: (_) => setSheetState(() {}),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
      if (updated == null || !mounted) return;
      final index = components.indexWhere(
        (item) => item.componentId == component.componentId,
      );
      if (index < 0) return;
      setDialogState(
        () => components[index] = updated.toComponent(
          componentId: component.componentId,
          position: index,
        ),
      );
    } catch (error) {
      widget.viewModel.reportInputError(
        error.toString(),
        operation: NutritionErrorOperation.planning,
      );
    } finally {
      c.dispose();
    }
  }

  ReusableMeal _reusableMealFromDraft({
    required TextEditingController name,
    required TextEditingController description,
    required TextEditingController portion,
    required List<ReusableMealComponent> components,
  }) => ReusableMeal(
    name: name.text,
    description: description.text.trim().isEmpty ? null : description.text,
    standardPortion: _parse(portion.text)!,
    components: [
      for (var index = 0; index < components.length; index++)
        ReusableMealComponent(
          componentId: components[index].componentId,
          position: index,
          name: components[index].name,
          brand: components[index].brand,
          amountGrams: components[index].amountGrams,
          per100Grams: components[index].per100Grams,
          source: components[index].source,
        ),
    ],
  );

  bool _canSaveRecipe(
    TextEditingController name,
    TextEditingController portion,
    List<ReusableMealComponent> components,
  ) =>
      name.text.trim().isNotEmpty &&
      (_parse(portion.text) ?? 0) >= .01 &&
      (_parse(portion.text) ?? 101) <= 100 &&
      components.isNotEmpty &&
      components.length <= 50;

  Future<void> _addReusableMeal(String id, ReusableMeal meal) async {
    final scale = TextEditingController(text: _grams(meal.standardPortion));
    try {
      final accepted = await showGainerSheet<bool>(
        context: context,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) {
            final portion = _parse(scale.text);
            final valid = (portion ?? 0) >= .01 && (portion ?? 101) <= 100;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GainerSheetHeader(title: '${meal.name} übernehmen'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    GainerSpacing.m,
                    GainerSpacing.m,
                    GainerSpacing.m,
                    0,
                  ),
                  child: GainerGroupedSection(
                    children: [
                      GainerTextFieldRow(
                        label: 'Portionen',
                        unit: '×',
                        controller: scale,
                        keyboardType: _decimalKeyboard,
                        onChanged: (_) => setSheetState(() {}),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: GainerSpacing.m),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: GainerSpacing.m,
                  ),
                  child: GainerPillButton(
                    label: 'Übernehmen',
                    expand: true,
                    onPressed: valid
                        ? () => Navigator.of(sheetContext).pop(true)
                        : null,
                  ),
                ),
                const SizedBox(height: GainerSpacing.m),
              ],
            );
          },
        ),
      );
      if (accepted == true && mounted) {
        await widget.viewModel.addReusableMeal(
          id,
          widget.viewModel.selectedMeal,
          portionScale: _parse(scale.text),
        );
      }
    } finally {
      scale.dispose();
    }
  }

  Future<void> _editTargetPhase({NutritionTargetVersion? existing}) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final from = TextEditingController(
      text: existing?.effectiveFrom ?? widget.viewModel.localDate,
    );
    final until = TextEditingController(text: existing?.effectiveUntil ?? '');
    final kcal = TextEditingController(
      text: existing == null ? '2000' : _grams(existing.kilocalories),
    );
    final protein = TextEditingController(
      text: existing == null
          ? '25'
          : _targetPart(existing, NutritionTargetInputMode.percent, 0),
    );
    final carbs = TextEditingController(
      text: existing == null
          ? '50'
          : _targetPart(existing, NutritionTargetInputMode.percent, 1),
    );
    final fat = TextEditingController(
      text: existing == null
          ? '25'
          : _targetPart(existing, NutritionTargetInputMode.percent, 2),
    );
    final draft = _TargetPhaseDraft(
      category: existing?.category ?? NutritionTargetCategory.custom,
      mode: existing?.inputMode ?? NutritionTargetInputMode.percent,
    );
    final c = _TargetPhaseControllers(
      name: name,
      from: from,
      until: until,
      kcal: kcal,
      protein: protein,
      carbs: carbs,
      fat: fat,
    );
    try {
      final fields = await Navigator.of(context)
          .push<
            ({NutritionTargetCategory category, NutritionTargetInputMode mode})
          >(
            CupertinoPageRoute<
              ({
                NutritionTargetCategory category,
                NutritionTargetInputMode mode,
              })
            >(
              builder: (context) => StatefulBuilder(
                builder: (context, setDialogState) => _targetPhasePage(
                  context,
                  setDialogState,
                  existing,
                  c,
                  draft,
                ),
              ),
            ),
          );
      if (fields == null || !mounted) return;
      NutritionTotals totals;
      if (fields.mode == NutritionTargetInputMode.percent) {
        totals = macroGramsFromPercent(
          kilocalories: _parse(kcal.text)!,
          proteinPercent: _parse(protein.text)!,
          carbohydratePercent: _parse(carbs.text)!,
          fatPercent: _parse(fat.text)!,
        );
      } else {
        totals = NutritionTotals(
          kilocalories: _parse(kcal.text)!,
          proteinGrams: _parse(protein.text)!,
          carbohydrateGrams: _parse(carbs.text)!,
          fatGrams: _parse(fat.text)!,
        );
      }
      final phase = NutritionTargetVersion(
        targetVersionId:
            existing?.targetVersionId ?? widget.viewModel.repository.ids(),
        name: name.text,
        category: fields.category,
        effectiveFrom: from.text.trim(),
        effectiveUntil: until.text.trim().isEmpty ? null : until.text.trim(),
        inputMode: fields.mode,
        kilocalories: _parse(kcal.text)!,
        proteinGrams: totals.proteinGrams!,
        carbohydrateGrams: totals.carbohydrateGrams!,
        fatGrams: totals.fatGrams!,
        proteinPercent: fields.mode == NutritionTargetInputMode.percent
            ? _parse(protein.text)
            : null,
        carbohydratePercent: fields.mode == NutritionTargetInputMode.percent
            ? _parse(carbs.text)
            : null,
        fatPercent: fields.mode == NutritionTargetInputMode.percent
            ? _parse(fat.text)
            : null,
        origin: existing?.origin ?? 'Manual',
        algorithmVersion: existing?.algorithmVersion,
        reason: existing?.reason,
      );
      await widget.viewModel.saveTargetPhase(
        phase,
        closeOpenPreviousPhase: true,
        update: existing != null,
      );
    } catch (error) {
      widget.viewModel.reportInputError(
        error.toString(),
        operation: NutritionErrorOperation.planning,
      );
    } finally {
      c.dispose();
    }
  }

  Widget _targetPhasePage(
    BuildContext context,
    StateSetter setDialogState,
    NutritionTargetVersion? existing,
    _TargetPhaseControllers c,
    _TargetPhaseDraft draft,
  ) {
    void refresh() => setDialogState(() {});
    final percent = draft.mode == NutritionTargetInputMode.percent;
    return _FormPage(
      title: existing == null ? 'Zielphase hinzufügen' : 'Zielphase bearbeiten',
      closeKey: const ValueKey('nutrition-target-close'),
      onSave:
          _validTargetInput(
            c.name,
            c.from,
            c.until,
            c.kcal,
            c.protein,
            c.carbs,
            c.fat,
            draft.mode,
          )
          ? () => Navigator.pop(context, (
              category: draft.category,
              mode: draft.mode,
            ))
          : null,
      children: [
        GainerGroupedSection(
          children: [
            GainerTextFieldRow(
              label: 'Name',
              controller: c.name,
              onChanged: (_) => refresh(),
            ),
            GainerTextFieldRow(
              label: 'Gültig ab',
              placeholder: 'JJJJ-MM-TT',
              controller: c.from,
              onChanged: (_) => refresh(),
            ),
            GainerTextFieldRow(
              label: 'Gültig bis',
              placeholder: 'Optional',
              controller: c.until,
              onChanged: (_) => refresh(),
            ),
            GainerTextFieldRow(
              label: 'Kalorien pro Tag',
              unit: 'kcal',
              controller: c.kcal,
              keyboardType: _decimalKeyboard,
              onChanged: (_) => refresh(),
            ),
          ],
        ),
        const SizedBox(height: GainerSpacing.m),
        GainerGroupedSection(
          children: [
            GainerListRow(
              title: 'Kategorie',
              value: _categoryName(draft.category),
              showChevron: true,
              onTap: () async {
                final selected = await _chooseCategory();
                if (selected != null) {
                  setDialogState(() => draft.category = selected);
                }
              },
            ),
            GainerListRow(
              title: 'Makroeingabe',
              value: percent ? 'Prozent (4/4/9)' : 'Gramm',
              showChevron: true,
              onTap: () => setDialogState(
                () => draft.mode = percent
                    ? NutritionTargetInputMode.grams
                    : NutritionTargetInputMode.percent,
              ),
            ),
          ],
        ),
        const SizedBox(height: GainerSpacing.m),
        GainerGroupedSection(
          footer: percent
              ? 'Prozentanteile müssen zusammen 100 % ergeben; Gramm werden mit 4/4/9 kcal berechnet.'
              : null,
          children: [
            GainerTextFieldRow(
              label: 'Protein',
              unit: percent ? '%' : 'g',
              controller: c.protein,
              keyboardType: _decimalKeyboard,
              onChanged: (_) => refresh(),
            ),
            GainerTextFieldRow(
              label: 'Kohlenhydrate',
              unit: percent ? '%' : 'g',
              controller: c.carbs,
              keyboardType: _decimalKeyboard,
              onChanged: (_) => refresh(),
            ),
            GainerTextFieldRow(
              label: 'Fett',
              unit: percent ? '%' : 'g',
              controller: c.fat,
              keyboardType: _decimalKeyboard,
              onChanged: (_) => refresh(),
            ),
          ],
        ),
      ],
    );
  }

  bool _validTargetInput(
    TextEditingController name,
    TextEditingController from,
    TextEditingController until,
    TextEditingController kcal,
    TextEditingController protein,
    TextEditingController carbs,
    TextEditingController fat,
    NutritionTargetInputMode mode,
  ) {
    final numbers = [
      _parse(kcal.text),
      _parse(protein.text),
      _parse(carbs.text),
      _parse(fat.text),
    ];
    final percentagesValid =
        mode != NutritionTargetInputMode.percent ||
        (numbers.skip(1).every((value) => value != null) &&
            (numbers[1]! + numbers[2]! + numbers[3]! - 100).abs() <= .01);
    return name.text.trim().isNotEmpty &&
        isValidLocalDate(from.text.trim()) &&
        (until.text.trim().isEmpty || isValidLocalDate(until.text.trim())) &&
        numbers.every((value) => value != null && value >= 0) &&
        (numbers.first ?? 0) > 0 &&
        percentagesValid;
  }

  Future<T?> _chooseFromSheet<T>({
    required String title,
    required List<({String label, IconData icon, T value})> options,
  }) => showGainerActionSheet<T>(
    context: context,
    title: title,
    groups: [
      [
        for (final option in options)
          GainerSheetAction<T>(
            label: option.label,
            icon: option.icon,
            value: option.value,
          ),
      ],
    ],
  );

  Future<NutritionTargetCategory?> _chooseCategory() =>
      _chooseFromSheet<NutritionTargetCategory>(
        title: 'Zielkategorie',
        options: [
          for (final category in NutritionTargetCategory.values)
            (
              label: _categoryName(category),
              icon: _categoryIcon(category),
              value: category,
            ),
        ],
      );

  Future<bool> _confirmRemoveTargetPhase(
    NutritionTargetVersion phase,
  ) => confirmGainerDelete(
    context,
    title: 'Zielphase entfernen?',
    message:
        'Die Phase „${phase.name}“ wird aus dem lokalen Plan entfernt. Bereits abgeschlossene Tage bleiben unverändert.',
    deleteLabel: 'Entfernen',
  );

  Future<void> _addManual(
    FoodAddTarget target,
    ValueChanged<FoodComponentDraft> onDraft,
  ) async {
    final amount = _parse(_amount.text);
    final kcal = _parse(_kcal.text);
    if (amount == null || kcal == null) {
      widget.viewModel.reportInputError(
        'Menge und Kalorien müssen gültige Zahlen sein.',
        operation: NutritionErrorOperation.entry,
      );
      return;
    }
    switch (target) {
      case DayMealTarget():
        await widget.viewModel.addManualEntry(
          productName: _name.text,
          brand: _brand.text.trim().isEmpty ? null : _brand.text,
          amountGrams: amount,
          kilocaloriesPer100Grams: kcal,
          proteinGramsPer100: _nullable(_protein.text),
          carbohydrateGramsPer100: _nullable(_carbs.text),
          fatGramsPer100: _nullable(_fat.text),
        );
        if (widget.viewModel.errorMessage == null) {
          _name.clear();
          _brand.clear();
        }
      case MealDraftTarget():
        final accepted = _commitDraft(
          FoodComponentDraft(
            name: _name.text,
            brand: _brand.text.trim().isEmpty ? null : _brand.text,
            amountGrams: amount,
            per100Grams: NutritionTotals(
              kilocalories: kcal,
              proteinGrams: _nullable(_protein.text),
              carbohydrateGrams: _nullable(_carbs.text),
              fatGrams: _nullable(_fat.text),
            ),
            source: null,
          ),
          onDraft,
        );
        if (accepted) {
          for (final controller in [
            _name,
            _brand,
            _kcal,
            _protein,
            _carbs,
            _fat,
          ]) {
            controller.clear();
          }
        }
    }
  }

  Future<void> _scanLabel() async {
    final consent = await _confirm(
      title: 'Etikett fotografieren',
      message: 'Das Bild wird zur Nährwerterkennung an den Gainer-Dienst gesendet. Es wird nicht lokal gespeichert. Du kannst den Vorschlag danach prüfen oder verwerfen.',
      accept: 'Fortfahren',
    );
    if (consent != true || !mounted) return;
    final useCamera = await _chooseCaptureSource();
    if (useCamera == null || !mounted) return;
    final upload = await _confirm(
      title: 'Nährwerte online erkennen',
      message: 'Das Etikettbild wird einmalig hochgeladen. Nichts wird automatisch ins Tagebuch übernommen.',
      accept: 'Einmalig hochladen',
    );
    if (upload != true || !mounted) return;
    await widget.viewModel.scanLabel(
      photoConsentConfirmed: true,
      uploadConsentConfirmed: true,
      useCamera: useCamera,
    );
    if (mounted && widget.viewModel.labelDraft != null) {
      await _reviewLabelDraft();
    }
  }

  Future<void> _reviewLabelDraft() async {
    final draft = widget.viewModel.labelDraft!;
    final name = TextEditingController();
    final amount = TextEditingController(text: '100');
    final recipeName = TextEditingController();
    final target = _LabelTargetDraft();
    try {
      final accepted = await Navigator.of(context).push<String>(
        CupertinoPageRoute<String>(
          builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => _labelDraftPage(
              context,
              setDialogState,
              draft,
              name: name,
              amount: amount,
              recipeName: recipeName,
              target: target,
            ),
          ),
        ),
      );
      if (accepted == 'diary' && mounted) {
        await widget.viewModel.confirmLabelDraft(
          productName: name.text,
          amountGrams: _parse(amount.text) ?? 0,
        );
      } else if (accepted == 'meal' && mounted) {
        await widget.viewModel.confirmLabelAsReusableMeal(
          productName: name.text,
          amountGrams: _parse(amount.text) ?? 0,
          mealName: recipeName.text.trim().isEmpty
              ? name.text
              : recipeName.text,
        );
      } else {
        widget.viewModel.discardLabelDraft();
      }
    } finally {
      name.dispose();
      amount.dispose();
      recipeName.dispose();
    }
  }

  Widget _labelDraftPage(
    BuildContext context,
    StateSetter setDialogState,
    NutritionLabelScanDraft draft, {
    required TextEditingController name,
    required TextEditingController amount,
    required TextEditingController recipeName,
    required _LabelTargetDraft target,
  }) {
    void refresh() => setDialogState(() {});
    return _FormPage(
      title: 'Vorschlag prüfen',
      closeKey: const ValueKey('nutrition-label-close'),
      closeLabel: 'Verwerfen',
      onSave:
          draft.confirmedPer100Grams == null ||
              name.text.trim().isEmpty ||
              _parse(amount.text) == null
          ? null
          : () => Navigator.pop(context, target.value),
      children: [
        GainerGroupedSection(
          header:
              'Erkannt${draft.servingMassGrams == null ? '' : ' · ${draft.servingMassGrams} g pro Portion'}',
          footer: 'Prüfe alle Werte. Der Scan allein speichert nichts.',
          children: [
            GainerListRow(title: 'Basis', value: draft.basis),
            GainerListRow(
              title: 'Kalorien',
              value:
                  '${draft.kilocalories.per100Grams ?? _notRecognizedLabel} kcal / 100 g',
            ),
            GainerListRow(
              title: 'Protein',
              value:
                  '${draft.proteinGrams.per100Grams ?? _notRecognizedLabel} g',
            ),
            GainerListRow(
              title: 'Kohlenhydrate',
              value:
                  '${draft.carbohydrateGrams.per100Grams ?? _notRecognizedLabel} g',
            ),
            GainerListRow(
              title: 'Fett',
              value: '${draft.fatGrams.per100Grams ?? _notRecognizedLabel} g',
            ),
          ],
        ),
        const SizedBox(height: GainerSpacing.m),
        GainerGroupedSection(
          children: [
            GainerTextFieldRow(
              label: 'Produktname',
              controller: name,
              onChanged: (_) => refresh(),
            ),
            GainerTextFieldRow(
              label: 'Menge',
              unit: 'g',
              controller: amount,
              keyboardType: _decimalKeyboard,
              onChanged: (_) => refresh(),
            ),
          ],
        ),
        const SizedBox(height: GainerSpacing.m),
        GainerGroupedSection(
          children: [
            GainerListRow(
              title: 'Speicherziel',
              value: target.value == 'diary'
                  ? 'Tagebucheintrag'
                  : 'Gespeichertes Gericht',
              showChevron: true,
              onTap: () async {
                final choice = await _chooseTarget();
                if (choice != null) {
                  setDialogState(() => target.value = choice);
                }
              },
            ),
            if (target.value == 'meal')
              GainerTextFieldRow(
                label: 'Gerichtsname',
                placeholder: 'Optional',
                controller: recipeName,
              ),
          ],
        ),
      ],
    );
  }

  Future<String?> _chooseTarget() => _chooseFromSheet<String>(
    title: 'Speicherziel auswählen',
    options: const [
      (label: 'Tagebucheintrag', icon: CupertinoIcons.book, value: 'diary'),
      (
        label: 'Neues gespeichertes Gericht',
        icon: CupertinoIcons.square_stack_3d_up,
        value: 'meal',
      ),
    ],
  );

  Future<void> _captureMealEstimate() async {
    final consent = await _confirm(
      title: 'Mahlzeit fotografieren',
      message: 'Das Bild wird einmalig zur Schätzung an den Gainer-Dienst gesendet. Es wird nicht lokal gespeichert. Der Vorschlag landet erst nach deiner Prüfung im Tagebuch.',
      accept: 'Fortfahren',
    );
    if (consent != true || !mounted) return;
    final useCamera = await _chooseCaptureSource();
    if (useCamera == null || !mounted) return;
    final upload = await _confirm(
      title: 'Bild einmalig hochladen',
      message: 'Die Bildanalyse ist unverbindlich. Prüfe jeden erkannten Bestandteil.',
      accept: 'Hochladen',
    );
    if (upload != true || !mounted) return;
    await widget.viewModel.estimateMealFromImage(
      photoConsentConfirmed: true,
      uploadConsentConfirmed: true,
      useCamera: useCamera,
    );
  }

  Future<bool?> _chooseCaptureSource() => _chooseFromSheet<bool>(
    title: 'Bild auswählen',
    options: const [
      (
        label: 'Fotomediathek',
        icon: CupertinoIcons.photo_on_rectangle,
        value: false,
      ),
      (label: 'Kamera', icon: CupertinoIcons.camera, value: true),
    ],
  );

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String accept,
    bool destructive = false,
  }) => showGainerStackedDialog<bool>(
    context: context,
    title: title,
    message: message,
    actions: [
      const GainerDialogAction(label: 'Abbrechen', value: false),
      GainerDialogAction(label: accept, value: true, destructive: destructive),
    ],
  );
}

IconData _mealIcon(NutritionMeal meal) => switch (meal) {
  NutritionMeal.breakfast => CupertinoIcons.sunrise,
  NutritionMeal.lunch => CupertinoIcons.sun_max,
  NutritionMeal.dinner => CupertinoIcons.moon,
  NutritionMeal.snacks => CupertinoIcons.square_grid_2x2,
};

IconData _categoryIcon(NutritionTargetCategory category) => switch (category) {
  NutritionTargetCategory.custom => CupertinoIcons.slider_horizontal_3,
  NutritionTargetCategory.cut => CupertinoIcons.minus_circle,
  NutritionTargetCategory.maintenance => CupertinoIcons.equal_circle,
  NutritionTargetCategory.bulk => CupertinoIcons.plus_circle,
};

const _decimalKeyboard = TextInputType.numberWithOptions(decimal: true);

Widget _notice(BuildContext context, String text, {bool isError = false}) {
  final colors = GainerDesign.colorsOf(context);
  final tone = isError ? colors.destructive : colors.accent;
  return Container(
    margin: const EdgeInsets.symmetric(vertical: 6),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: tone.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(GainerRadii.field),
    ),
    child: Text(
      text,
      style: GainerTypography.body.copyWith(
        color: isError ? colors.destructive : colors.primaryText,
      ),
    ),
  );
}

/// Felder eines Lebensmittels als zwei gruppierte Karten (Stammdaten und
/// Nährwerte pro 100 g). Gemeinsam genutzt von manueller Erfassung, Eintrags-
/// und Bestandteilbearbeitung.
List<Widget> _foodFormGroups({
  required TextEditingController name,
  required TextEditingController brand,
  required TextEditingController amount,
  required TextEditingController kcal,
  required TextEditingController protein,
  required TextEditingController carbs,
  required TextEditingController fat,
  Key? nameKey,
  Key? brandKey,
  Key? amountKey,
  Key? kcalKey,
  ValueChanged<String>? onChanged,
}) => [
  GainerGroupedSection(
    children: [
      GainerTextFieldRow(
        label: 'Name',
        placeholder: 'Lebensmittel',
        controller: name,
        fieldKey: nameKey,
        onChanged: onChanged,
      ),
      GainerTextFieldRow(
        label: 'Marke',
        placeholder: 'Optional',
        controller: brand,
        fieldKey: brandKey,
        onChanged: onChanged,
      ),
      GainerTextFieldRow(
        label: 'Menge',
        unit: 'g',
        controller: amount,
        keyboardType: _decimalKeyboard,
        fieldKey: amountKey,
        onChanged: onChanged,
      ),
    ],
  ),
  const SizedBox(height: GainerSpacing.m),
  GainerGroupedSection(
    header: 'Nährwerte pro 100 g',
    children: [
      GainerTextFieldRow(
        label: 'Kalorien',
        unit: 'kcal',
        controller: kcal,
        keyboardType: _decimalKeyboard,
        fieldKey: kcalKey,
        onChanged: onChanged,
      ),
      GainerTextFieldRow(
        label: 'Protein',
        unit: 'g',
        controller: protein,
        keyboardType: _decimalKeyboard,
        onChanged: onChanged,
      ),
      GainerTextFieldRow(
        label: 'Kohlenhydrate',
        unit: 'g',
        controller: carbs,
        keyboardType: _decimalKeyboard,
        onChanged: onChanged,
      ),
      GainerTextFieldRow(
        label: 'Fett',
        unit: 'g',
        controller: fat,
        keyboardType: _decimalKeyboard,
        onChanged: onChanged,
      ),
    ],
  ),
];

/// Baut aus den Bearbeitungsfeldern einen (noch ungeprüften) Draft.
FoodComponentDraft _draftFrom(
  _IngredientControllers c, {
  NutritionSource? source,
}) => FoodComponentDraft(
  name: c.name.text,
  brand: c.brand.text.trim().isEmpty ? null : c.brand.text,
  amountGrams: _parse(c.amount.text) ?? 0,
  per100Grams: NutritionTotals(
    kilocalories: _parse(c.kcal.text) ?? 0,
    proteinGrams: _nullable(c.protein.text),
    carbohydrateGrams: _nullable(c.carbs.text),
    fatGrams: _nullable(c.fat.text),
  ),
  source: source,
);

/// Formularseite im Look der Sheets: X links, Titel, „Sichern“-Pille rechts
/// (aktiv, sobald [onSave] gesetzt ist). Das X schließt ohne Ergebnis.
class _FormPage extends StatelessWidget {
  const _FormPage({
    required this.title,
    required this.children,
    required this.onSave,
    this.closeKey,
    this.closeLabel = 'Schließen',
  });

  final String title;
  final List<Widget> children;
  final VoidCallback? onSave;
  final Key? closeKey;
  final String closeLabel;

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    backgroundColor: GainerDesign.colorsOf(context).background,
    child: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GainerSheetHeader(
                title: title,
                leading: GainerToolbarButton(
                  key: closeKey,
                  icon: CupertinoIcons.xmark,
                  semanticLabel: closeLabel,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                trailing: GainerPillButton(label: 'Sichern', onPressed: onSave),
              ),
              Expanded(
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(
                    GainerSpacing.m,
                    GainerSpacing.m,
                    GainerSpacing.m,
                    GainerSpacing.l,
                  ),
                  children: children,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Plus-Symbol am Zeilenende, das „Antippen übernimmt“ anzeigt.
class _AddGlyph extends StatelessWidget {
  const _AddGlyph();

  @override
  Widget build(BuildContext context) => Icon(
    CupertinoIcons.add_circled,
    size: 22,
    color: GainerDesign.colorsOf(context).accent,
  );
}

/// Zeile „+ Beschriftung“ in Akzentfarbe am Ende einer Karte.
class _AddRow extends StatelessWidget {
  const _AddRow({required this.label, required this.onPressed, super.key});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final color = onPressed == null ? colors.placeholderText : colors.accent;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: GainerSpacing.m),
            child: Row(
              children: [
                Icon(CupertinoIcons.add, size: 18, color: color),
                const SizedBox(width: GainerSpacing.xxs),
                Text(
                  label,
                  style: GainerTypography.label.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EntryEditControllers {
  _EntryEditControllers(NutritionEntry entry)
    : name = TextEditingController(text: entry.productName),
      brand = TextEditingController(text: entry.brand ?? ''),
      amount = TextEditingController(text: _grams(entry.amountGrams)),
      kcal = TextEditingController(
        text: _grams(entry.per100Grams.kilocalories),
      ),
      protein = TextEditingController(
        text: _optionalGrams(entry.per100Grams.proteinGrams),
      ),
      carbs = TextEditingController(
        text: _optionalGrams(entry.per100Grams.carbohydrateGrams),
      ),
      fat = TextEditingController(
        text: _optionalGrams(entry.per100Grams.fatGrams),
      );

  final TextEditingController name;
  final TextEditingController brand;
  final TextEditingController amount;
  final TextEditingController kcal;
  final TextEditingController protein;
  final TextEditingController carbs;
  final TextEditingController fat;

  void dispose() {
    for (final controller in [name, brand, amount, kcal, protein, carbs, fat]) {
      controller.dispose();
    }
  }
}

class _TargetPhaseDraft {
  _TargetPhaseDraft({required this.category, required this.mode});

  NutritionTargetCategory category;
  NutritionTargetInputMode mode;
}

class _TargetPhaseControllers {
  const _TargetPhaseControllers({
    required this.name,
    required this.from,
    required this.until,
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  final TextEditingController name;
  final TextEditingController from;
  final TextEditingController until;
  final TextEditingController kcal;
  final TextEditingController protein;
  final TextEditingController carbs;
  final TextEditingController fat;

  void dispose() {
    for (final controller in [name, from, until, kcal, protein, carbs, fat]) {
      controller.dispose();
    }
  }
}

class _LabelTargetDraft {
  String value = 'diary';
}

/// Tageswechsel in der Toolbar: ‹ [Datum] › in einer gemeinsamen Pille. Das
/// Datum öffnet die Datumsauswahl.
class _DayNavigator extends StatelessWidget {
  const _DayNavigator({
    required this.label,
    required this.onPrevious,
    required this.onNext,
    required this.onPick,
  });

  final String label;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    Widget arrow(IconData icon, String semanticLabel, VoidCallback onTap) =>
        Semantics(
          button: true,
          label: semanticLabel,
          excludeSemantics: true,
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size.square(GainerRadii.iconButtonDiameter),
            onPressed: onTap,
            child: Icon(icon, size: 22, color: colors.primaryText),
          ),
        );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.elevatedSurface,
        borderRadius: GainerRadii.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          arrow(CupertinoIcons.chevron_left, 'Vorheriger Tag', onPrevious),
          Semantics(
            button: true,
            label: 'Tag auswählen',
            excludeSemantics: true,
            child: CupertinoButton(
              key: const ValueKey('nutrition-date-pill'),
              padding: const EdgeInsets.symmetric(horizontal: GainerSpacing.xs),
              minimumSize: const Size(0, GainerRadii.iconButtonDiameter),
              onPressed: onPick,
              child: Text(
                label,
                style: GainerTypography.body.copyWith(
                  color: colors.primaryText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          arrow(CupertinoIcons.chevron_right, 'Nächster Tag', onNext),
        ],
      ),
    );
  }
}

/// Schmaler Fortschrittsbalken; wärmere Farbe, sobald das Ziel überschritten
/// ist.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.consumed,
    required this.target,
    this.height = 6,
  });

  final double? consumed;
  final double target;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final value = consumed ?? 0;
    final ratio = target <= 0 ? 0.0 : (value / target).clamp(0.0, 1.0);
    final exceeded = target > 0 && value > target;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: colors.elevatedSurface)),
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: constraints.maxWidth * ratio,
                  height: height,
                  child: ColoredBox(
                    color: exceeded ? colors.warning : colors.accent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Eine Tageskarte: Kalorien groß mit Fortschritt, darunter drei kompakte
/// Makro-Spalten. Ohne Ziele nur die Ist-Werte und der Weg zu den Zielen.
class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.totals,
    required this.target,
    required this.onManage,
  });

  final NutritionTotals totals;
  final NutritionTargetVersion? target;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final goal = target;
    final kcal = totals.kilocalories;
    final remaining = goal == null ? null : goal.kilocalories - kcal;
    return Semantics(
      button: true,
      label: goal == null ? 'Tagesziele festlegen' : 'Tagesziele verwalten',
      child: GestureDetector(
        key: const ValueKey('nutrition-target-card'),
        behavior: HitTestBehavior.opaque,
        onTap: onManage,
        child: GainerCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                label: 'Tageskalorien ${_fmtKcal(kcal)} Kilokalorien',
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: _fmtKcal(kcal),
                        style: GainerTypography.largeTitle.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.primaryText,
                        ),
                      ),
                      TextSpan(
                        text: goal == null
                            ? ' kcal'
                            : ' von ${_fmtKcal(goal.kilocalories)} kcal',
                        style: GainerTypography.body.copyWith(
                          color: colors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (goal != null && remaining != null) ...[
                const SizedBox(height: GainerSpacing.xs),
                _ProgressBar(consumed: kcal, target: goal.kilocalories),
                const SizedBox(height: GainerSpacing.xs),
                Text(
                  remaining >= 0
                      ? '${_fmtKcal(remaining)} übrig'
                      : '${_fmtKcal(-remaining)} über',
                  style: GainerTypography.label.copyWith(
                    color: remaining >= 0
                        ? colors.secondaryText
                        : colors.warning,
                  ),
                ),
              ],
              const SizedBox(height: GainerSpacing.m),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _macro(
                    colors,
                    'Protein',
                    totals.proteinGrams,
                    goal?.proteinGrams,
                  ),
                  const SizedBox(width: GainerSpacing.s),
                  _macro(
                    colors,
                    'Kohlenhydrate',
                    totals.carbohydrateGrams,
                    goal?.carbohydrateGrams,
                  ),
                  const SizedBox(width: GainerSpacing.s),
                  _macro(colors, 'Fett', totals.fatGrams, goal?.fatGrams),
                ],
              ),
              if (goal == null) ...[
                const SizedBox(height: GainerSpacing.m),
                Text(
                  'Tagesziele festlegen',
                  style: GainerTypography.body.copyWith(
                    color: colors.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _macro(
    GainerColors colors,
    String name,
    double? consumed,
    double? goal,
  ) {
    final actual = consumed == null ? '–' : _fmtGrams(consumed);
    return Expanded(
      child: Semantics(
        label: goal == null
            ? '$name, $actual g'
            : '$name, $actual von ${_fmtGrams(goal)} g',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GainerTypography.caption.copyWith(
                color: colors.secondaryText,
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                goal == null ? '$actual g' : '$actual / ${_fmtGrams(goal)} g',
                maxLines: 1,
                style: GainerTypography.value.copyWith(
                  color: colors.primaryText,
                ),
              ),
            ),
            if (goal != null) ...[
              const SizedBox(height: GainerSpacing.xxs),
              _ProgressBar(consumed: consumed, target: goal, height: 4),
            ],
          ],
        ),
      ),
    );
  }
}

/// Zielphase, die für [date] gilt, oder `null`.
NutritionTargetVersion? _targetFor(
  String date,
  NutritionTargetSchedule? schedule,
) => schedule?.versions
    .where(
      (phase) =>
          phase.effectiveFrom.compareTo(date) <= 0 &&
          (phase.effectiveUntil == null ||
              phase.effectiveUntil!.compareTo(date) >= 0),
    )
    .lastOrNull;

/// „Heute“, „Gestern“, „Morgen“ oder kurzes Datum wie „Mo. 12. Okt.“.
String _dateLabel(String value, String today) {
  final date = DateTime.parse(value);
  final now = DateTime.parse(today);
  final difference = DateTime.utc(
    date.year,
    date.month,
    date.day,
  ).difference(DateTime.utc(now.year, now.month, now.day)).inDays;
  if (difference == 0) return 'Heute';
  if (difference == -1) return 'Gestern';
  if (difference == 1) return 'Morgen';
  const weekdays = ['Mo.', 'Di.', 'Mi.', 'Do.', 'Fr.', 'Sa.', 'So.'];
  const months = [
    'Jan.',
    'Feb.',
    'März',
    'Apr.',
    'Mai',
    'Juni',
    'Juli',
    'Aug.',
    'Sept.',
    'Okt.',
    'Nov.',
    'Dez.',
  ];
  return '${weekdays[date.weekday - 1]} ${date.day}. ${months[date.month - 1]}';
}

enum _EntryAction { move, remove }

enum _NutritionMenuAction { planning }

/// Mahlzeit: Abschnittsüberschrift mit kcal rechts, darunter eine gruppierte
/// Karte mit einer Zeile je Eintrag. Wischen nach links löscht nach
/// Bestätigung, langes Drücken öffnet das Kontext-Sheet. Ohne Einträge zeigt
/// die Karte nur „+ Hinzufügen“.
class _MealSection extends StatelessWidget {
  const _MealSection({
    super.key,
    required this.meal,
    required this.entries,
    required this.onAdd,
    required this.onEdit,
    required this.onRemove,
    required this.onConfirmRemove,
    required this.onMoveTo,
  });
  final NutritionMeal meal;
  final List<NutritionEntry> entries;
  final VoidCallback onAdd;
  final ValueChanged<NutritionEntry> onEdit;
  final ValueChanged<NutritionEntry> onRemove;
  final Future<bool> Function(NutritionEntry entry) onConfirmRemove;
  final Future<void> Function(
    List<NutritionEntry> ordered,
    List<String> orderedIds,
  )
  onMoveTo;

  @override
  Widget build(BuildContext context) {
    final ordered = [...entries]
      ..sort((a, b) => a.position.compareTo(b.position));
    final calories = entries.fold<double>(
      0,
      (sum, entry) => sum + entry.totals.kilocalories,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GainerSectionHeader(
          title: _mealName(meal),
          trailing: '${_fmtKcal(calories)} kcal',
        ),
        const SizedBox(height: GainerSpacing.xs),
        GainerGroupedSection(
          children: [
            for (final entry in ordered) _entryRow(context, ordered, entry),
            _AddRow(
              key: ValueKey('meal-add-${meal.name}'),
              label: 'Hinzufügen',
              onPressed: onAdd,
            ),
          ],
        ),
      ],
    );
  }

  Widget _entryRow(
    BuildContext context,
    List<NutritionEntry> ordered,
    NutritionEntry entry,
  ) => GainerSwipeToDelete(
    dismissKey: ValueKey('nutrition-swipe-${entry.entryId}'),
    confirm: () => onConfirmRemove(entry),
    onDeleted: () => onRemove(entry),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _showEntryActions(context, ordered, entry),
      child: GainerListRow(
        key: ValueKey('nutrition-entry-${entry.entryId}'),
        title: entry.productName,
        value:
            '${_fmtGrams(entry.amountGrams)} g · ${_fmtKcal(entry.totals.kilocalories)} kcal',
        onTap: () => onEdit(entry),
      ),
    ),
  );

  /// Kontext-Sheet eines Eintrags: Verschieben (ab zwei Einträgen) und Entfernen.
  Future<void> _showEntryActions(
    BuildContext context,
    List<NutritionEntry> ordered,
    NutritionEntry entry,
  ) async {
    final action = await showGainerActionSheet<_EntryAction>(
      context: context,
      title: entry.productName,
      groups: [
        if (ordered.length > 1)
          const [
            GainerSheetAction(
              label: 'Verschieben',
              icon: CupertinoIcons.arrow_up_arrow_down,
              value: _EntryAction.move,
            ),
          ],
        const [
          GainerSheetAction(
            label: 'Entfernen',
            icon: CupertinoIcons.trash,
            value: _EntryAction.remove,
            destructive: true,
          ),
        ],
      ],
    );
    if (!context.mounted) return;
    switch (action) {
      case _EntryAction.move:
        final ids = await showGainerSheet<List<String>>(
          context: context,
          builder: (_) => _ReorderSheet(
            title: 'Einträge anordnen',
            items: [
              for (final item in ordered)
                (id: item.entryId, title: item.productName),
            ],
          ),
        );
        if (ids != null) await onMoveTo(ordered, ids);
      case _EntryAction.remove:
        if (await onConfirmRemove(entry)) onRemove(entry);
      case null:
    }
  }
}

/// Sheet zum Umordnen einer Liste mit Ziehgriffen. Liefert die IDs in neuer
/// Reihenfolge, bei Schließen `null`.
class _ReorderSheet extends StatefulWidget {
  const _ReorderSheet({required this.title, required this.items});

  final String title;
  final List<({String id, String title})> items;

  @override
  State<_ReorderSheet> createState() => _ReorderSheetState();
}

class _ReorderSheetState extends State<_ReorderSheet> {
  late final List<({String id, String title})> _items = [...widget.items];

  void _move(int oldIndex, int newIndex) {
    setState(() => _items.insert(newIndex, _items.removeAt(oldIndex)));
  }

  @override
  Widget build(BuildContext context) {
    final maxListHeight = MediaQuery.sizeOf(context).height * 0.6;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GainerSheetHeader(
          title: widget.title,
          trailing: GainerPillButton(
            label: 'Fertig',
            onPressed: () =>
                Navigator.of(context).pop([for (final item in _items) item.id]),
          ),
        ),
        const SizedBox(height: GainerSpacing.s),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxListHeight),
          child: CustomScrollView(
            shrinkWrap: true,
            slivers: [
              SliverReorderableList(
                itemCount: _items.length,
                onReorderItem: _move,
                itemBuilder: (context, index) =>
                    _row(context, _items[index], index),
              ),
            ],
          ),
        ),
        const SizedBox(height: GainerSpacing.m),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    ({String id, String title}) item,
    int index,
  ) {
    final colors = GainerDesign.colorsOf(context);
    return Padding(
      key: ValueKey(item.id),
      padding: const EdgeInsets.only(bottom: GainerSpacing.xs),
      child: GainerCard(
        child: Row(
          children: [
            Expanded(
              child: Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GainerTypography.cardTitle.copyWith(
                  color: colors.primaryText,
                ),
              ),
            ),
            ReorderableDragStartListener(
              index: index,
              child: Semantics(
                label: 'Ziehen zum Umordnen',
                child: Padding(
                  padding: const EdgeInsets.all(GainerSpacing.xxs),
                  child: Icon(
                    CupertinoIcons.line_horizontal_3,
                    size: 22,
                    color: colors.secondaryText,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ReusableMealAction { add, edit, archive }

/// Gespeichertes Gericht als Listenzeile. Antippen öffnet die Bearbeitung
/// (oder übernimmt das Gericht, wenn nur [onAdd] gesetzt ist). Langes Drücken
/// öffnet das Kontext-Sheet mit Übernehmen, Bearbeiten und Archivieren.
class _ReusableMealRow extends StatelessWidget {
  const _ReusableMealRow({
    required this.meal,
    required this.onAdd,
    required this.onEdit,
    required this.onArchive,
  });

  final ReusableMeal meal;
  final VoidCallback onAdd;
  final VoidCallback? onEdit;
  final VoidCallback? onArchive;

  bool get _active => meal.status == 'Active';

  @override
  Widget build(BuildContext context) {
    final tap = onEdit ?? (_active ? onAdd : null);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _showActions(context),
      child: GainerListRow(
        key: ValueKey('reusable-meal-${meal.name}'),
        title: meal.name,
        subtitle:
            '${meal.components.length} Bestandteile · Portion ${_fmtGrams(meal.standardPortion)}× · ${_active ? 'Aktiv' : 'Archiviert'}',
        showChevron: onEdit != null,
        onTap: tap,
      ),
    );
  }

  Future<void> _showActions(BuildContext context) async {
    final action = await showGainerActionSheet<_ReusableMealAction>(
      context: context,
      title: meal.name,
      groups: [
        [
          if (_active)
            const GainerSheetAction(
              label: 'Übernehmen',
              icon: CupertinoIcons.plus_square,
              value: _ReusableMealAction.add,
            ),
          if (onEdit != null)
            const GainerSheetAction(
              label: 'Bearbeiten',
              icon: CupertinoIcons.pencil,
              value: _ReusableMealAction.edit,
            ),
        ],
        [
          if (onArchive != null)
            const GainerSheetAction(
              label: 'Archivieren',
              icon: CupertinoIcons.archivebox,
              value: _ReusableMealAction.archive,
              destructive: true,
            ),
        ],
      ].where((group) => group.isNotEmpty).toList(),
    );
    if (!context.mounted) return;
    switch (action) {
      case _ReusableMealAction.add:
        onAdd();
      case _ReusableMealAction.edit:
        onEdit?.call();
      case _ReusableMealAction.archive:
        onArchive?.call();
      case null:
    }
  }
}

/// Zielphase als Listenzeile. Bearbeiten per Antippen, künftige Phasen lassen
/// sich nach links wischen und nach Bestätigung entfernen.
class _TargetPhaseRow extends StatelessWidget {
  const _TargetPhaseRow({
    super.key,
    required this.phase,
    required this.onEdit,
    required this.onDelete,
    required this.onConfirmDelete,
  });

  final NutritionTargetVersion phase;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final Future<bool> Function()? onConfirmDelete;

  @override
  Widget build(BuildContext context) {
    final row = GainerListRow(
      title: phase.name,
      subtitle:
          '${phase.effectiveFrom} – ${phase.effectiveUntil ?? 'offen'} · ${_fmtKcal(phase.kilocalories)} kcal · P ${_fmtGrams(phase.proteinGrams)} g · KH ${_fmtGrams(phase.carbohydrateGrams)} g · F ${_fmtGrams(phase.fatGrams)} g',
      showChevron: onEdit != null,
      onTap: onEdit,
    );
    final delete = onDelete;
    final confirm = onConfirmDelete;
    if (delete == null || confirm == null) return row;
    return GainerSwipeToDelete(
      dismissKey: ValueKey('target-phase-swipe-${phase.targetVersionId}'),
      label: 'Entfernen',
      confirm: confirm,
      onDeleted: delete,
      child: row,
    );
  }
}

class _IngredientControllers {
  _IngredientControllers()
    : componentId = null,
      source = null,
      name = TextEditingController(),
      brand = TextEditingController(),
      amount = TextEditingController(text: '100'),
      kcal = TextEditingController(),
      protein = TextEditingController(),
      carbs = TextEditingController(),
      fat = TextEditingController();

  _IngredientControllers.fromComponent(ReusableMealComponent component)
    : componentId = component.componentId,
      source = component.source,
      name = TextEditingController(text: component.name),
      brand = TextEditingController(text: component.brand ?? ''),
      amount = TextEditingController(text: _grams(component.amountGrams)),
      kcal = TextEditingController(
        text: _grams(component.per100Grams.kilocalories),
      ),
      protein = TextEditingController(
        text: _optionalGrams(component.per100Grams.proteinGrams),
      ),
      carbs = TextEditingController(
        text: _optionalGrams(component.per100Grams.carbohydrateGrams),
      ),
      fat = TextEditingController(
        text: _optionalGrams(component.per100Grams.fatGrams),
      );

  final String? componentId;
  final NutritionSource? source;
  final TextEditingController name;
  final TextEditingController brand;
  final TextEditingController amount;
  final TextEditingController kcal;
  final TextEditingController protein;
  final TextEditingController carbs;
  final TextEditingController fat;

  void dispose() {
    name.dispose();
    brand.dispose();
    amount.dispose();
    kcal.dispose();
    protein.dispose();
    carbs.dispose();
    fat.dispose();
  }
}

String _mealName(NutritionMeal meal) => switch (meal) {
  NutritionMeal.breakfast => 'Frühstück',
  NutritionMeal.lunch => 'Mittagessen',
  NutritionMeal.dinner => 'Abendessen',
  NutritionMeal.snacks => 'Snacks',
};
double? _parse(String input) =>
    double.tryParse(input.trim().replaceAll(',', '.'));
double? _nullable(String input) => input.trim().isEmpty ? null : _parse(input);
String _grams(double value) =>
    value.toStringAsFixed(2).replaceFirst(RegExp(r'\.00$'), '');

/// Anzeige-Format: deutsches Komma, Tausenderpunkt, keine Nullen am Ende.
String _formatNumber(double value, {int decimals = 0}) =>
    formatNutritionNumber(value, decimals: decimals);

/// Kilokalorien als ganze Zahl, z. B. `1.240`.
String _fmtKcal(double value) => _formatNumber(value);

/// Gramm mit höchstens einer Nachkommastelle, z. B. `12,5`.
String _fmtGrams(double value) => _formatNumber(value, decimals: 1);

String _mealShortName(NutritionMeal meal) => switch (meal) {
  NutritionMeal.breakfast => 'Frühstück',
  NutritionMeal.lunch => 'Mittag',
  NutritionMeal.dinner => 'Abend',
  NutritionMeal.snacks => 'Snacks',
};
String _optionalGrams(double? value) => value == null ? '' : _grams(value);
String _dateString(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
String _categoryName(NutritionTargetCategory category) => switch (category) {
  NutritionTargetCategory.custom => 'Benutzerdefiniert',
  NutritionTargetCategory.cut => 'Abnehmen',
  NutritionTargetCategory.maintenance => 'Erhalten',
  NutritionTargetCategory.bulk => 'Aufbauen',
};
String _targetPart(
  NutritionTargetVersion value,
  NutritionTargetInputMode mode,
  int index,
) {
  final percent = switch (index) {
    0 => value.proteinPercent,
    1 => value.carbohydratePercent,
    _ => value.fatPercent,
  };
  final grams = switch (index) {
    0 => value.proteinGrams,
    1 => value.carbohydrateGrams,
    _ => value.fatGrams,
  };
  return _grams(
    mode == NutritionTargetInputMode.percent ? (percent ?? 0) : grams,
  );
}
