import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/services/auth/passkey_ceremony.dart';
import 'package:gainer_mobile/data/services/platform/generated/mobile_platform_api.dart';

void main() {
  test('reads relying party, challenge and user from creation options', () {
    final request = PasskeyCeremony.creationRequest(
      jsonEncode({
        'rp': {'name': 'gainer.markfort.xyz', 'id': 'gainer.markfort.xyz'},
        'user': {
          'id': 'YWJjZA',
          'name': 'athlete@example.test',
          'displayName': 'athlete@example.test',
        },
        'challenge': 'AQID_-8',
        'pubKeyCredParams': [
          {'type': 'public-key', 'alg': -7},
        ],
      }),
    );

    expect(request.relyingPartyId, 'gainer.markfort.xyz');
    expect(request.challenge, [1, 2, 3, 255, 239]);
    expect(utf8.decode(request.userId), 'abcd');
    expect(request.userName, 'athlete@example.test');
  });

  test('reads relying party and challenge from request options', () {
    final request = PasskeyCeremony.assertionRequest(
      jsonEncode({
        'challenge': 'AAEC',
        'rpId': 'gainer.markfort.xyz',
        'allowCredentials': [],
      }),
    );

    expect(request.relyingPartyId, 'gainer.markfort.xyz');
    expect(request.challenge, [0, 1, 2]);
  });

  test('rejects options without challenge', () {
    expect(
      () => PasskeyCeremony.assertionRequest(
        jsonEncode({'rpId': 'gainer.markfort.xyz'}),
      ),
      throwsFormatException,
    );
  });

  test('builds WebAuthn JSON with unpadded Base64Url values', () {
    final registration = jsonDecode(
      PasskeyCeremony.registrationJson(
        PlatformPasskeyRegistration(
          credentialId: Uint8List.fromList([251, 255]),
          clientDataJson: Uint8List.fromList(utf8.encode('{}')),
          attestationObject: Uint8List.fromList([1]),
        ),
      ),
    ) as Map<String, dynamic>;
    expect(registration['id'], '-_8');
    expect(registration['rawId'], '-_8');
    expect(registration['type'], 'public-key');
    expect(registration['response'], {
      'clientDataJSON': 'e30',
      'attestationObject': 'AQ',
      'transports': ['internal', 'hybrid'],
    });

    final assertion = jsonDecode(
      PasskeyCeremony.assertionJson(
        PlatformPasskeyAssertion(
          credentialId: Uint8List.fromList([1]),
          clientDataJson: Uint8List.fromList([2]),
          authenticatorData: Uint8List.fromList([3]),
          signature: Uint8List.fromList([4]),
          userHandle: Uint8List.fromList([5]),
        ),
      ),
    ) as Map<String, dynamic>;
    expect(assertion['response'], {
      'clientDataJSON': 'Ag',
      'authenticatorData': 'Aw',
      'signature': 'BA',
      'userHandle': 'BQ',
    });
  });
}
