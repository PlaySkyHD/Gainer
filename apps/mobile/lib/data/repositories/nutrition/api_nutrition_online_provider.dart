import 'dart:typed_data';

import '../../../domain/models/nutrition/nutrition.dart';
import '../../models/api/api_models.dart';
import '../../services/api/api_client.dart';
import 'nutrition_repository.dart';

/// Maps real API responses into reviewable domain drafts; it never commits them.
class ApiNutritionOnlineProvider implements NutritionOnlineProvider {
  ApiNutritionOnlineProvider(this.client);
  final ApiClient client;

  @override
  Future<List<NutritionFood>> searchFoods(String query) async {
    final result = await client.searchFoods(
      query: query,
      page: 1,
      pageSize: 20,
    );
    return List.unmodifiable(result.products.map(_food));
  }

  @override
  Future<NutritionFood?> lookupBarcode(String barcode) async {
    final value = await client.lookupFoodByBarcode(barcode);
    return _food(value);
  }

  @override
  Future<MealEstimateDraft> estimateMeal(String description) async {
    final result = await client.estimateMeal(text: description);
    return _estimate(result);
  }

  @override
  Future<MealEstimateDraft> estimateMealImage({
    required Uint8List image,
    required String mimeType,
  }) async {
    final result = await client.estimateMeal(
      imageBytes: image,
      imageContentType: mimeType,
      imageConsent: true,
    );
    return _estimate(result);
  }

  MealEstimateDraft _estimate(ApiMealEstimateResponse result) =>
      MealEstimateDraft(
        components: List.unmodifiable(
          result.components.map(
            (item) => NutritionEstimateComponent(
              name: item.name,
              amountGrams: item.amountGrams,
              totals: NutritionTotals(
                kilocalories: item.kilocalories,
                proteinGrams: item.proteinGrams,
                carbohydrateGrams: item.carbohydrateGrams,
                fatGrams: item.fatGrams,
              ),
              confidence: item.confidence,
              dataGaps: List.unmodifiable(item.dataGaps),
            ),
          ),
        ),
        provider: result.provider,
        schemaVersion: result.schemaVersion,
        estimatedAtUtc: result.estimatedAtUtc,
      );

  @override
  Future<NutritionLabelScanDraft> scanLabel({
    required Uint8List image,
    required String mimeType,
  }) async {
    final result = await client.scanNutritionLabel(
      imageBytes: image,
      imageContentType: mimeType,
    );
    return NutritionLabelScanDraft(
      basis: result.basis,
      servingMassGrams: result.servingMassGrams,
      kilocalories: _field(result.kilocalories),
      proteinGrams: _field(result.proteinGrams),
      carbohydrateGrams: _field(result.carbohydrateGrams),
      fatGrams: _field(result.fatGrams),
      canConfirm: result.canConfirm,
      provider: result.provider,
      providerModelVersion: result.providerModelVersion,
      parserVersion: result.parserVersion,
      scannedAtUtc: result.scannedAtUtc,
    );
  }

  NutritionFood _food(ApiFoodProduct value) => NutritionFood(
    name: value.productName,
    brand: value.brand,
    per100Grams: NutritionTotals(
      kilocalories: value.kilocaloriesPer100Grams,
      proteinGrams: value.proteinGramsPer100Grams,
      carbohydrateGrams: value.carbohydrateGramsPer100Grams,
      fatGrams: value.fatGramsPer100Grams,
    ),
    source: NutritionSource(
      provider: value.source,
      barcode: value.barcode,
      retrievedAtUtc: value.retrievedAtUtc,
      basisGrams: value.basisGrams,
    ),
  );

  NutritionLabelFieldDraft _field(ApiNutritionLabelField value) =>
      NutritionLabelFieldDraft(
        originalValue: value.originalValue,
        per100Grams: value.per100Grams,
        status: value.status,
        evidence: value.evidence,
      );
}
