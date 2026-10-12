import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/services/platform/generated/mobile_platform_api.dart';
import 'package:gainer_mobile/data/services/platform/pigeon_secure_session_platform.dart';

class _FakeMobilePlatformApi extends MobilePlatformApi {
  final Map<String, Uint8List> checkpoints = {};
  final List<String> clearedOrigins = [];

  @override
  Future<Uint8List?> readSessionCheckpoint(String apiOrigin) async {
    final checkpoint = checkpoints[apiOrigin];
    return checkpoint == null ? null : Uint8List.fromList(checkpoint);
  }

  @override
  Future<void> writeSessionCheckpoint(
    String apiOrigin,
    Uint8List checkpoint,
  ) async {
    checkpoints[apiOrigin] = Uint8List.fromList(checkpoint);
  }

  @override
  Future<void> clearSessionCheckpoint(String apiOrigin) async {
    clearedOrigins.add(apiOrigin);
    checkpoints.remove(apiOrigin);
  }
}

void main() {
  test(
    'secure session adapter preserves API-origin binding and bytes',
    () async {
      final api = _FakeMobilePlatformApi();
      final platform = PigeonSecureSessionPlatform(api: api);
      const apiOrigin = 'https://api.example.test';
      final checkpoint = Uint8List.fromList([0, 1, 127, 128, 255]);

      expect(await platform.readCheckpoint(apiOrigin), isNull);
      await platform.writeCheckpoint(apiOrigin, checkpoint);
      checkpoint[0] = 42;

      expect(
        await platform.readCheckpoint(apiOrigin),
        orderedEquals([0, 1, 127, 128, 255]),
      );
      expect(
        await platform.readCheckpoint('https://other.example.test'),
        isNull,
      );

      await platform.clearCheckpoint(apiOrigin);
      expect(api.clearedOrigins, [apiOrigin]);
      expect(await platform.readCheckpoint(apiOrigin), isNull);
    },
  );
}
