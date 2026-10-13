import 'package:flutter/cupertino.dart';

import '../../../domain/models/nutrition/nutrition.dart';
import 'nutrition_view_model.dart';

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
          child: vm.isLoading && snapshot == null
              ? const Center(child: CupertinoActivityIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    _heading(context, 'Tagesübersicht · ${vm.localDate}'),
                    Row(
                      children: [
                        CupertinoButton(
                          onPressed: () => _shiftDay(-1),
                          child: const Icon(CupertinoIcons.chevron_left),
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              vm.localDate,
                              style: CupertinoTheme.of(context)
                                  .textTheme
                                  .textStyle,
                            ),
                          ),
                        ),
                        CupertinoButton(
                          onPressed: () => _shiftDay(1),
                          child: const Icon(CupertinoIcons.chevron_right),
                        ),
                        CupertinoButton(
                          onPressed: () => _pickDay(context),
                          child: const Icon(CupertinoIcons.calendar),
                        ),
                      ],
                    ),
                    if (snapshot != null)
                      _TotalsCard(totals: snapshot.day.totals),
                    if (vm.errorMessage != null)
                      _notice(context, vm.errorMessage!, isError: true),
                    if (vm.statusMessage != null)
                      Semantics(
                        liveRegion: true,
                        child: _notice(context, vm.statusMessage!),
                      ),
                    _heading(context, 'Eintrag hinzufügen'),
                    _rowButton(
                      context,
                      title: 'Mahlzeit',
                      value: _mealName(vm.selectedMeal),
                      onPressed: _chooseMeal,
                    ),
                    _field(
                      context,
                      _name,
                      'Lebensmittel *',
                      action: TextInputAction.next,
                    ),
                    _field(
                      context,
                      _brand,
                      'Marke (optional)',
                      action: TextInputAction.next,
                    ),
                    _field(context, _amount, 'Menge (g) *', numeric: true),
                    _field(context, _kcal, 'kcal / 100 g *', numeric: true),
                    _field(
                      context,
                      _protein,
                      'Protein g / 100 g',
                      numeric: true,
                    ),
                    _field(
                      context,
                      _carbs,
                      'Kohlenhydrate g / 100 g',
                      numeric: true,
                    ),
                    _field(context, _fat, 'Fett g / 100 g', numeric: true),
                    _button(
                      'Manuell speichern',
                      _addManual,
                      filled: true,
                      icon: CupertinoIcons.add,
                      enabled: !vm.isSaving,
                    ),
                    const SizedBox(height: 12),
                    _field(
                      context,
                      _search,
                      'Online-Lebensmittelsuche',
                      action: TextInputAction.search,
                      helper: 'Online-Ergebnisse vor dem Übernehmen prüfen.',
                      onSubmitted: vm.searchFoods,
                    ),
                    for (final food in vm.searchResults)
                      _dataRow(
                        context,
                        title: food.name,
                        detail:
                            '${food.brand ?? food.source.provider ?? 'Lebensmittel'} · ${food.per100Grams.kilocalories} kcal / 100 g',
                        actionLabel: 'Lebensmittel mit Menge übernehmen',
                        actionIcon: CupertinoIcons.add_circled,
                        onAction: () => vm.addFood(
                          food,
                          amountGrams: _parse(_amount.text) ?? 100,
                        ),
                      ),
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
                            '${food.brand ?? food.source.provider ?? 'Barcode'} · ${food.per100Grams.kilocalories} kcal / 100 g',
                        actionLabel: 'Barcode-Produkt übernehmen',
                        actionIcon: CupertinoIcons.add_circled,
                        onAction: () => vm.addFood(
                          food,
                          amountGrams: _parse(_amount.text) ?? 100,
                        ),
                      ),
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
                      enabled:
                          !vm.isOnlineOperation &&
                          _estimateText.text.trim().isNotEmpty,
                    ),
                    if (vm.mealEstimateDraft case final estimate?) ...[
                      _heading(
                        context,
                        'Vorschlag prüfen · ${estimate.provider}',
                      ),
                      for (
                        var index = 0;
                        index < estimate.components.length;
                        index++
                      )
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
                    _button(
                      'Nährwertetikett erfassen',
                      _scanLabel,
                      icon: CupertinoIcons.doc_text_viewfinder,
                      enabled: !vm.isOnlineOperation,
                    ),
                    _button(
                      'Mahlzeit fotografieren und schätzen',
                      _captureMealEstimate,
                      icon: CupertinoIcons.camera,
                      enabled: !vm.isOnlineOperation,
                    ),
                    _heading(context, 'Gespeicherte Gerichte'),
                    _button(
                      'Neues Gericht anlegen',
                      () => _editReusableMeal(),
                      icon: CupertinoIcons.add,
                    ),
                    for (final meal in snapshot?.meals ?? const [])
                      _ReusableMealRow(
                        meal: meal.value,
                        onAdd: () => _addReusableMeal(meal.id, meal.value),
                        onEdit: meal.value.status == 'Active'
                            ? () => _editReusableMeal(
                                id: meal.id,
                                existing: meal.value,
                              )
                            : null,
                        onArchive: meal.value.status == 'Active'
                            ? () => vm.archiveReusableMeal(meal.id)
                            : null,
                      ),
                    _heading(context, 'Zielphasen'),
                    _button(
                      'Zielphase hinzufügen',
                      () => _editTargetPhase(),
                      icon: CupertinoIcons.add,
                    ),
                    for (final phase
                        in snapshot?.targetSchedule?.versions ?? const [])
                      _TargetPhaseRow(
                        key: ValueKey('target-phase-${phase.targetVersionId}'),
                        phase: phase,
                        onEdit:
                            phase.effectiveFrom.compareTo(
                                  _dateString(vm.repository.clock()),
                                ) >
                                0
                            ? () => _editTargetPhase(existing: phase)
                            : null,
                        onDelete:
                            phase.effectiveFrom.compareTo(
                                  _dateString(vm.repository.clock()),
                                ) >
                                0
                            ? () => _removeTargetPhase(phase)
                            : null,
                      ),
                    for (final meal in NutritionMeal.values) ...[
                      _heading(context, _mealName(meal)),
                      ...?snapshot?.day.entries
                          .where((item) => item.meal == meal)
                          .map(
                            (entry) => _dataRow(
                              context,
                              title: entry.productName,
                              detail:
                                  '${_grams(entry.amountGrams)} g · ${_grams(entry.totals.kilocalories)} kcal${entry.totals.proteinGrams == null ? '' : ' · P ${_grams(entry.totals.proteinGrams!)} g'}',
                              actionLabel: 'Eintrag bearbeiten',
                              actionIcon: CupertinoIcons.pencil,
                              onAction: () => _editEntry(entry),
                            ),
                          ),
                    ],
                    ...?snapshot?.day.entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: CupertinoButton(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          onPressed: () => vm.removeEntry(entry.entryId),
                          child: const Text('Eintrag entfernen'),
                        ),
                      ),
                    ),
                    if (vm.isSaving || vm.isOnlineOperation)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(child: CupertinoActivityIndicator()),
                      ),
                  ],
                ),
        ),
      );
    },
  );

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
    final name = TextEditingController(text: entry.productName);
    final brand = TextEditingController(text: entry.brand ?? '');
    final amount = TextEditingController(text: _grams(entry.amountGrams));
    final kcal = TextEditingController(
      text: _grams(entry.per100Grams.kilocalories),
    );
    final protein = TextEditingController(
      text: _optionalGrams(entry.per100Grams.proteinGrams),
    );
    final carbs = TextEditingController(
      text: _optionalGrams(entry.per100Grams.carbohydrateGrams),
    );
    final fat = TextEditingController(
      text: _optionalGrams(entry.per100Grams.fatGrams),
    );
    var meal = entry.meal;
    try {
      final values = await showCupertinoDialog<({NutritionMeal meal})>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => CupertinoAlertDialog(
            title: const Text('Tagebucheintrag bearbeiten'),
            content: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  _field(context, name, 'Lebensmittel *'),
                  _field(context, brand, 'Marke'),
                  _field(context, amount, 'Menge (g) *', numeric: true),
                  _field(context, kcal, 'kcal / 100 g *', numeric: true),
                  _field(context, protein, 'Protein / 100 g', numeric: true),
                  _field(
                    context,
                    carbs,
                    'Kohlenhydrate / 100 g',
                    numeric: true,
                  ),
                  _field(context, fat, 'Fett / 100 g', numeric: true),
                  _rowButton(
                    context,
                    title: 'Mahlzeit',
                    value: _mealName(meal),
                    onPressed: () async {
                      final selected = await _chooseMealValue();
                      if (selected != null) {
                        setDialogState(() => meal = selected);
                      }
                    },
                  ),
                  Text(
                    entry.source == null
                        ? 'Manueller Eintrag'
                        : 'Quelle ${entry.source!.provider ?? entry.source!.barcode ?? 'Lebensmittelkatalog'} bleibt erhalten.',
                  ),
                ],
              ),
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context),
                child: const Text('Abbrechen'),
              ),
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed:
                    _parse(amount.text) == null ||
                        _parse(kcal.text) == null ||
                        name.text.trim().isEmpty
                    ? null
                    : () => Navigator.pop(context, (meal: meal)),
                child: const Text('Änderungen speichern'),
              ),
            ],
          ),
        ),
      );
      if (values != null && mounted) {
        await widget.viewModel.updateEntry(
          original: entry,
          meal: values.meal,
          productName: name.text,
          brand: brand.text.trim().isEmpty ? null : brand.text,
          amountGrams: _parse(amount.text)!,
          per100Grams: NutritionTotals(
            kilocalories: _parse(kcal.text)!,
            proteinGrams: _nullable(protein.text),
            carbohydrateGrams: _nullable(carbs.text),
            fatGrams: _nullable(fat.text),
          ),
        );
      }
    } finally {
      for (final controller in [
        name,
        brand,
        amount,
        kcal,
        protein,
        carbs,
        fat,
      ]) {
        controller.dispose();
      }
    }
  }

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
      final save = await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => CupertinoAlertDialog(
            title: Text(
              existing == null ? 'Neues Gericht' : 'Gericht bearbeiten',
            ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
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
                    for (var i = 0; i < ingredients.length; i++) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: Text('Bestandteil ${i + 1}')),
                          CupertinoButton(
                            padding: const EdgeInsets.all(4),
                            onPressed: ingredients.length == 1
                                ? null
                                : () => setDialogState(
                                    () => ingredients.removeAt(i).dispose(),
                                  ),
                            child: const Icon(CupertinoIcons.minus_circle),
                          ),
                        ],
                      ),
                      _field(
                        context,
                        ingredients[i].name,
                        'Lebensmittel *',
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      _field(
                        context,
                        ingredients[i].brand,
                        'Marke (optional)',
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      _field(
                        context,
                        ingredients[i].amount,
                        'Menge (g) *',
                        numeric: true,
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      _field(
                        context,
                        ingredients[i].kcal,
                        'kcal / 100 g *',
                        numeric: true,
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
                    CupertinoButton(
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
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Abbrechen'),
              ),
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () {
                  if (_canSaveRecipe(name, portion, ingredients)) {
                    Navigator.pop(context, true);
                  }
                },
                child: const Text('Gericht speichern'),
              ),
            ],
          ),
        ),
      );
      if (save != true || !mounted) return;
      final oldComponents =
          existing?.components ?? const <ReusableMealComponent>[];
      final value = ReusableMeal(
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
      await widget.viewModel.saveReusableMeal(id: id, meal: value);
    } catch (error) {
      widget.viewModel.reportInputError(error.toString());
    } finally {
      name.dispose();
      description.dispose();
      portion.dispose();
      for (final item in ingredients) {
        item.dispose();
      }
    }
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
    var category = existing?.category ?? NutritionTargetCategory.custom;
    var mode = existing?.inputMode ?? NutritionTargetInputMode.percent;
    try {
      final fields =
          await showCupertinoDialog<
            ({NutritionTargetCategory category, NutritionTargetInputMode mode})
          >(
            context: context,
            builder: (context) => StatefulBuilder(
              builder: (context, setDialogState) => CupertinoAlertDialog(
                title: Text(
                  existing == null
                      ? 'Zielphase hinzufügen'
                      : 'Zielphase bearbeiten',
                ),
                content: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      _field(
                        context,
                        name,
                        'Name *',
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      _field(
                        context,
                        from,
                        'Gültig ab (JJJJ-MM-TT) *',
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      _field(
                        context,
                        until,
                        'Gültig bis (optional)',
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      _field(
                        context,
                        kcal,
                        'Kalorien pro Tag *',
                        numeric: true,
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      _rowButton(
                        context,
                        title: 'Kategorie',
                        value: _categoryName(category),
                        onPressed: () async {
                          final selected = await _chooseCategory();
                          if (selected != null) {
                            setDialogState(() => category = selected);
                          }
                        },
                      ),
                      _rowButton(
                        context,
                        title: 'Makroeingabe',
                        value: mode == NutritionTargetInputMode.percent
                            ? 'Prozent (4/4/9)'
                            : 'Gramm',
                        onPressed: () async {
                          setDialogState(
                            () =>
                                mode = mode == NutritionTargetInputMode.percent
                                ? NutritionTargetInputMode.grams
                                : NutritionTargetInputMode.percent,
                          );
                        },
                      ),
                      _field(
                        context,
                        protein,
                        mode == NutritionTargetInputMode.percent
                            ? 'Protein (%)'
                            : 'Protein (g)',
                        numeric: true,
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      _field(
                        context,
                        carbs,
                        mode == NutritionTargetInputMode.percent
                            ? 'Kohlenhydrate (%)'
                            : 'Kohlenhydrate (g)',
                        numeric: true,
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      _field(
                        context,
                        fat,
                        mode == NutritionTargetInputMode.percent
                            ? 'Fett (%)'
                            : 'Fett (g)',
                        numeric: true,
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      if (mode == NutritionTargetInputMode.percent)
                        const Text(
                          'Prozentanteile müssen zusammen 100 % ergeben; Gramm werden mit 4/4/9 kcal berechnet.',
                        ),
                    ],
                  ),
                ),
                actions: [
                  CupertinoDialogAction(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Abbrechen'),
                  ),
                  CupertinoDialogAction(
                    isDefaultAction: true,
                    onPressed: () {
                      if (_validTargetInput(
                        name,
                        from,
                        until,
                        kcal,
                        protein,
                        carbs,
                        fat,
                        mode,
                      )) {
                        Navigator.pop(context, (
                          category: category,
                          mode: mode,
                        ));
                      }
                    },
                    child: const Text('Zielphase speichern'),
                  ),
                ],
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
      widget.viewModel.reportInputError(error.toString());
    } finally {
      for (final controller in [name, from, until, kcal, protein, carbs, fat]) {
        controller.dispose();
      }
    }
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
    var target = 'diary';
    try {
      final accepted = await showCupertinoDialog<String>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => CupertinoAlertDialog(
            title: const Text('Nährwertvorschlag prüfen'),
            content: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Text(
                    'Basis: ${draft.basis}${draft.servingMassGrams == null ? '' : ' · ${draft.servingMassGrams} g pro Portion'}',
                  ),
                  Text(
                    'kcal: ${draft.kilocalories.per100Grams ?? 'nicht erkannt'} / 100 g',
                  ),
                  Text(
                    'Protein: ${draft.proteinGrams.per100Grams ?? 'nicht erkannt'} g',
                  ),
                  Text(
                    'Kohlenhydrate: ${draft.carbohydrateGrams.per100Grams ?? 'nicht erkannt'} g',
                  ),
                  Text(
                    'Fett: ${draft.fatGrams.per100Grams ?? 'nicht erkannt'} g',
                  ),
                  const SizedBox(height: 12),
                  _field(context, name, 'Produktname *'),
                  _field(context, amount, 'Menge (g) *', numeric: true),
                  _rowButton(
                    context,
                    title: 'Speicherziel',
                    value: target == 'diary'
                        ? 'Tagebucheintrag'
                        : 'Gespeichertes Gericht',
                    onPressed: () async {
                      final choice = await _chooseTarget();
                      if (choice != null) setDialogState(() => target = choice);
                    },
                  ),
                  if (target == 'meal')
                    _field(context, recipeName, 'Gerichtsname (optional)'),
                  const Text(
                    'Prüfe alle Werte. Der Scan allein speichert nichts.',
                  ),
                ],
              ),
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context, 'discard'),
                child: const Text('Verwerfen'),
              ),
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed:
                    draft.confirmedPer100Grams == null ||
                        name.text.trim().isEmpty ||
                        _parse(amount.text) == null
                    ? null
                    : () => Navigator.pop(context, target),
                child: Text(
                  target == 'meal' ? 'Gericht speichern' : 'Tagebuch speichern',
                ),
              ),
            ],
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
  String? helper,
  TextInputAction? action,
  ValueChanged<String>? onSubmitted,
  ValueChanged<String>? onChanged,
}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 5),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      const SizedBox(height: 5),
      CupertinoTextField(
        controller: controller,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : null,
        textInputAction: action,
        onSubmitted: onSubmitted,
        onChanged: onChanged,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
            context,
          ),
          borderRadius: BorderRadius.circular(10),
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
  IconData? icon,
  bool filled = false,
  bool enabled = true,
}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 4),
  child: CupertinoButton(
    onPressed: enabled ? onPressed : null,
    color: filled ? CupertinoColors.activeBlue : null,
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[Icon(icon, size: 19), const SizedBox(width: 8)],
        Flexible(child: Text(title, textAlign: TextAlign.center)),
      ],
    ),
  ),
);

Widget _rowButton(
  BuildContext context, {
  required String title,
  required String value,
  required VoidCallback onPressed,
}) => CupertinoButton(
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
              style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ],
        ),
      ),
      CupertinoButton(
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

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.totals});
  final NutritionTotals totals;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
        context,
      ),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        Text('${_grams(totals.kilocalories)} kcal'),
        Text(
          'Protein ${totals.proteinGrams == null ? '—' : '${_grams(totals.proteinGrams!)} g'}',
        ),
        Text(
          'Kohlenhydrate ${totals.carbohydrateGrams == null ? '—' : '${_grams(totals.carbohydrateGrams!)} g'}',
        ),
        Text(
          'Fett ${totals.fatGrams == null ? '—' : '${_grams(totals.fatGrams!)} g'}',
        ),
      ],
    ),
  );
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
          style: TextStyle(
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
        Wrap(
          spacing: 4,
          children: [
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: meal.status == 'Active' ? onAdd : null,
              child: const Text('Übernehmen'),
            ),
            if (onEdit != null)
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                onPressed: onEdit,
                child: const Text('Bearbeiten'),
              ),
            if (onArchive != null)
              CupertinoButton(
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
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  onPressed: onEdit,
                  child: const Text('Bearbeiten'),
                ),
              if (onDelete != null)
                CupertinoButton(
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
