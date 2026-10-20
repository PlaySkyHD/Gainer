import 'dart:typed_data';

import 'generated/mobile_platform_api.dart';
import 'platform_ports.dart';

class PigeonPasskeyPlatform implements PasskeyPlatform {
  PigeonPasskeyPlatform({MobilePlatformApi? api})
    : _api = api ?? MobilePlatformApi();

  final MobilePlatformApi _api;

  @override
  Future<PlatformPasskeyRegistration?> createPasskey({
    required String relyingPartyId,
    required Uint8List challenge,
    required Uint8List userId,
    required String userName,
  }) => _api.createPasskey(relyingPartyId, challenge, userId, userName);

  @override
  Future<PlatformPasskeyAssertion?> assertPasskey({
    required String relyingPartyId,
    required Uint8List challenge,
  }) => _api.assertPasskey(relyingPartyId, challenge);
}
