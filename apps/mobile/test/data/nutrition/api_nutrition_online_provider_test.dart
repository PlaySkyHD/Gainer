import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/nutrition/api_nutrition_online_provider.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';

void main() {
  test(
    'nutrition 422 feedback stays localized and preserves operation/code',
    () {
      final failure = mapNutritionApiException(
        const ApiException(
          statusCode: 422,
          code: 'validation_failed',
          message: 'The request cannot be processed.',
        ),
        operation: 'Mahlzeitenschätzung',
      );

      expect(failure.statusCode, 422);
      expect(failure.code, 'validation_failed');
      expect(failure.toString(), contains('Mahlzeitenschätzung'));
      expect(failure.toString(), contains('Fehlerkennung: validation_failed'));
      expect(
        failure.toString(),
        isNot(contains('The request cannot be processed')),
      );
    },
  );

  test('a photo without a nutrition table explains how to retake it', () {
    final failure = mapNutritionApiException(
      const ApiException(
        statusCode: 422,
        code: 'no_nutrition_label',
        message: 'No nutrition table was found in the photo.',
      ),
      operation: 'Etikettenanalyse',
    );

    expect(failure.toString(), contains('keine Nährwerttabelle erkannt'));
  });

  test('barcode not found gives a manual-entry path', () {
    final failure = mapNutritionApiException(
      const ApiException(
        statusCode: 404,
        code: 'product_not_found',
        message: 'The requested resource was not found.',
      ),
      operation: 'Barcode-Abfrage',
    );

    expect(failure.toString(), contains('Zu diesem Barcode'));
    expect(failure.toString(), contains('Barcode-Abfrage'));
  });
}
