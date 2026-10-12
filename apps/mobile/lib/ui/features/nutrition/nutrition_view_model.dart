import 'package:flutter/foundation.dart';

import '../../../data/repositories/nutrition/nutrition_repository.dart';
import '../../../domain/models/nutrition/nutrition.dart';

class NutritionViewModel extends ChangeNotifier {
  NutritionViewModel({required this.repository, required this.localDate}) {
    if (!isValidLocalDate(localDate)) {
      throw ArgumentError.value(localDate, 'localDate');
    }
  }

  final NutritionRepository repository;
  final String localDate;
  NutritionMeal selectedMeal = NutritionMeal.breakfast;
  NutritionSnapshot? snapshot;
  NutritionLabelScanDraft? labelDraft;
  MealEstimateDraft? mealEstimateDraft;
  List<NutritionFood> searchResults = const [];
  NutritionFood? barcodeFood;
  bool isLoading = false;
  bool isSaving = false;
  bool isOnlineOperation = false;
  String? errorMessage;
  String? statusMessage;

  Future<void> load() => _run(() async {
    snapshot = await repository.read(localDate);
  });

  void reportInputError(String message) {
    errorMessage = message;
    notifyListeners();
  }

  void selectMeal(NutritionMeal meal) {
    selectedMeal = meal;
    notifyListeners();
  }

  Future<void> addManualEntry({
    required String productName,
    String? brand,
    required double amountGrams,
    required double kilocaloriesPer100Grams,
    double? proteinGramsPer100,
    double? carbohydrateGramsPer100,
    double? fatGramsPer100,
  }) => _run(() async {
    final current = snapshot ?? await repository.read(localDate);
    final position =
        current.day.entries
            .where((item) => item.meal == selectedMeal)
            .fold<int>(
              0,
              (max, item) => item.position > max ? item.position : max,
            ) +
        1;
    await repository.saveEntry(
      localDate,
      NutritionEntry(
        entryId: repository.ids(),
        meal: selectedMeal,
        position: position,
        productName: productName,
        brand: brand,
        amountGrams: amountGrams,
        per100Grams: NutritionTotals(
          kilocalories: kilocaloriesPer100Grams,
          proteinGrams: proteinGramsPer100,
          carbohydrateGrams: carbohydrateGramsPer100,
          fatGrams: fatGramsPer100,
        ),
        source: null,
      ),
    );
    snapshot = await repository.read(localDate);
    statusMessage = 'Eintrag lokal gespeichert und für den Sync vorgemerkt.';
  }, saving: true);

  Future<void> removeEntry(String entryId) => _run(() async {
    await repository.removeEntry(localDate, entryId);
    snapshot = await repository.read(localDate);
    statusMessage = 'Eintrag entfernt.';
  }, saving: true);

  Future<void> moveEntry(String entryId, NutritionMeal meal, int position) =>
      _run(() async {
        await repository.moveEntry(localDate, entryId, meal, position);
        snapshot = await repository.read(localDate);
      }, saving: true);

  Future<void> addReusableMeal(
    String id,
    NutritionMeal meal, {
    double? portionScale,
  }) => _run(() async {
    await repository.copyReusableMealToDay(
      mealId: id,
      localDate: localDate,
      meal: meal,
      portionScale: portionScale,
    );
    snapshot = await repository.read(localDate);
    statusMessage = 'Gericht als unabhängige Mahlzeit übernommen.';
  }, saving: true);

  Future<void> searchFoods(String query) => _run(() async {
    isOnlineOperation = true;
    searchResults = await repository.searchFoods(query);
    statusMessage = searchResults.isEmpty
        ? 'Keine Lebensmittel gefunden.'
        : '${searchResults.length} Lebensmittel gefunden.';
  }, saving: false);

  Future<void> lookupBarcode() => _run(() async {
    isOnlineOperation = true;
    final barcode = await repository.scanBarcode();
    if (barcode == null) return;
    barcodeFood = await repository.lookupBarcode(barcode);
    statusMessage = barcodeFood == null
        ? 'Kein Produkt zu diesem Barcode gefunden.'
        : 'Produkt gefunden: ${barcodeFood!.name}. Bitte Menge prüfen und eintragen.';
  }, saving: false);

  Future<void> estimateMeal(String description) => _run(() async {
    isOnlineOperation = true;
    mealEstimateDraft = await repository.estimateMeal(description);
    statusMessage = mealEstimateDraft!.components.isEmpty
        ? 'Keine Bestandteile erkannt.'
        : 'Schätzung prüfen. Es wurde noch nichts gespeichert.';
  }, saving: false);

  Future<void> estimateMealFromImage({
    required bool photoConsentConfirmed,
    required bool uploadConsentConfirmed,
    required bool useCamera,
  }) => _run(() async {
    isOnlineOperation = true;
    final image = await repository.captureLabelImage(
      photoConsentConfirmed: photoConsentConfirmed,
      useCamera: useCamera,
    );
    if (image == null) {
      statusMessage = 'Aufnahme abgebrochen.';
      return;
    }
    mealEstimateDraft = await repository.estimateCapturedMeal(
      review: image,
      uploadConsentConfirmed: uploadConsentConfirmed,
    );
    statusMessage = 'Schätzung prüfen. Es wurde noch nichts gespeichert.';
  });

  Future<void> addFood(NutritionFood food, {required double amountGrams}) =>
      _run(() async {
        final current = snapshot ?? await repository.read(localDate);
        final position =
            current.day.entries
                .where((item) => item.meal == selectedMeal)
                .fold<int>(
                  0,
                  (max, item) => item.position > max ? item.position : max,
                ) +
            1;
        await repository.saveEntry(
          localDate,
          NutritionEntry(
            entryId: repository.ids(),
            meal: selectedMeal,
            position: position,
            productName: food.name,
            brand: food.brand,
            amountGrams: amountGrams,
            per100Grams: food.per100Grams,
            source: food.source,
          ),
        );
        snapshot = await repository.read(localDate);
        statusMessage =
            'Lebensmittel-Snapshot gespeichert und für den Sync vorgemerkt.';
      }, saving: true);

  Future<void> confirmEstimatedComponent(int componentIndex) async {
    final draft = mealEstimateDraft;
    if (draft == null ||
        componentIndex < 0 ||
        componentIndex >= draft.components.length) {
      throw StateError('Die Schätzung ist nicht verfügbar.');
    }
    final item = draft.components[componentIndex];
    if (item.amountGrams <= 0 || item.totals.kilocalories <= 0) {
      throw StateError(
        'Der Schätzwert ist nicht gültig und muss manuell ergänzt werden.',
      );
    }
    final per100 = calculatePer100Totals(
      amountGrams: item.amountGrams,
      totals: item.totals,
    );
    await _run(() async {
      final current = snapshot ?? await repository.read(localDate);
      final position =
          current.day.entries
              .where((entry) => entry.meal == selectedMeal)
              .fold<int>(
                0,
                (max, entry) => entry.position > max ? entry.position : max,
              ) +
          1;
      await repository.saveEntry(
        localDate,
        NutritionEntry(
          entryId: repository.ids(),
          meal: selectedMeal,
          position: position,
          productName: item.name,
          brand: null,
          amountGrams: item.amountGrams,
          per100Grams: per100,
          source: NutritionSource(
            provider: draft.provider,
            retrievedAtUtc: draft.estimatedAtUtc,
            basisGrams: item.amountGrams,
          ),
        ),
      );
      snapshot = await repository.read(localDate);
      mealEstimateDraft = null;
      statusMessage = 'Geprüfte Schätzung als Eintrag gespeichert.';
      notifyListeners();
    }, saving: true);
  }

  void discardEstimate() {
    mealEstimateDraft = null;
    statusMessage = 'Schätzung verworfen; es wurde nichts gespeichert.';
    notifyListeners();
  }

  Future<void> scanLabel({
    required bool photoConsentConfirmed,
    required bool uploadConsentConfirmed,
    required bool useCamera,
  }) => _run(() async {
    isOnlineOperation = true;
    final image = await repository.captureLabelImage(
      photoConsentConfirmed: photoConsentConfirmed,
      useCamera: useCamera,
    );
    if (image == null) {
      statusMessage = 'Aufnahme abgebrochen.';
      return;
    }
    labelDraft = await repository.scanCapturedLabel(
      review: image,
      uploadConsentConfirmed: uploadConsentConfirmed,
    );
    statusMessage =
        'Nährwertvorschlag prüfen. Es wurde noch nichts gespeichert.';
  });

  Future<void> confirmLabelDraft({
    required String productName,
    required double amountGrams,
    String? brand,
  }) async {
    final draft = labelDraft;
    final nutrients = draft?.confirmedPer100Grams;
    if (draft == null || nutrients == null) {
      throw StateError('Der Labelscan kann nicht bestätigt werden.');
    }
    await _run(() async {
      final current = snapshot ?? await repository.read(localDate);
      final position =
          current.day.entries
              .where((item) => item.meal == selectedMeal)
              .fold<int>(
                0,
                (max, item) => item.position > max ? item.position : max,
              ) +
          1;
      await repository.saveEntry(
        localDate,
        NutritionEntry(
          entryId: repository.ids(),
          meal: selectedMeal,
          position: position,
          productName: productName,
          brand: brand,
          amountGrams: amountGrams,
          per100Grams: nutrients,
          source: NutritionSource(
            provider: draft.provider,
            retrievedAtUtc: draft.scannedAtUtc,
            basisGrams: 100,
          ),
        ),
      );
      snapshot = await repository.read(localDate);
      labelDraft = null;
      statusMessage = 'Eintrag lokal gespeichert und für den Sync vorgemerkt.';
    }, saving: true);
  }

  Future<String?> confirmLabelAsReusableMeal({
    required String productName,
    required double amountGrams,
    required String mealName,
  }) async {
    final draft = labelDraft;
    final per100 = draft?.confirmedPer100Grams;
    if (draft == null || per100 == null) {
      throw StateError('Der Labelscan kann nicht bestätigt werden.');
    }
    String? id;
    await _run(() async {
      final source = NutritionSource(
        provider: draft.provider,
        retrievedAtUtc: draft.scannedAtUtc,
        basisGrams: 100,
      );
      id = await repository.saveReusableMeal(
        ReusableMeal(
          name: mealName,
          description: 'Aus geprüftem Nährwertetikett',
          standardPortion: 1,
          components: [
            ReusableMealComponent(
              componentId: repository.ids(),
              position: 0,
              name: productName,
              brand: null,
              amountGrams: amountGrams,
              per100Grams: per100,
              source: source,
            ),
          ],
        ),
      );
      snapshot = await repository.read(localDate);
      labelDraft = null;
      statusMessage =
          'Gericht lokal gespeichert. Es wurde kein Ernährungstag geändert.';
    }, saving: true);
    return id;
  }

  void discardLabelDraft() {
    labelDraft = null;
    statusMessage = 'Vorschlag verworfen; es wurde nichts gespeichert.';
    notifyListeners();
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool saving = false,
  }) async {
    isLoading = !saving;
    isSaving = saving;
    isOnlineOperation = false;
    errorMessage = null;
    statusMessage = null;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      errorMessage = _messageFor(error);
    } finally {
      isLoading = false;
      isSaving = false;
      isOnlineOperation = false;
      notifyListeners();
    }
  }

  String _messageFor(Object error) =>
      error is StateError && error.message.contains('Onlineverbindung')
      ? '${error.message} Bitte später erneut versuchen.'
      : error.toString();
}
