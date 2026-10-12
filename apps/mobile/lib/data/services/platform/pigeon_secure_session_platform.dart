import 'dart:typed_data';

import 'generated/mobile_platform_api.dart';
import 'platform_ports.dart';

class PigeonSecureSessionPlatform implements SecureSessionPlatform {
  PigeonSecureSessionPlatform({MobilePlatformApi? api})
    : _api = api ?? MobilePlatformApi();

  final MobilePlatformApi _api;

  @override
  Future<Uint8List?> readCheckpoint(String apiOrigin) {
    return _api.readSessionCheckpoint(apiOrigin);
  }

  @override
  Future<void> writeCheckpoint(String apiOrigin, Uint8List checkpoint) {
    return _api.writeSessionCheckpoint(apiOrigin, checkpoint);
  }

  @override
  Future<void> clearCheckpoint(String apiOrigin) {
    return _api.clearSessionCheckpoint(apiOrigin);
  }
}
