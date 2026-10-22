import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/local/local_mutation.dart';
import 'package:gainer_mobile/data/repositories/sync/sync_payload_codec.dart';
import 'package:gainer_mobile/domain/models/nutrition/nutrition.dart';

const _aggregateId = '22222222-2222-4222-8222-222222222222';

LocalMutation _mutation(
  String type,
  LocalMutationOperation operation,
  Map<String, dynamic> body,
) => LocalMutation(
  mutationId: '33333333-3333-4333-8333-333333333333',
  accountId: '11111111-1111-4111-8111-111111111111',
  aggregateType: type,
  aggregateId: _aggregateId,
  sequence: 1,
  status: LocalMutationStatus.pending,
  createdAtUtc: DateTime.utc(2026),
  operation: operation,
  baseVersion: 1,
  body: body,
);

Map<String, dynamic> _payload(
  String type,
  LocalMutationOperation operation,
  Map<String, dynamic> body,
) =>
    SyncPayloadCodec.serverPayload(_mutation(type, operation, body), body, 1)!
        as Map<String, dynamic>;

final _entry = NutritionEntry(
  entryId: 'e1',
  meal: NutritionMeal.lunch,
  position: 0,
  productName: 'Reis',
  brand: null,
  amountGrams: 150,
  per100Grams: const NutritionTotals(kilocalories: 130, proteinGrams: 2.7),
  source: null,
);

void main() {
  test('day kind is sent only when chosen', () {
    final rest = NutritionDay(
      localDate: '2026-10-22',
      entries: const [],
      dayKind: NutritionDayKind.rest,
    ).toJson();
    expect(
      _payload('nutrition-day', LocalMutationOperation.update, rest),
      containsPair('dayKind', 'Rest'),
    );
    final automatic = NutritionDay(
      localDate: '2026-10-22',
      entries: const [],
    ).toJson();
    expect(
      _payload('nutrition-day', LocalMutationOperation.update, automatic),
      isNot(contains('dayKind')),
    );
  });

  test('server snapshots with and without day kind decode', () {
    final day = NutritionDay.fromJson({
      'nutritionDayId': _aggregateId,
      'localDate': '2026-10-22',
      'entries': <Object?>[],
      'dayKind': 'Training',
    });
    expect(day.dayKind, NutritionDayKind.training);
    expect(
      NutritionDay.fromJson({
        'localDate': '2026-10-22',
        'entries': <Object?>[],
        'dayKind': null,
      }).dayKind,
      isNull,
    );
  });

  test('rest day targets are sent only when set', () {
    NutritionTargetVersion version({NutritionDayTarget? rest}) =>
        NutritionTargetVersion(
          targetVersionId: 'v1',
          name: 'Ziele',
          category: NutritionTargetCategory.custom,
          effectiveFrom: '2026-10-22',
          effectiveUntil: null,
          inputMode: NutritionTargetInputMode.grams,
          kilocalories: 2600,
          proteinGrams: 180,
          carbohydrateGrams: 290,
          fatGrams: 80,
          proteinPercent: null,
          carbohydratePercent: null,
          fatPercent: null,
          restDay: rest,
        );
    Map<String, dynamic> firstVersion(NutritionTargetVersion value) {
      final body = NutritionTargetSchedule(versions: [value]).toJson();
      final payload = _payload(
        'nutrition-target-schedule',
        LocalMutationOperation.update,
        body.cast<String, dynamic>(),
      );
      return (payload['versions'] as List).single as Map<String, dynamic>;
    }

    final withRest = firstVersion(
      version(
        rest: const NutritionDayTarget(
          inputMode: NutritionTargetInputMode.grams,
          kilocalories: 2200,
          proteinGrams: 180,
          carbohydrateGrams: 190,
          fatGrams: 80,
        ),
      ),
    );
    expect(withRest['restDay'], {
      'inputMode': 'Grams',
      'kilocalories': 2200.0,
      'proteinGrams': 180.0,
      'carbohydrateGrams': 190.0,
      'fatGrams': 80.0,
      'proteinPercent': null,
      'carbohydratePercent': null,
      'fatPercent': null,
    });
    expect(firstVersion(version()), isNot(contains('restDay')));
  });

  test('day templates map to their own resource and operations', () {
    expect(
      SyncPayloadCodec.aggregateTypeForResource('NutritionDayTemplate'),
      'nutrition-day-template',
    );
    final body = NutritionDayTemplate(
      templateId: _aggregateId,
      name: 'Trainingstag',
      dayKind: NutritionDayKind.training,
      entries: [_entry],
    ).toJson().cast<String, dynamic>();
    final save = _mutation(
      'nutrition-day-template',
      LocalMutationOperation.create,
      body,
    );
    expect(
      SyncPayloadCodec.serverOperation(save, body),
      'saveNutritionDayTemplate',
    );
    final payload = _payload(
      'nutrition-day-template',
      LocalMutationOperation.create,
      body,
    );
    expect(payload['templateId'], _aggregateId);
    expect(payload['name'], 'Trainingstag');
    expect(payload['dayKind'], 'Training');
    final entry = (payload['entries'] as List).single as Map<String, Object?>;
    expect(entry['meal'], 'Lunch');
    expect(entry['kilocaloriesPer100Grams'], 130.0);

    final delete = _mutation(
      'nutrition-day-template',
      LocalMutationOperation.delete,
      body,
    );
    expect(
      SyncPayloadCodec.serverOperation(delete, body),
      'deleteNutritionDayTemplate',
    );
    expect(
      _payload('nutrition-day-template', LocalMutationOperation.delete, body),
      {'templateId': _aggregateId, 'baseVersion': 1},
    );
  });

  test('server template snapshots decode', () {
    final template = NutritionDayTemplate.fromJson({
      'templateId': _aggregateId,
      'name': 'Ruhetag',
      'dayKind': 'Rest',
      'entries': [
        {
          'entryId': 'e1',
          'meal': 'Breakfast',
          'position': 0,
          'productName': 'Haferflocken',
          'brand': null,
          'amountGrams': 80,
          'totals': {'kilocalories': 296},
          'per100Grams': {'kilocalories': 370},
          'source': null,
          'portion': null,
        },
      ],
      'totals': {'kilocalories': 296},
      'createdAtUtc': '2026-10-22T08:00:00Z',
      'updatedAtUtc': '2026-10-22T09:00:00Z',
      'version': 2,
    });
    expect(template.dayKind, NutritionDayKind.rest);
    expect(template.entries.single.productName, 'Haferflocken');
    expect(template.updatedAtUtc, DateTime.utc(2026, 10, 22, 9));
  });
}
