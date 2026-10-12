import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/services/platform/generated/mobile_platform_api.dart';
import 'package:gainer_mobile/data/services/platform/pigeon_pending_handover_secret_store.dart';

class _FakeMobilePlatformApi extends MobilePlatformApi {
  final Map<String, Uint8List> records = {};

  String _key(String origin, String accountId) =>
      '$origin|${accountId.toLowerCase()}';

  @override
  Future<Uint8List?> readPendingHandover(
    String apiOrigin,
    String accountId,
  ) async {
    final value = records[_key(apiOrigin, accountId)];
    return value == null ? null : Uint8List.fromList(value);
  }

  @override
  Future<void> writePendingHandover(
    String apiOrigin,
    String accountId,
    Uint8List record,
  ) async {
    records[_key(apiOrigin, accountId)] = Uint8List.fromList(record);
  }

  @override
  Future<void> clearPendingHandover(String apiOrigin, String accountId) async {
    records.remove(_key(apiOrigin, accountId));
  }
}

void main() {
  test(
    'handover record stays opaque and is isolated by origin and account',
    () async {
      final api = _FakeMobilePlatformApi();
      final store = PigeonPendingHandoverSecretStore(api: api);
      const origin = 'https://api.example.test';
      const accountA = 'a1111111-1111-4111-8111-111111111111';
      final record = Uint8List.fromList([0, 1, 127, 128, 255]);

      await store.write(apiOrigin: origin, accountId: accountA, record: record);
      record[0] = 42;

      expect(await store.read(apiOrigin: origin, accountId: accountA), [
        0,
        1,
        127,
        128,
        255,
      ]);
      expect(
        await store.read(apiOrigin: origin, accountId: accountA.toUpperCase()),
        [0, 1, 127, 128, 255],
      );
      expect(
        await store.read(
          apiOrigin: origin,
          accountId: 'b2222222-2222-4222-8222-222222222222',
        ),
        isNull,
      );
      expect(
        await store.read(
          apiOrigin: 'https://other.example.test',
          accountId: accountA,
        ),
        isNull,
      );

      await store.clear(apiOrigin: origin, accountId: accountA);
      expect(await store.read(apiOrigin: origin, accountId: accountA), isNull);
    },
  );
}
