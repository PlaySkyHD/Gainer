import 'package:flutter/cupertino.dart';

import '../../../data/repositories/nutrition/nutrition_repository.dart';
import '../../../domain/models/nutrition/nutrition.dart';
import '../../core/theme.dart';
import 'nutrition_view_model.dart';

const _foodNameLabel = 'Lebensmittel *';
const _amountRequiredLabel = 'Menge (g) *';
const _kcalRequiredLabel = 'kcal / 100 g *';
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
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('Ernährung')),
        child: SafeArea(
          child: Column(
            children: [
              if (vm.errorMessage != null &&
                  vm.errorOperation == NutritionErrorOperation.diary)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: _notice(context, vm.errorMessage!, isError: true),
                  ),
                ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      children: [
                        _heading(context, _friendlyDate(vm.localDate)),
                        Row(
                          children: [
                            CupertinoButton(
                              minimumSize: const Size(48, 48),
                              onPressed: () => _shiftDay(-1),
                              child: const Icon(CupertinoIcons.chevron_left),
                            ),
                            const Expanded(
                              child: Center(child: Text('Ernährungstagebuch')),
                            ),
                            CupertinoButton(
                              minimumSize: const Size(48, 48),
                              onPressed: () => _shiftDay(1),
                              child: const Icon(CupertinoIcons.chevron_right),
                            ),
                            CupertinoButton(
                              minimumSize: const Size(48, 48),
                              onPressed: () => _pickDay(context),
                              child: const Icon(CupertinoIcons.calendar),
                            ),
                          ],
                        ),
                        if (vm.errorMessage != null &&
                            vm.errorOperation ==
                                NutritionErrorOperation.day) ...[
                          _notice(context, vm.errorMessage!, isError: true),
                          _button(
                            'Tagebuch erneut laden',
                            vm.load,
                            icon: CupertinoIcons.refresh,
                          ),
                        ],
                        if (snapshot == null && vm.isLoading)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 18),
                            child: Center(child: CupertinoActivityIndicator()),
                          ),
                        if (snapshot != null)
                          ..._dayChildren(context, vm, snapshot),
                        if (vm.isSaving || vm.isOnlineOperation)
                          const Padding(
                            padding: EdgeInsets.all(12),
                            child: Center(child: CupertinoActivityIndicator()),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  List<Widget> _dayChildren(
    BuildContext context,
    NutritionViewModel vm,
    NutritionSnapshot snapshot,
  ) => [
    _TotalsCard(totals: snapshot.day.totals),
    const SizedBox(height: 10),
    _MacroSummary(totals: snapshot.day.totals),
    const SizedBox(height: 10),
    _TargetProgress(
      date: vm.localDate,
      totals: snapshot.day.totals,
      schedule: snapshot.targetSchedule,
      onManage: _openPlanning,
    ),
    const SizedBox(height: 10),
    _button(
      'Lebensmittel hinzufügen',
      _openEntry,
      key: const ValueKey('nutrition-add-food'),
      filled: true,
      icon: CupertinoIcons.add,
    ),
    if (vm.statusMessage != null)
      Semantics(liveRegion: true, child: _notice(context, vm.statusMessage!)),
    const SizedBox(height: 8),
    _heading(context, 'Mahlzeiten'),
    for (final meal in NutritionMeal.values)
      _MealSection(
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
        onMove: (entry, targetPosition) =>
            vm.moveEntry(entry.entryId, entry.meal, targetPosition),
      ),
    const SizedBox(height: 8),
    _button(
      'Gerichte und Ziele verwalten',
      _openPlanning,
      key: const ValueKey('nutrition-open-planning'),
      icon: CupertinoIcons.slider_horizontal_3,
    ),
  ];

  Future<void> _openEntry() {
    final vm = widget.viewModel;
    vm.dismissActionError();
    var mode = _NutritionEntryMode.choices;
    return Navigator.of(context).push<void>(
      CupertinoPageRoute<void>(
        builder: (routeContext) => StatefulBuilder(
          builder: (routeContext, setRouteState) => CupertinoPageScaffold(
            navigationBar: CupertinoNavigationBar(
              middle: Text(mode.title),
              leading: _entryLeading(
                routeContext,
                mode,
                onBack: () => setRouteState(() {
                  vm.dismissActionError();
                  mode = _NutritionEntryMode.choices;
                }),
              ),
            ),
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: AnimatedBuilder(
                    animation: vm,
                    builder: (context, _) => ListView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                      children: [
                        if (mode == _NutritionEntryMode.choices)
                          ..._choiceChildren(
                            context,
                            vm,
                            (option) => setRouteState(() => mode = option),
                          )
                        else
                          ..._entryChildren(context, vm, mode),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _entryLeading(
    BuildContext routeContext,
    _NutritionEntryMode mode, {
    required VoidCallback onBack,
  }) => CupertinoButton(
    key: ValueKey(
      mode == _NutritionEntryMode.choices
          ? 'nutrition-entry-close'
          : 'nutrition-entry-options',
    ),
    padding: EdgeInsets.zero,
    minimumSize: const Size(48, 48),
    onPressed: mode == _NutritionEntryMode.choices
        ? () => Navigator.pop(routeContext)
        : onBack,
    child: Text(mode == _NutritionEntryMode.choices ? 'Abbrechen' : 'Optionen'),
  );

  List<Widget> _choiceChildren(
    BuildContext context,
    NutritionViewModel vm,
    ValueChanged<_NutritionEntryMode> onSelectMode,
  ) => [
    _heading(context, _mealName(vm.selectedMeal)),
    _rowButton(
      context,
      title: 'Mahlzeit',
      value: _mealName(vm.selectedMeal),
      onPressed: _chooseMeal,
    ),
    for (final option in _NutritionEntryMode.values.where(
      (item) => item != _NutritionEntryMode.choices,
    ))
      CupertinoListTile(
        key: ValueKey('nutrition-mode-${option.name}'),
        leading: Icon(option.icon),
        title: Text(option.title),
        subtitle: Text(
          option.description,
          style: TextStyle(color: GainerTheme.secondaryText(context)),
        ),
        trailing: const CupertinoListTileChevron(),
        onTap: () => onSelectMode(option),
      ),
  ];

  List<Widget> _entryChildren(
    BuildContext context,
    NutritionViewModel vm,
    _NutritionEntryMode mode,
  ) => [
    if (vm.errorMessage != null &&
        vm.errorOperation != null &&
        vm.errorOperation != NutritionErrorOperation.day)
      _notice(context, vm.errorMessage!, isError: true),
    if (vm.statusMessage != null)
      Semantics(liveRegion: true, child: _notice(context, vm.statusMessage!)),
    _rowButton(
      context,
      title: 'Mahlzeit',
      value: _mealName(vm.selectedMeal),
      onPressed: _chooseMeal,
    ),
    ..._entryTools(context, vm, mode),
    if (vm.isSaving || vm.isOnlineOperation)
      const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CupertinoActivityIndicator()),
      ),
  ];

  List<Widget> _entryTools(
    BuildContext context,
    NutritionViewModel vm,
    _NutritionEntryMode mode,
  ) {
    final amount = _field(
      context,
      _amount,
      'Menge (g)',
      numeric: true,
      key: const ValueKey('nutrition-entry-amount'),
    );
    final manual = <Widget>[
      _field(
        context,
        _name,
        _foodNameLabel,
        action: TextInputAction.next,
        key: const ValueKey('nutrition-entry-name'),
      ),
      _field(context, _brand, 'Marke (optional)', action: TextInputAction.next),
      _field(
        context,
        _amount,
        _amountRequiredLabel,
        numeric: true,
        key: const ValueKey('nutrition-entry-amount'),
      ),
      _field(
        context,
        _kcal,
        _kcalRequiredLabel,
        numeric: true,
        key: const ValueKey('nutrition-entry-kcal'),
      ),
      _field(context, _protein, 'Protein g / 100 g', numeric: true),
      _field(context, _carbs, 'Kohlenhydrate g / 100 g', numeric: true),
      _field(context, _fat, 'Fett g / 100 g', numeric: true),
      _button(
        'Manuell speichern',
        _addManual,
        key: const ValueKey('nutrition-entry-save'),
        filled: true,
        icon: CupertinoIcons.add,
        enabled: !vm.isSaving,
      ),
    ];
    return switch (mode) {
      _NutritionEntryMode.manual => manual,
      _NutritionEntryMode.recent => _recentTools(context, vm, amount),
      _NutritionEntryMode.meals => _mealTools(vm),
      _NutritionEntryMode.search => _searchTools(context, vm, amount),
      _NutritionEntryMode.barcode => _barcodeTools(context, vm, amount),
      _NutritionEntryMode.estimate => _estimateTools(context, vm),
      _NutritionEntryMode.label => [
        _button(
          'Nährwertetikett erfassen',
          _scanLabel,
          icon: CupertinoIcons.doc_text_viewfinder,
          enabled: !vm.isOnlineOperation,
        ),
      ],
      _NutritionEntryMode.choices => const [],
    };
  }

  List<Widget> _recentTools(
    BuildContext context,
    NutritionViewModel vm,
    Widget amount,
  ) => [
    amount,
    if (vm.snapshot?.recentFoods.isEmpty ?? true)
      const Text('Noch keine zuletzt verwendeten Lebensmittel.'),
    for (final food in vm.snapshot?.recentFoods ?? const <NutritionFood>[])
      _dataRow(
        context,
        title: food.name,
        detail:
            '${food.brand ?? food.source.provider ?? 'Lebensmittel'} · ${_grams(food.per100Grams.kilocalories)} kcal / 100 g',
        actionLabel: 'Zuletzt verwendetes Lebensmittel übernehmen',
        actionIcon: CupertinoIcons.add_circled,
        onAction: () =>
            vm.addFood(food, amountGrams: _parse(_amount.text) ?? 100),
      ),
  ];

  List<Widget> _mealTools(NutritionViewModel vm) => [
    if (vm.snapshot?.meals
            .where((item) => item.value.status == 'Active')
            .isEmpty ??
        true)
      const Text('Noch keine gespeicherten Gerichte.'),
    for (final meal in vm.snapshot?.meals ?? const [])
      if (meal.value.status == 'Active')
        _ReusableMealRow(
          meal: meal.value,
          onAdd: () => _addReusableMeal(meal.id, meal.value),
          onEdit: null,
          onArchive: null,
        ),
  ];

  List<Widget> _searchTools(
    BuildContext context,
    NutritionViewModel vm,
    Widget amount,
  ) => [
    amount,
    _field(
      context,
      _search,
      'Produkt oder Marke',
      key: const ValueKey('nutrition-entry-search'),
      action: TextInputAction.search,
      helper: 'Online-Ergebnisse vor dem Übernehmen prüfen.',
      onSubmitted: (query) => _searchFoods(vm, query),
    ),
    _button(
      'Suchen',
      () => _searchFoods(vm, _search.text),
      icon: CupertinoIcons.search,
      enabled: !vm.isOnlineOperation,
    ),
    for (final food in vm.searchResults)
      _dataRow(
        context,
        title: food.name,
        detail:
            '${food.brand ?? food.source.provider ?? 'Lebensmittel'} · ${_grams(food.per100Grams.kilocalories)} kcal / 100 g',
        actionLabel: 'Suchergebnis mit Menge übernehmen',
        actionIcon: CupertinoIcons.add_circled,
        onAction: () =>
            vm.addFood(food, amountGrams: _parse(_amount.text) ?? 100),
      ),
  ];

  List<Widget> _barcodeTools(
    BuildContext context,
    NutritionViewModel vm,
    Widget amount,
  ) => [
    amount,
    _button(
      'Barcode scannen',
      vm.lookupBarcode,
      icon: CupertinoIcons.barcode_viewfinder,
      enabled: !vm.isOnlineOperation,
    ),
    if (vm.barcodeFood case final food?)
      _dataRow(
        context,
        title: food.name,
        detail:
            '${food.brand ?? food.source.provider ?? 'Barcode'} · ${_grams(food.per100Grams.kilocalories)} kcal / 100 g',
        actionLabel: 'Barcode-Produkt mit Menge übernehmen',
        actionIcon: CupertinoIcons.add_circled,
        onAction: () =>
            vm.addFood(food, amountGrams: _parse(_amount.text) ?? 100),
      ),
  ];

  List<Widget> _estimateTools(BuildContext context, NutritionViewModel vm) => [
    _field(
      context,
      _estimateText,
      'Mahlzeit beschreiben',
      helper: 'Vorschläge werden erst nach deiner Bestätigung gespeichert.',
    ),
    _button(
      'Mahlzeit schätzen',
      () => vm.estimateMeal(_estimateText.text),
      icon: CupertinoIcons.sparkles,
      enabled: !vm.isOnlineOperation && _estimateText.text.trim().isNotEmpty,
    ),
    _button(
      'Mahlzeit fotografieren und schätzen',
      _captureMealEstimate,
      icon: CupertinoIcons.camera,
      enabled: !vm.isOnlineOperation,
    ),
    if (vm.mealEstimateDraft case final estimate?) ...[
      _heading(context, 'Vorschlag prüfen · ${estimate.provider}'),
      for (var index = 0; index < estimate.components.length; index++)
        _dataRow(
          context,
          title: estimate.components[index].name,
          detail:
              '${estimate.components[index].amountGrams} g · ${estimate.components[index].totals.kilocalories} kcal · ${estimate.components[index].confidence}',
          actionLabel: 'Schätzwert prüfen und übernehmen',
          actionIcon: CupertinoIcons.add_circled,
          onAction: () => vm.confirmEstimatedComponent(index),
        ),
      _button('Schätzung verwerfen', vm.discardEstimate),
    ],
  ];

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
          builder: (context, _) => CupertinoPageScaffold(
            navigationBar: const CupertinoNavigationBar(
              middle: Text('Gerichte und Ziele'),
            ),
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: [
                      if (vm.errorMessage != null &&
                          vm.errorOperation == NutritionErrorOperation.planning)
                        _notice(context, vm.errorMessage!, isError: true),
                      _heading(context, 'Gespeicherte Gerichte'),
                      _button(
                        'Neues Gericht anlegen',
                        () => _editReusableMeal(),
                        icon: CupertinoIcons.add,
                      ),
                      ..._mealRows(vm),
                      const SizedBox(height: 16),
                      _heading(context, 'Zielphasen'),
                      _button(
                        'Zielphase hinzufügen',
                        () => _editTargetPhase(),
                        icon: CupertinoIcons.add,
                      ),
                      ..._targetPhaseRows(vm),
                    ],
                  ),
                ),
              ),
            ),
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
            ? () => _removeTargetPhase(phase)
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
    var selected = initial;
    final date = await showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (context) => Container(
        height: 330,
        color: CupertinoColors.systemBackground.resolveFrom(context),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Abbrechen'),
                ),
                CupertinoButton(
                  onPressed: () => Navigator.pop(context, selected),
                  child: const Text('Fertig'),
                ),
              ],
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: initial,
                maximumDate: DateTime.now().add(const Duration(days: 3650)),
                onDateTimeChanged: (value) => selected = value,
              ),
            ),
          ],
        ),
      ),
    );
    if (date != null && mounted) {
      await widget.viewModel.selectDate(_dateString(date));
    }
  }

  Future<void> _editEntry(NutritionEntry entry) async {
    final c = _EntryEditControllers(entry);
    var meal = entry.meal;
    try {
      final values = await Navigator.of(context).push<({NutritionMeal meal})>(
        CupertinoPageRoute<({NutritionMeal meal})>(
          builder: (routeContext) => AnimatedBuilder(
            animation: widget.viewModel,
            builder: (routeContext, _) => StatefulBuilder(
              builder: (routeContext, setRouteState) => CupertinoPageScaffold(
                navigationBar: CupertinoNavigationBar(
                  middle: const Text('Eintrag bearbeiten'),
                  leading: CupertinoButton(
                    key: const ValueKey('nutrition-edit-close'),
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(48, 48),
                    onPressed: () => Navigator.pop(routeContext),
                    child: const Text('Abbrechen'),
                  ),
                  trailing: _entrySaveButton(routeContext, c, entry, meal),
                ),
                child: SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: ListView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
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
              ),
            ),
          ),
        ),
      );
      if (values == null) return;
    } finally {
      c.dispose();
    }
  }

  Widget _entrySaveButton(
    BuildContext routeContext,
    _EntryEditControllers c,
    NutritionEntry entry,
    NutritionMeal meal,
  ) => CupertinoButton(
    padding: EdgeInsets.zero,
    minimumSize: const Size(48, 48),
    onPressed: _isEntryEditBlocked(c)
        ? null
        : () => _saveEntryEdit(routeContext, c, entry, meal),
    child: const Text('Sichern'),
  );

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
    _field(
      routeContext,
      c.name,
      _foodNameLabel,
      key: const ValueKey('nutrition-edit-name'),
      onChanged: (_) => refresh(),
    ),
    _field(routeContext, c.brand, 'Marke'),
    _field(
      routeContext,
      c.amount,
      _amountRequiredLabel,
      numeric: true,
      key: const ValueKey('nutrition-edit-amount'),
      onChanged: (_) => refresh(),
    ),
    _field(
      routeContext,
      c.kcal,
      _kcalRequiredLabel,
      numeric: true,
      key: const ValueKey('nutrition-edit-kcal'),
      onChanged: (_) => refresh(),
    ),
    _field(routeContext, c.protein, 'Protein / 100 g', numeric: true),
    _field(routeContext, c.carbs, 'Kohlenhydrate / 100 g', numeric: true),
    _field(routeContext, c.fat, 'Fett / 100 g', numeric: true),
    _rowButton(
      routeContext,
      title: 'Mahlzeit',
      value: _mealName(meal),
      onPressed: () async {
        final selected = await _chooseMealValue();
        if (selected != null) onMealChanged(selected);
      },
    ),
    Text(
      entry.source == null
          ? 'Manueller Eintrag'
          : 'Quelle ${entry.source!.provider ?? entry.source!.barcode ?? 'Lebensmittelkatalog'} bleibt erhalten.',
    ),
  ];

  Future<NutritionMeal?> _chooseMealValue() =>
      showCupertinoModalPopup<NutritionMeal>(
        context: context,
        builder: (context) => CupertinoActionSheet(
          title: const Text('Mahlzeit auswählen'),
          actions: [
            for (final item in NutritionMeal.values)
              CupertinoActionSheetAction(
                onPressed: () => Navigator.pop(context, item),
                child: Text(_mealName(item)),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
        ),
      );

  Future<void> _editReusableMeal({String? id, ReusableMeal? existing}) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final description = TextEditingController(
      text: existing?.description ?? '',
    );
    final portion = TextEditingController(
      text: _grams(existing?.standardPortion ?? 1),
    );
    final ingredients = <_IngredientControllers>[
      for (final item in existing?.components ?? const [])
        _IngredientControllers.fromComponent(item),
      if (existing == null) _IngredientControllers(),
    ];
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
              ingredients: ingredients,
            ),
          ),
        ),
      );
      if (save != true || !mounted) return;
      final value = _reusableMealFromDraft(
        existing: existing,
        name: name,
        description: description,
        portion: portion,
        ingredients: ingredients,
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
      for (final item in ingredients) {
        item.dispose();
      }
    }
  }

  Widget _recipeEditorPage(
    BuildContext context,
    StateSetter setDialogState, {
    required ReusableMeal? existing,
    required TextEditingController name,
    required TextEditingController description,
    required TextEditingController portion,
    required List<_IngredientControllers> ingredients,
  }) => CupertinoPageScaffold(
    navigationBar: CupertinoNavigationBar(
      middle: Text(existing == null ? 'Neues Gericht' : 'Gericht bearbeiten'),
      leading: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(48, 48),
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Abbrechen'),
      ),
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(48, 48),
        onPressed: _canSaveRecipe(name, portion, ingredients)
            ? () => Navigator.pop(context, true)
            : null,
        child: const Text('Sichern'),
      ),
    ),
    child: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              const SizedBox(height: 10),
              _field(
                context,
                name,
                'Gerichtsname *',
                onChanged: (_) => setDialogState(() {}),
              ),
              _field(
                context,
                description,
                'Beschreibung',
                onChanged: (_) => setDialogState(() {}),
              ),
              _field(
                context,
                portion,
                'Standardportion (×)',
                numeric: true,
                onChanged: (_) => setDialogState(() {}),
              ),
              ..._ingredientEditors(context, setDialogState, ingredients),
              CupertinoButton(
                minimumSize: const Size(double.infinity, 48),
                onPressed: ingredients.length >= 50
                    ? null
                    : () => setDialogState(
                        () => ingredients.add(_IngredientControllers()),
                      ),
                child: const Text('Bestandteil hinzufügen'),
              ),
              const Text(
                'Änderungen am Rezept ändern keine bereits kopierten Tagebucheinträge.',
              ),
            ],
          ),
        ),
      ),
    ),
  );

  List<Widget> _ingredientEditors(
    BuildContext context,
    StateSetter setDialogState,
    List<_IngredientControllers> ingredients,
  ) => [
    for (var i = 0; i < ingredients.length; i++) ...[
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(child: Text('Bestandteil ${i + 1}')),
          CupertinoButton(
            padding: const EdgeInsets.all(4),
            onPressed: ingredients.length == 1
                ? null
                : () => setDialogState(() => ingredients.removeAt(i).dispose()),
            child: const Icon(CupertinoIcons.minus_circle),
          ),
        ],
      ),
      _field(
        context,
        ingredients[i].name,
        _foodNameLabel,
        key: ValueKey('nutrition-recipe-component-$i-name'),
        onChanged: (_) => setDialogState(() {}),
      ),
      _field(
        context,
        ingredients[i].brand,
        'Marke (optional)',
        key: ValueKey('nutrition-recipe-component-$i-brand'),
        onChanged: (_) => setDialogState(() {}),
      ),
      _field(
        context,
        ingredients[i].amount,
        _amountRequiredLabel,
        numeric: true,
        key: ValueKey('nutrition-recipe-component-$i-amount'),
        onChanged: (_) => setDialogState(() {}),
      ),
      _field(
        context,
        ingredients[i].kcal,
        _kcalRequiredLabel,
        numeric: true,
        key: ValueKey('nutrition-recipe-component-$i-kcal'),
        onChanged: (_) => setDialogState(() {}),
      ),
      _field(
        context,
        ingredients[i].protein,
        'Protein / 100 g',
        numeric: true,
        onChanged: (_) => setDialogState(() {}),
      ),
      _field(
        context,
        ingredients[i].carbs,
        'Kohlenhydrate / 100 g',
        numeric: true,
        onChanged: (_) => setDialogState(() {}),
      ),
      _field(
        context,
        ingredients[i].fat,
        'Fett / 100 g',
        numeric: true,
        onChanged: (_) => setDialogState(() {}),
      ),
    ],
  ];

  ReusableMeal _reusableMealFromDraft({
    required ReusableMeal? existing,
    required TextEditingController name,
    required TextEditingController description,
    required TextEditingController portion,
    required List<_IngredientControllers> ingredients,
  }) {
    final oldComponents =
        existing?.components ?? const <ReusableMealComponent>[];
    return ReusableMeal(
      name: name.text,
      description: description.text.trim().isEmpty ? null : description.text,
      standardPortion: _parse(portion.text)!,
      components: [
        for (var index = 0; index < ingredients.length; index++)
          ReusableMealComponent(
            componentId:
                ingredients[index].componentId ??
                (index < oldComponents.length
                    ? oldComponents[index].componentId
                    : widget.viewModel.repository.ids()),
            position: index,
            name: ingredients[index].name.text,
            brand: ingredients[index].brand.text.trim().isEmpty
                ? null
                : ingredients[index].brand.text,
            amountGrams: _parse(ingredients[index].amount.text)!,
            per100Grams: NutritionTotals(
              kilocalories: _parse(ingredients[index].kcal.text)!,
              proteinGrams: _nullable(ingredients[index].protein.text),
              carbohydrateGrams: _nullable(ingredients[index].carbs.text),
              fatGrams: _nullable(ingredients[index].fat.text),
            ),
            source: ingredients[index].source,
          ),
      ],
    );
  }

  bool _canSaveRecipe(
    TextEditingController name,
    TextEditingController portion,
    List<_IngredientControllers> items,
  ) =>
      name.text.trim().isNotEmpty &&
      (_parse(portion.text) ?? 0) >= .01 &&
      (_parse(portion.text) ?? 101) <= 100 &&
      items.isNotEmpty &&
      items.every(
        (item) =>
            item.name.text.trim().isNotEmpty &&
            (_parse(item.amount.text) ?? 0) > 0 &&
            (_parse(item.amount.text) ?? 100001) <= 100000 &&
            (_parse(item.kcal.text) ?? 0) > 0 &&
            [
              _nullable(item.protein.text),
              _nullable(item.carbs.text),
              _nullable(item.fat.text),
            ].every((value) => value == null || value >= 0),
      );

  Future<void> _addReusableMeal(String id, ReusableMeal meal) async {
    final scale = TextEditingController(text: _grams(meal.standardPortion));
    try {
      final accepted = await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: Text('${meal.name} übernehmen'),
          content: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _field(context, scale, 'Portionen (×)', numeric: true),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed:
                  (_parse(scale.text) ?? 0) >= .01 &&
                      (_parse(scale.text) ?? 101) <= 100
                  ? () => Navigator.pop(context, true)
                  : null,
              child: const Text('Übernehmen'),
            ),
          ],
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
  ) => CupertinoPageScaffold(
    navigationBar: CupertinoNavigationBar(
      middle: Text(
        existing == null ? 'Zielphase hinzufügen' : 'Zielphase bearbeiten',
      ),
      leading: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(48, 48),
        onPressed: () => Navigator.pop(context),
        child: const Text('Abbrechen'),
      ),
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(48, 48),
        onPressed:
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
        child: const Text('Sichern'),
      ),
    ),
    child: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              const SizedBox(height: 10),
              _field(
                context,
                c.name,
                'Name *',
                onChanged: (_) => setDialogState(() {}),
              ),
              _field(
                context,
                c.from,
                'Gültig ab (JJJJ-MM-TT) *',
                onChanged: (_) => setDialogState(() {}),
              ),
              _field(
                context,
                c.until,
                'Gültig bis (optional)',
                onChanged: (_) => setDialogState(() {}),
              ),
              _field(
                context,
                c.kcal,
                'Kalorien pro Tag *',
                numeric: true,
                onChanged: (_) => setDialogState(() {}),
              ),
              _rowButton(
                context,
                title: 'Kategorie',
                value: _categoryName(draft.category),
                onPressed: () async {
                  final selected = await _chooseCategory();
                  if (selected != null) {
                    setDialogState(() => draft.category = selected);
                  }
                },
              ),
              _rowButton(
                context,
                title: 'Makroeingabe',
                value: draft.mode == NutritionTargetInputMode.percent
                    ? 'Prozent (4/4/9)'
                    : 'Gramm',
                onPressed: () async {
                  setDialogState(
                    () => draft.mode =
                        draft.mode == NutritionTargetInputMode.percent
                        ? NutritionTargetInputMode.grams
                        : NutritionTargetInputMode.percent,
                  );
                },
              ),
              _field(
                context,
                c.protein,
                draft.mode == NutritionTargetInputMode.percent
                    ? 'Protein (%)'
                    : 'Protein (g)',
                numeric: true,
                onChanged: (_) => setDialogState(() {}),
              ),
              _field(
                context,
                c.carbs,
                draft.mode == NutritionTargetInputMode.percent
                    ? 'Kohlenhydrate (%)'
                    : 'Kohlenhydrate (g)',
                numeric: true,
                onChanged: (_) => setDialogState(() {}),
              ),
              _field(
                context,
                c.fat,
                draft.mode == NutritionTargetInputMode.percent
                    ? 'Fett (%)'
                    : 'Fett (g)',
                numeric: true,
                onChanged: (_) => setDialogState(() {}),
              ),
              if (draft.mode == NutritionTargetInputMode.percent)
                const Text(
                  'Prozentanteile müssen zusammen 100 % ergeben; Gramm werden mit 4/4/9 kcal berechnet.',
                ),
            ],
          ),
        ),
      ),
    ),
  );

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

  Future<NutritionTargetCategory?> _chooseCategory() =>
      showCupertinoModalPopup<NutritionTargetCategory>(
        context: context,
        builder: (context) => CupertinoActionSheet(
          title: const Text('Zielkategorie'),
          actions: [
            for (final category in NutritionTargetCategory.values)
              CupertinoActionSheetAction(
                onPressed: () => Navigator.pop(context, category),
                child: Text(_categoryName(category)),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
        ),
      );

  Future<void> _removeTargetPhase(NutritionTargetVersion phase) async {
    final accepted = await _confirm(
      title: 'Zielphase entfernen?',
      message:
          'Die Phase „${phase.name}“ wird aus dem lokalen Plan entfernt. Bereits abgeschlossene Tage bleiben unverändert.',
      accept: 'Entfernen',
    );
    if (accepted == true && mounted) {
      await widget.viewModel.removeTargetPhase(phase.targetVersionId);
    }
  }

  Future<void> _chooseMeal() async {
    final meal = await showCupertinoModalPopup<NutritionMeal>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Mahlzeit auswählen'),
        actions: [
          for (final meal in NutritionMeal.values)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, meal),
              child: Text(_mealName(meal)),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
      ),
    );
    if (meal != null) widget.viewModel.selectMeal(meal);
  }

  Future<void> _addManual() async {
    final amount = _parse(_amount.text);
    final kcal = _parse(_kcal.text);
    if (amount == null || kcal == null) {
      widget.viewModel.reportInputError(
        'Menge und Kalorien müssen gültige Zahlen sein.',
        operation: NutritionErrorOperation.entry,
      );
      return;
    }
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
  }) => CupertinoPageScaffold(
    navigationBar: CupertinoNavigationBar(
      middle: const Text('Vorschlag prüfen'),
      leading: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(48, 48),
        onPressed: () => Navigator.pop(context, 'discard'),
        child: const Text('Verwerfen'),
      ),
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(48, 48),
        onPressed:
            draft.confirmedPer100Grams == null ||
                name.text.trim().isEmpty ||
                _parse(amount.text) == null
            ? null
            : () => Navigator.pop(context, target.value),
        child: const Text('Sichern'),
      ),
    ),
    child: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Text(
                'Basis: ${draft.basis}${draft.servingMassGrams == null ? '' : ' · ${draft.servingMassGrams} g pro Portion'}',
              ),
              Text(
                'kcal: ${draft.kilocalories.per100Grams ?? _notRecognizedLabel} / 100 g',
              ),
              Text(
                'Protein: ${draft.proteinGrams.per100Grams ?? _notRecognizedLabel} g',
              ),
              Text(
                'Kohlenhydrate: ${draft.carbohydrateGrams.per100Grams ?? _notRecognizedLabel} g',
              ),
              Text(
                'Fett: ${draft.fatGrams.per100Grams ?? _notRecognizedLabel} g',
              ),
              const SizedBox(height: 12),
              _field(
                context,
                name,
                'Produktname *',
                onChanged: (_) => setDialogState(() {}),
              ),
              _field(
                context,
                amount,
                _amountRequiredLabel,
                numeric: true,
                onChanged: (_) => setDialogState(() {}),
              ),
              _rowButton(
                context,
                title: 'Speicherziel',
                value: target.value == 'diary'
                    ? 'Tagebucheintrag'
                    : 'Gespeichertes Gericht',
                onPressed: () async {
                  final choice = await _chooseTarget();
                  if (choice != null) {
                    setDialogState(() => target.value = choice);
                  }
                },
              ),
              if (target.value == 'meal')
                _field(context, recipeName, 'Gerichtsname (optional)'),
              const Text('Prüfe alle Werte. Der Scan allein speichert nichts.'),
            ],
          ),
        ),
      ),
    ),
  );

  Future<String?> _chooseTarget() => showCupertinoModalPopup<String>(
    context: context,
    builder: (context) => CupertinoActionSheet(
      title: const Text('Speicherziel auswählen'),
      actions: [
        CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context, 'diary'),
          child: const Text('Tagebucheintrag'),
        ),
        CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context, 'meal'),
          child: const Text('Neues gespeichertes Gericht'),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.pop(context),
        child: const Text('Abbrechen'),
      ),
    ),
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

  Future<bool?> _chooseCaptureSource() => showCupertinoModalPopup<bool>(
    context: context,
    builder: (context) => CupertinoActionSheet(
      title: const Text('Bild auswählen'),
      actions: [
        CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Fotomediathek'),
        ),
        CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Kamera'),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.pop(context),
        child: const Text('Abbrechen'),
      ),
    ),
  );

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String accept,
  }) => showCupertinoDialog<bool>(
    context: context,
    builder: (context) => CupertinoAlertDialog(
      title: Text(title),
      content: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(message),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Abbrechen'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(context, true),
          child: Text(accept),
        ),
      ],
    ),
  );
}

Widget _heading(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.fromLTRB(2, 20, 2, 8),
  child: Text(
    text,
    style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
  ),
);

Widget _notice(
  BuildContext context,
  String text, {
  bool isError = false,
}) => Container(
  margin: const EdgeInsets.symmetric(vertical: 6),
  padding: const EdgeInsets.all(12),
  decoration: BoxDecoration(
    color: (isError ? CupertinoColors.systemRed : CupertinoColors.systemGreen)
        .resolveFrom(context)
        .withValues(alpha: .12),
    borderRadius: BorderRadius.circular(12),
  ),
  child: Text(
    text,
    style: TextStyle(
      color: isError ? CupertinoColors.systemRed.resolveFrom(context) : null,
    ),
  ),
);

Widget _field(
  BuildContext context,
  TextEditingController controller,
  String label, {
  bool numeric = false,
  Key? key,
  String? helper,
  TextInputAction? action,
  ValueChanged<String>? onSubmitted,
  ValueChanged<String>? onChanged,
}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 5),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ExcludeSemantics(child: Text(label)),
      const SizedBox(height: 5),
      Semantics(
        label: label,
        textField: true,
        child: CupertinoTextField(
          key: key,
          controller: controller,
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(decimal: true)
              : null,
          textInputAction: action,
          onSubmitted: onSubmitted,
          onChanged: onChanged,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
              context,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      if (helper != null)
        Padding(padding: const EdgeInsets.only(top: 4), child: Text(helper)),
    ],
  ),
);

Widget _button(
  String title,
  VoidCallback? onPressed, {
  Key? key,
  IconData? icon,
  bool filled = false,
  bool enabled = true,
}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 4),
  child: Builder(
    builder: (context) => CupertinoButton(
    key: key,
    minimumSize: const Size(0, 48),
    onPressed: enabled ? onPressed : null,
    color: filled ? GainerTheme.actionColor(context) : null,
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 19, color: filled ? CupertinoColors.white : null),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: filled
                ? const TextStyle(color: CupertinoColors.white)
                : null,
          ),
        ),
      ],
    ),
  ),
  ),
);

Widget _rowButton(
  BuildContext context, {
  required String title,
  required String value,
  required VoidCallback onPressed,
}) => CupertinoButton(
  minimumSize: const Size(48, 48),
  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
  onPressed: onPressed,
  child: Row(
    children: [
      Expanded(child: Text(title, textAlign: TextAlign.left)),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.right,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      const SizedBox(width: 6),
      const Icon(CupertinoIcons.chevron_right, size: 16),
    ],
  ),
);

Widget _dataRow(
  BuildContext context, {
  required String title,
  required String detail,
  required String actionLabel,
  required IconData actionIcon,
  required VoidCallback onAction,
}) => Container(
  margin: const EdgeInsets.symmetric(vertical: 4),
  padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
  decoration: BoxDecoration(
    color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
      context,
    ),
    borderRadius: BorderRadius.circular(12),
  ),
  child: Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            const SizedBox(height: 3),
            Text(
              detail,
              style: CupertinoTheme.of(context).textTheme.textStyle
                  .copyWith(color: GainerTheme.secondaryText(context)),
            ),
          ],
        ),
      ),
      CupertinoButton(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.all(8),
        onPressed: onAction,
        child: Semantics(
          label: actionLabel,
          button: true,
          child: Icon(actionIcon),
        ),
      ),
    ],
  ),
);

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

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.totals});
  final NutritionTotals totals;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: CupertinoColors.activeBlue
          .resolveFrom(context)
          .withValues(alpha: .1),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Semantics(
      label: 'Tageskalorien ${_grams(totals.kilocalories)} Kilokalorien',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _grams(totals.kilocalories),
            style: CupertinoTheme.of(context).textTheme.navLargeTitleTextStyle
                .copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(
              'kcal heute',
              style: TextStyle(color: GainerTheme.secondaryText(context)),
            ),
          ),
        ],
      ),
    ),
  );
}

String _friendlyDate(String value) {
  final date = DateTime.parse(value);
  const weekdays = [
    'Montag',
    'Dienstag',
    'Mittwoch',
    'Donnerstag',
    'Freitag',
    'Samstag',
    'Sonntag',
  ];
  const months = [
    'Januar',
    'Februar',
    'März',
    'April',
    'Mai',
    'Juni',
    'Juli',
    'August',
    'September',
    'Oktober',
    'November',
    'Dezember',
  ];
  return '${weekdays[date.weekday - 1]}, ${date.day}. ${months[date.month - 1]}';
}

class _MacroSummary extends StatelessWidget {
  const _MacroSummary({required this.totals});
  final NutritionTotals totals;

  @override
  Widget build(BuildContext context) {
    final color = GainerTheme.secondaryText(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
          context,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _macro(context, 'Protein', totals.proteinGrams, color),
          _macro(context, 'Kohlenhydrate', totals.carbohydrateGrams, color),
          _macro(context, 'Fett', totals.fatGrams, color),
        ],
      ),
    );
  }

  Widget _macro(
    BuildContext context,
    String name,
    double? value,
    Color color,
  ) => Expanded(
    child: Column(
      children: [
        Text(
          name,
          textAlign: TextAlign.center,
          style: TextStyle(color: color, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          value == null ? '–' : '${_grams(value)} g',
          style: CupertinoTheme.of(context).textTheme.textStyle
              .copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

class _TargetProgress extends StatelessWidget {
  const _TargetProgress({
    required this.date,
    required this.totals,
    required this.schedule,
    required this.onManage,
  });

  final String date;
  final NutritionTotals totals;
  final NutritionTargetSchedule? schedule;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final target = schedule?.versions
        .where(
          (phase) =>
              phase.effectiveFrom.compareTo(date) <= 0 &&
              (phase.effectiveUntil == null ||
                  phase.effectiveUntil!.compareTo(date) >= 0),
        )
        .lastOrNull;
    return Container(
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
                  target == null ? 'Tagesziele' : 'Tagesziele · ${target.name}',
                  style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
                ),
              ),
              CupertinoButton(
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                onPressed: onManage,
                child: Text(target == null ? 'Einrichten' : 'Verwalten'),
              ),
            ],
          ),
          if (target == null)
            Text(
              'Noch keine Ziele für diesen Tag. Deine Aufnahme wird trotzdem angezeigt.',
              style: TextStyle(color: GainerTheme.secondaryText(context)),
            )
          else ...[
            _targetLine(
              context,
              'Kalorien',
              totals.kilocalories,
              target.kilocalories,
              'kcal',
            ),
            _targetLine(
              context,
              'Protein',
              totals.proteinGrams,
              target.proteinGrams,
              'g',
            ),
            _targetLine(
              context,
              'Kohlenhydrate',
              totals.carbohydrateGrams,
              target.carbohydrateGrams,
              'g',
            ),
            _targetLine(context, 'Fett', totals.fatGrams, target.fatGrams, 'g'),
          ],
        ],
      ),
    );
  }

  Widget _targetLine(
    BuildContext context,
    String label,
    double? consumed,
    double target,
    String unit,
  ) {
    final ratio = consumed == null || target <= 0
        ? 0.0
        : (consumed / target).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Semantics(
        label: consumed == null
            ? '$label, noch keine Nährwertangaben, Ziel ${_grams(target)} $unit'
            : '$label, ${_grams(consumed)} von ${_grams(target)} $unit',
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: Text(label)),
                Text(
                  '${consumed == null ? '–' : _grams(consumed)} / ${_grams(target)} $unit',
                  style: TextStyle(color: GainerTheme.secondaryText(context)),
                ),
              ],
            ),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 6,
                child: LayoutBuilder(
                  builder: (context, constraints) => Stack(
                    children: [
                      Positioned.fill(
                        child: ColoredBox(
                          color: CupertinoColors.tertiarySystemFill.resolveFrom(
                            context,
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: constraints.maxWidth * ratio,
                          child: ColoredBox(
                            color: CupertinoColors.activeBlue.resolveFrom(
                              context,
                            ),
                          ),
                        ),
                      ),
                    ],
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

class _MealSection extends StatelessWidget {
  const _MealSection({
    super.key,
    required this.meal,
    required this.entries,
    required this.onAdd,
    required this.onEdit,
    required this.onRemove,
    required this.onMove,
  });
  final NutritionMeal meal;
  final List<NutritionEntry> entries;
  final VoidCallback onAdd;
  final ValueChanged<NutritionEntry> onEdit;
  final ValueChanged<NutritionEntry> onRemove;
  final void Function(NutritionEntry entry, int targetPosition) onMove;

  Widget _entryTile(
    BuildContext context,
    List<NutritionEntry> orderedEntries,
    int index,
  ) {
    final entry = orderedEntries[index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label:
              '${entry.productName}, ${_grams(entry.amountGrams)} Gramm, ${_grams(entry.totals.kilocalories)} Kilokalorien',
          button: true,
          child: CupertinoButton(
            key: ValueKey('nutrition-entry-${entry.entryId}'),
            padding: const EdgeInsets.symmetric(vertical: 8),
            minimumSize: const Size(0, 48),
            onPressed: () => onEdit(entry),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    entry.productName,
                    textAlign: TextAlign.left,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${_grams(entry.amountGrams)} g · ${_grams(entry.totals.kilocalories)} kcal',
                  style: TextStyle(
                    color: GainerTheme.secondaryText(context),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (orderedEntries.length > 1)
          Wrap(
            spacing: 4,
            children: [
              CupertinoButton(
                key: ValueKey('nutrition-move-up-${entry.entryId}'),
                minimumSize: const Size(48, 48),
                onPressed: index == 0 ? null : () => onMove(entry, index - 1),
                child: Semantics(
                  label: '${entry.productName} nach oben',
                  button: true,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.chevron_up),
                      Text('Nach oben'),
                    ],
                  ),
                ),
              ),
              CupertinoButton(
                key: ValueKey('nutrition-move-down-${entry.entryId}'),
                minimumSize: const Size(48, 48),
                onPressed: index == orderedEntries.length - 1
                    ? null
                    : () => onMove(entry, index + 1),
                child: Semantics(
                  label: '${entry.productName} nach unten',
                  button: true,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.chevron_down),
                      Text('Nach unten'),
                    ],
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final orderedEntries = [...entries]
      ..sort((a, b) => a.position.compareTo(b.position));
    final calories = entries.fold<double>(
      0,
      (sum, entry) => sum + entry.totals.kilocalories,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
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
                  _mealName(meal),
                  style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
                ),
              ),
              Text(
                '${_grams(calories)} kcal',
                style: TextStyle(color: GainerTheme.secondaryText(context)),
              ),
            ],
          ),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Noch nichts eingetragen',
                style: TextStyle(color: GainerTheme.secondaryText(context)),
              ),
            )
          else
            for (var index = 0; index < orderedEntries.length; index++)
              Builder(
                builder: (context) =>
                    _entryTile(context, orderedEntries, index),
              ),
          Align(
            alignment: Alignment.centerLeft,
            child: CupertinoButton(
              key: ValueKey('meal-add-${meal.name}'),
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              onPressed: onAdd,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.add_circled, size: 18),
                  SizedBox(width: 6),
                  Text('Hinzufügen'),
                ],
              ),
            ),
          ),
          if (entries.isNotEmpty)
            Wrap(
              spacing: 4,
              children: [
                for (final entry in entries)
                  CupertinoButton(
                    key: ValueKey('nutrition-remove-${entry.entryId}'),
                    minimumSize: const Size(48, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    onPressed: () => onRemove(entry),
                    child: Semantics(
                      label: '${entry.productName} entfernen',
                      button: true,
                      child: const Text('Entfernen'),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

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

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 4),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
        context,
      ),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(meal.name, style: CupertinoTheme.of(context).textTheme.textStyle),
        Text(
          '${meal.components.length} Bestandteile · Portion ${_grams(meal.standardPortion)}× · ${meal.status == 'Active' ? 'Aktiv' : 'Archiviert'}',
          style: TextStyle(color: GainerTheme.secondaryText(context)),
        ),
        Wrap(
          spacing: 4,
          children: [
            CupertinoButton(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: meal.status == 'Active' ? onAdd : null,
              child: const Text('Übernehmen'),
            ),
            if (onEdit != null)
              CupertinoButton(
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                onPressed: onEdit,
                child: const Text('Bearbeiten'),
              ),
            if (onArchive != null)
              CupertinoButton(
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                onPressed: onArchive,
                child: const Text('Archivieren'),
              ),
          ],
        ),
      ],
    ),
  );
}

class _TargetPhaseRow extends StatelessWidget {
  const _TargetPhaseRow({
    super.key,
    required this.phase,
    required this.onEdit,
    required this.onDelete,
  });

  final NutritionTargetVersion phase;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 4),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
        context,
      ),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(phase.name),
        Text(
          '${phase.effectiveFrom} – ${phase.effectiveUntil ?? 'offen'} · ${_grams(phase.kilocalories)} kcal · P ${_grams(phase.proteinGrams)} g · KH ${_grams(phase.carbohydrateGrams)} g · F ${_grams(phase.fatGrams)} g',
        ),
        if (onEdit != null || onDelete != null)
          Wrap(
            spacing: 4,
            children: [
              if (onEdit != null)
                CupertinoButton(
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  onPressed: onEdit,
                  child: const Text('Bearbeiten'),
                ),
              if (onDelete != null)
                CupertinoButton(
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  onPressed: onDelete,
                  child: const Text('Entfernen'),
                ),
            ],
          ),
      ],
    ),
  );
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
