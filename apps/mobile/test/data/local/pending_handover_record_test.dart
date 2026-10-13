import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/services/local/pending_handover_secret_store.dart';

void main() {
  test(
    'source request record is discoverable before server assigns a handover ID',
    () {
      final record = PendingHandoverRecord(
        apiOrigin: 'https://api.example.test',
        accountId: '11111111-1111-4111-8111-111111111111',
        requestId: '22222222-2222-4222-8222-222222222222',
        sourceClientId: '33333333-3333-4333-8333-333333333333',
        phase: 'sourceBeginPending',
        expiresAtUtc: null,
        frozenRevision: 12,
      );
      final bytes = record.encode();
      final decoded = PendingHandoverRecord.decode(bytes);
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

      expect(decoded.handoverId, isNull);
      expect(decoded.requestId, record.requestId);
      expect(decoded.frozenRevision, 12);
      expect(json['version'], PendingHandoverRecord.currentVersion);
    },
  );

  test(
    'target retry record retains the exact revision and secret in opaque bytes',
    () {
      final code = Uint8List.fromList(
        PendingHandoverRecord(
          apiOrigin: 'https://api.example.test',
          accountId: '11111111-1111-4111-8111-111111111111',
          requestId: '22222222-2222-4222-8222-222222222222',
          sourceClientId: '33333333-3333-4333-8333-333333333333',
          handoverId: '44444444-4444-4444-8444-444444444444',
          targetClientId: '55555555-5555-4555-8555-555555555555',
          frozenRevision: 91,
          phase: 'targetCompletePending',
          expiresAtUtc: DateTime.utc(2026, 10, 13),
          oneTimeCode: 'once-only-fixture',
        ).encode(),
      );
      final decoded = PendingHandoverRecord.decode(code);

      expect(decoded.frozenRevision, 91);
      expect(decoded.oneTimeCode, 'once-only-fixture');
      expect(decoded.targetClientId, '55555555-5555-4555-8555-555555555555');
      expect(decoded.expiresAtUtc, DateTime.utc(2026, 10, 13));
    },
  );

  test('rejects unsupported record versions', () {
    final invalid = Uint8List.fromList(utf8.encode('{"version":99}'));
    expect(() => PendingHandoverRecord.decode(invalid), throwsFormatException);
  });
}
