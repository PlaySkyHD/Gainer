import 'package:flutter/material.dart';

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
      return Scaffold(
        appBar: AppBar(title: const Text('Ernährung')),
        body: SafeArea(
          child: vm.isLoading && snapshot == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Tagesübersicht · ${vm.localDate}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    if (snapshot != null)
                      _TotalsCard(totals: snapshot.day.totals),
                    if (vm.errorMessage != null)
                      Semantics(
                        liveRegion: true,
                        child: Card(
                          color: Theme.of(context).colorScheme.errorContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(vm.errorMessage!),
                          ),
                        ),
                      ),
                    if (vm.statusMessage != null)
                      Semantics(
                        liveRegion: true,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(vm.statusMessage!),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      'Eintrag hinzufügen',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    DropdownButtonFormField<NutritionMeal>(
                      initialValue: vm.selectedMeal,
                      decoration: const InputDecoration(labelText: 'Mahlzeit'),
                      items: [
                        for (final meal in NutritionMeal.values)
                          DropdownMenuItem(
                            value: meal,
                            child: Text(_mealName(meal)),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) vm.selectMeal(value);
                      },
                    ),
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(
                        labelText: 'Lebensmittel *',
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    TextField(
                      controller: _brand,
                      decoration: const InputDecoration(
                        labelText: 'Marke (optional)',
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _amount,
                            decoration: const InputDecoration(
                              labelText: 'Menge (g) *',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _kcal,
                            decoration: const InputDecoration(
                              labelText: 'kcal / 100 g *',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _protein,
                            decoration: const InputDecoration(
                              labelText: 'Protein g / 100 g',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _carbs,
                            decoration: const InputDecoration(
                              labelText: 'Kohlenhydrate g / 100 g',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _fat,
                            decoration: const InputDecoration(
                              labelText: 'Fett g / 100 g',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: vm.isSaving ? null : _addManual,
                      icon: const Icon(Icons.add),
                      label: const Text('Manuell speichern'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _search,
                      decoration: const InputDecoration(
                        labelText: 'Online-Lebensmittelsuche',
                        helperText: 'Erfordert eine Verbindung; Ergebnisse immer prüfen.',
                      ),
                      textInputAction: TextInputAction.search,
                      onSubmitted: vm.searchFoods,
                    ),
                    for (final food in vm.searchResults)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(food.name),
                        subtitle: Text(
                          '${food.brand ?? food.source.provider ?? 'Lebensmittel'} · ${food.per100Grams.kilocalories} kcal / 100 g',
                        ),
                        trailing: IconButton(
                          tooltip: 'Lebensmittel mit Menge übernehmen',
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => vm.addFood(
                            food,
                            amountGrams: _parse(_amount.text) ?? 100,
                          ),
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: vm.isOnlineOperation ? null : vm.lookupBarcode,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Barcode scannen'),
                    ),
                    if (vm.barcodeFood case final food?)
                      ListTile(
                        title: Text(food.name),
                        subtitle: Text(
                          '${food.brand ?? food.source.provider ?? 'Barcode'} · ${food.per100Grams.kilocalories} kcal / 100 g',
                        ),
                        trailing: IconButton(
                          tooltip: 'Barcode-Produkt mit Menge übernehmen',
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => vm.addFood(
                            food,
                            amountGrams: _parse(_amount.text) ?? 100,
                          ),
                        ),
                      ),
                    TextField(
                      controller: _estimateText,
                      decoration: const InputDecoration(
                        labelText: 'Mahlzeit beschreiben',
                        helperText: 'Die Online-Schätzung ist ein Vorschlag und wird nie automatisch gespeichert.',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          vm.isOnlineOperation ||
                              _estimateText.text.trim().isEmpty
                          ? null
                          : () async {
                              await vm.estimateMeal(_estimateText.text);
                            },
                      icon: const Icon(Icons.auto_awesome_outlined),
                      label: const Text('Mahlzeit schätzen'),
                    ),
                    if (vm.mealEstimateDraft case final estimate?) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Geschätzter Vorschlag · ${estimate.provider}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      for (
                        var index = 0;
                        index < estimate.components.length;
                        index++
                      )
                        ListTile(
                          title: Text(estimate.components[index].name),
                          subtitle: Text(
                            '${estimate.components[index].amountGrams} g · ${estimate.components[index].totals.kilocalories} kcal · ${estimate.components[index].confidence} confidence',
                          ),
                          trailing: IconButton(
                            tooltip: 'Schätzwert prüfen und übernehmen',
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () =>
                                vm.confirmEstimatedComponent(index),
                          ),
                        ),
                      TextButton(
                        onPressed: vm.discardEstimate,
                        child: const Text('Schätzung verwerfen'),
                      ),
                    ],
                    OutlinedButton.icon(
                      onPressed: vm.isOnlineOperation ? null : _scanLabel,
                      icon: const Icon(Icons.document_scanner_outlined),
                      label: const Text('Nährwertetikett erfassen'),
                    ),
                    OutlinedButton.icon(
                      onPressed: vm.isOnlineOperation
                          ? null
                          : () => _captureMealEstimate(),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Mahlzeit fotografieren und schätzen'),
                    ),
                    if (snapshot?.meals.any(
                          (item) => item.value.status == 'Active',
                        ) ==
                        true) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Gespeicherte Gerichte',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      for (final meal in snapshot!.meals.where(
                        (item) => item.value.status == 'Active',
                      ))
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(meal.value.name),
                          subtitle: Text(
                            '${meal.value.components.length} Bestandteile · Portion ${meal.value.standardPortion}×',
                          ),
                          trailing: IconButton(
                            tooltip: 'Gericht zur Mahlzeit hinzufügen',
                            icon: const Icon(Icons.playlist_add),
                            onPressed: () =>
                                vm.addReusableMeal(meal.id, vm.selectedMeal),
                          ),
                        ),
                    ],
                    const SizedBox(height: 12),
                    for (final meal in NutritionMeal.values) ...[
                      Text(
                        _mealName(meal),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      ...?snapshot?.day.entries
                          .where((item) => item.meal == meal)
                          .map(
                            (entry) => Card(
                              child: ListTile(
                                title: Text(entry.productName),
                                subtitle: Text(
                                  '${_grams(entry.amountGrams)} g · ${_grams(entry.totals.kilocalories)} kcal${entry.totals.proteinGrams == null ? '' : ' · P ${_grams(entry.totals.proteinGrams!)} g'}',
                                ),
                                trailing: IconButton(
                                  tooltip: 'Eintrag entfernen',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () =>
                                      vm.removeEntry(entry.entryId),
                                ),
                              ),
                            ),
                          ),
                    ],
                    if (vm.isSaving || vm.isOnlineOperation)
                      const LinearProgressIndicator(),
                  ],
                ),
        ),
      );
    },
  );

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
    final photoConsent = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Etikett fotografieren'),
        content: const Text(
          'Das Bild wird zur Nährwerterkennung an den Gainer-Dienst gesendet. Es wird nicht lokal gespeichert. Du kannst den Vorschlag danach prüfen oder verwerfen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kamera-/Fotozugriff fortsetzen'),
          ),
        ],
      ),
    );
    if (photoConsent != true || !mounted) return;
    final useCamera = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bild auswählen'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Fotomediathek'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kamera'),
          ),
        ],
      ),
    );
    if (useCamera == null || !mounted) return;
    final uploadConsent = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nährwerte online erkennen'),
        content: const Text(
          'Das ausgewählte Etikettbild wird jetzt zur Analyse hochgeladen. Nichts wird automatisch ins Tagebuch übernommen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Einmalig hochladen'),
          ),
        ],
      ),
    );
    if (uploadConsent != true || !mounted) return;
    await widget.viewModel.scanLabel(
      photoConsentConfirmed: true,
      uploadConsentConfirmed: true,
      useCamera: useCamera,
    );
    if (!mounted || widget.viewModel.labelDraft == null) return;
    await _reviewLabelDraft();
  }

  Future<void> _reviewLabelDraft() async {
    final draft = widget.viewModel.labelDraft!;
    final name = TextEditingController();
    final amount = TextEditingController(text: '100');
    final recipeName = TextEditingController();
    var target = 'diary';
    final accepted = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nährwertvorschlag prüfen'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Produktname *'),
                ),
                TextField(
                  controller: amount,
                  decoration: const InputDecoration(labelText: 'Menge (g) *'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: target,
                  decoration: const InputDecoration(labelText: 'Speicherziel'),
                  items: const [
                    DropdownMenuItem(
                      value: 'diary',
                      child: Text('Tagebucheintrag'),
                    ),
                    DropdownMenuItem(
                      value: 'meal',
                      child: Text('Neues gespeichertes Gericht'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => target = value);
                    }
                  },
                ),
                if (target == 'meal')
                  TextField(
                    controller: recipeName,
                    decoration: const InputDecoration(
                      labelText: 'Gerichtsname (optional)',
                    ),
                  ),
                const Text(
                  'Prüfe die Werte vor dem Speichern. Der Scan allein erzeugt keinen Tagebucheintrag.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'discard'),
              child: const Text('Verwerfen'),
            ),
            FilledButton(
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
        mealName: recipeName.text.trim().isEmpty ? name.text : recipeName.text,
      );
    } else {
      widget.viewModel.discardLabelDraft();
    }
    name.dispose();
    amount.dispose();
    recipeName.dispose();
  }

  Future<void> _captureMealEstimate() async {
    final consent = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mahlzeit fotografieren'),
        content: const Text(
          'Das Bild wird einmalig zur Schätzung an den Gainer-Dienst gesendet. Es wird nicht lokal gespeichert. Der Vorschlag landet erst nach deiner Prüfung im Tagebuch.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Fortfahren'),
          ),
        ],
      ),
    );
    if (consent != true || !mounted) {
      return;
    }
    final useCamera = await _chooseCaptureSource();
    if (useCamera == null || !mounted) {
      return;
    }
    final uploadConsent = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bild einmalig hochladen'),
        content: const Text(
          'Die Bildanalyse ist eine unverbindliche Schätzung. Prüfe jeden erkannten Bestandteil.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hochladen'),
          ),
        ],
      ),
    );
    if (uploadConsent != true || !mounted) {
      return;
    }
    await widget.viewModel.estimateMealFromImage(
      photoConsentConfirmed: true,
      uploadConsentConfirmed: true,
      useCamera: useCamera,
    );
  }

  Future<bool?> _chooseCaptureSource() => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Bild auswählen'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Abbrechen'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Fotomediathek'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Kamera'),
        ),
      ],
    ),
  );
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.totals});
  final NutritionTotals totals;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 16,
        runSpacing: 6,
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
    ),
  );
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
