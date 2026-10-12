import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/api/api_models.dart';
import 'package:gainer_mobile/data/models/api/sync_api_models.dart';

void main() {
  test('antiforgery identity metadata remains nullable for older APIs', () {
    final olderResponse = ApiAntiforgeryToken.fromJson({
      'requestToken': 'request-token',
    });
    final authenticatedResponse = ApiAntiforgeryToken.fromJson({
      'requestToken': 'request-token',
      'authenticatedUserId': '11111111-1111-4111-8111-111111111111',
    });

    expect(olderResponse.authenticatedUserId, isNull);
    expect(
      authenticatedResponse.authenticatedUserId,
      '11111111-1111-4111-8111-111111111111',
    );
  });

  test('invitation response matches the current backend DTO exactly', () {
    final invitation = ApiInvitation.fromJson({
      'activationPath': '/accept-invitation?token=one-time-token',
      'expiresAt': '2026-10-12T12:30:00+02:00',
    });

    expect(
      invitation.activationPath,
      '/accept-invitation?token=one-time-token',
    );
    expect(invitation.expiresAt, DateTime.utc(2026, 10, 12, 10, 30));
  });

  test('session response maps existing user and operator fields', () {
    final session = ApiSession.fromJson({
      'userId': '11111111-1111-4111-8111-111111111111',
      'email': 'member@example.test',
      'isAccountOperator': true,
    });

    expect(session.userId, '11111111-1111-4111-8111-111111111111');
    expect(session.email, 'member@example.test');
    expect(session.isAccountOperator, isTrue);
  });

  test('nutrition API DTOs preserve catalog and reviewed draft fields', () {
    final food = ApiFoodProduct.fromJson({
      'barcode': '12345678',
      'productName': 'Oats',
      'brand': null,
      'basisGrams': '100',
      'kilocaloriesPer100Grams': '372.5',
      'proteinGramsPer100Grams': 13.5,
      'carbohydrateGramsPer100Grams': null,
      'fatGramsPer100Grams': '7.1',
      'qualityIndicators': ['verified'],
      'retrievedAtUtc': '2026-10-12T10:00:00+02:00',
      'isStale': false,
      'source': 'catalog',
    });
    final estimate = ApiMealEstimateResponse.fromJson({
      'components': [
        {
          'name': 'Oats',
          'amountGrams': '50',
          'kilocalories': 186,
          'proteinGrams': '6.75',
          'carbohydrateGrams': null,
          'fatGrams': 3.55,
          'confidence': 'Medium',
          'dataGaps': ['brand'],
        },
      ],
      'provider': 'test-provider',
      'schemaVersion': '1',
      'estimatedAtUtc': '2026-10-12T10:00:00Z',
    });
    final scan = ApiNutritionLabelScanResponse.fromJson({
      'basis': 'Per100Grams',
      'servingMassGrams': 30,
      'kilocalories': {
        'originalValue': 120,
        'per100Grams': 400,
        'status': 'Confirmed',
        'evidence': '120 kcal',
      },
      'proteinGrams': {
        'originalValue': 4,
        'per100Grams': 13.3,
        'status': 'Confirmed',
        'evidence': null,
      },
      'carbohydrateGrams': {
        'originalValue': null,
        'per100Grams': null,
        'status': 'Missing',
        'evidence': null,
      },
      'fatGrams': {
        'originalValue': 2,
        'per100Grams': 6.7,
        'status': 'Confirmed',
        'evidence': null,
      },
      'canConfirm': false,
      'provider': 'scanner',
      'providerModelVersion': 'model-1',
      'parserVersion': 'parser-1',
      'scannedAtUtc': '2026-10-12T10:00:00Z',
    });

    expect(food.kilocaloriesPer100Grams, 372.5);
    expect(food.retrievedAtUtc, DateTime.utc(2026, 10, 12, 8));
    expect(estimate.components.single.dataGaps, ['brand']);
    expect(scan.kilocalories.per100Grams, 400);
    expect(scan.canConfirm, isFalse);
  });

  test('sync response accepts OpenAPI numeric int or string encodings and UTC dates', () {
    final client = SyncClientRegistrationResponse.fromJson({
      'clientId': '22222222-2222-4222-8222-222222222222',
      'displayName': 'iPhone',
      'protocolVersion': '2',
      'isActiveWriter': true,
      'registeredAtUtc': '2026-10-12T10:00:00Z',
      'lastSeenAtUtc': '2026-10-12T12:00:00+02:00',
    });
    final pull = SyncPullResponse.fromJson({
      'protocolVersion': 2,
      'nextCursor': '922337',
      'hasMore': false,
      'batches': [
        {
          'batchId': '33333333-3333-4333-8333-333333333333',
          'revision': 922337,
          'originMutationId': null,
          'changes': [],
        },
      ],
    });

    expect(client.protocolVersion, 2);
    expect(client.registeredAtUtc, DateTime.utc(2026, 10, 12, 10));
    expect(client.lastSeenAtUtc, DateTime.utc(2026, 10, 12, 10));
    expect(pull.nextCursor, 922337);
    expect(pull.batches.single.changes, isEmpty);
  });

  test(
    'planned handover request preserves the current OpenSpec field names',
    () {
      expect(
        const BeginSyncHandoverRequest(
          requestId: '11111111-1111-4111-8111-111111111111',
          sourceClientId: '22222222-2222-4222-8222-222222222222',
          expectedRevision: 19,
        ).toJson(),
        {
          'requestId': '11111111-1111-4111-8111-111111111111',
          'sourceClientId': '22222222-2222-4222-8222-222222222222',
          'expectedRevision': 19,
        },
      );
      expect(
        const CompleteSyncHandoverRequest(
          oneTimeCode: 'opaque-one-time-code',
          targetClientId: '33333333-3333-4333-8333-333333333333',
          caughtUpRevision: 19,
        ).toJson(),
        {
          'oneTimeCode': 'opaque-one-time-code',
          'targetClientId': '33333333-3333-4333-8333-333333333333',
          'caughtUpRevision': 19,
        },
      );
    },
  );
}
