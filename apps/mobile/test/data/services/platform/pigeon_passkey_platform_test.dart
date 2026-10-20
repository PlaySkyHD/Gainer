import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/services/platform/generated/mobile_platform_api.dart';
import 'package:gainer_mobile/data/services/platform/pigeon_passkey_platform.dart';

class _FakeMobilePlatformApi extends MobilePlatformApi {
  final calls = <String>[];

  @override
  Future<PlatformPasskeyRegistration?> createPasskey(
    String relyingPartyId,
    Uint8List challenge,
    Uint8List userId,
    String userName,
  ) async {
    calls.add('create $relyingPartyId $challenge $userId $userName');
    return PlatformPasskeyRegistration(
      credentialId: Uint8List.fromList([1]),
      clientDataJson: Uint8List.fromList([2]),
      attestationObject: Uint8List.fromList([3]),
    );
  }

  @override
  Future<PlatformPasskeyAssertion?> assertPasskey(
    String relyingPartyId,
    Uint8List challenge,
  ) async {
    calls.add('assert $relyingPartyId $challenge');
    return null;
  }
}

void main() {
  test('passkey adapter forwards ceremonies unchanged', () async {
    final api = _FakeMobilePlatformApi();
    final platform = PigeonPasskeyPlatform(api: api);

    final registration = await platform.createPasskey(
      relyingPartyId: 'gainer.markfort.xyz',
      challenge: Uint8List.fromList([9]),
      userId: Uint8List.fromList([7]),
      userName: 'athlete@example.test',
    );
    final assertion = await platform.assertPasskey(
      relyingPartyId: 'gainer.markfort.xyz',
      challenge: Uint8List.fromList([8]),
    );

    expect(registration?.attestationObject, [3]);
    expect(assertion, isNull);
    expect(api.calls, [
      'create gainer.markfort.xyz [9] [7] athlete@example.test',
      'assert gainer.markfort.xyz [8]',
    ]);
  });
}
