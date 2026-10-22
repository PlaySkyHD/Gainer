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
    try {
      final result = await client.searchFoods(
        query: query,
        page: 1,
        pageSize: 20,
      );
      return List.unmodifiable(result.products.map(_food));
    } on ApiException catch (error) {
      throw mapNutritionApiException(error, operation: 'Suche');
    }
  }

  @override
  Future<NutritionFood?> lookupBarcode(String barcode) async {
    try {
      final value = await client.lookupFoodByBarcode(barcode);
      return _food(value);
    } on ApiException catch (error) {
      throw mapNutritionApiException(error, operation: 'Barcode-Abfrage');
    }
  }

  @override
  Future<MealEstimateDraft> estimateMeal(String description) async {
    try {
      final result = await client.estimateMeal(text: description);
      return _estimate(result);
    } on ApiException catch (error) {
      throw mapNutritionApiException(error, operation: 'Mahlzeitenschätzung');
    }
  }

  @override
  Future<MealEstimateDraft> estimateMealImage({
    required Uint8List image,
    required String mimeType,
  }) async {
    try {
      final result = await client.estimateMeal(
        imageBytes: image,
        imageContentType: mimeType,
        imageConsent: true,
      );
      return _estimate(result);
    } on ApiException catch (error) {
      throw mapNutritionApiException(error, operation: 'Bildanalyse');
    }
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
                saltGrams: item.saltGrams,
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
    late final ApiNutritionLabelScanResponse result;
    try {
      result = await client.scanNutritionLabel(
        imageBytes: image,
        imageContentType: mimeType,
      );
    } on ApiException catch (error) {
      throw mapNutritionApiException(error, operation: 'Etikettenanalyse');
    }
    return NutritionLabelScanDraft(
      basis: result.basis,
      servingMassGrams: result.servingMassGrams,
      kilocalories: _field(result.kilocalories),
      proteinGrams: _field(result.proteinGrams),
      carbohydrateGrams: _field(result.carbohydrateGrams),
      fatGrams: _field(result.fatGrams),
      saltGrams: result.saltGrams == null
          ? const NutritionLabelFieldDraft(
              originalValue: null,
              per100Grams: null,
              status: 'Missing',
              evidence: null,
            )
          : _field(result.saltGrams!),
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
      saltGrams: value.saltGramsPer100Grams,
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

NutritionOnlineException mapNutritionApiException(
  ApiException error, {
  required String operation,
}) {
  final detail = switch ((error.statusCode, error.code)) {
    (400, 'validation_failed') =>
      'Bitte prüfe die Eingabe und versuche es erneut.',
    (_, 'product_not_found') =>
      'Zu diesem Barcode wurde kein Produkt gefunden.',
    (_, 'product_incomplete') => 'Für dieses Produkt fehlen verwertbare Nährwerte. Wähle ein anderes Produkt oder trage die Werte manuell ein.',
    (_, 'daily_budget_exhausted') => 'Das Tageslimit für KI-Schätzungen ist erreicht. Versuche es morgen erneut.',
    (_, 'invalid_input') => 'Bitte ergänze eine Beschreibung der Mahlzeit.',
    (_, 'no_nutrition_label') => 'Auf dem Foto wurde keine Nährwerttabelle erkannt. Fotografiere die Tabelle gerade und gut lesbar.',
    (_, 'image_consent_required') =>
      'Für die Bildanalyse ist eine ausdrückliche Zustimmung erforderlich.',
    (_, 'invalid_image_size') => 'Das Bild ist leer oder größer als 8 MB.',
    (_, 'unsupported_image_format') =>
      'Verwende ein JPEG-, PNG- oder WebP-Bild.',
    (_, 'provider_rate_limited') =>
      'Der externe Dienst ist gerade ausgelastet. Versuche es später erneut.',
    (_, 'provider_timeout') => 'Der externe Dienst hat nicht rechtzeitig geantwortet. Versuche es erneut.',
    (401, _) => 'Deine Sitzung ist abgelaufen. Melde dich erneut an.',
    (422, _) => 'Der Dienst hat die Anfrage abgelehnt. Prüfe die Eingabe oder verwende die manuelle Eingabe.',
    (429, _) => 'Zu viele Anfragen. Bitte warte kurz und versuche es erneut.',
    (503, _) || (504, _) => 'Der Dienst ist vorübergehend nicht erreichbar. Deine bisherigen Einträge bleiben erhalten; versuche es erneut.',
    (_, _) => 'Die Online-Funktion ist fehlgeschlagen. Deine bisherigen Einträge bleiben erhalten; versuche es erneut.',
  };
  return NutritionOnlineException(
    operation,
    error.statusCode,
    error.code,
    detail,
  );
}

class NutritionOnlineException implements Exception {
  const NutritionOnlineException(
    this.operation,
    this.statusCode,
    this.code,
    this.detail,
  );
  final String operation;
  final int? statusCode;
  final String code;
  final String detail;

  @override
  String toString() =>
      '$operation: $detail (${statusCode == null ? '' : 'HTTP $statusCode · '}Fehlerkennung: $code)';
}
