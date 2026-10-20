import 'dart:convert';
import 'dart:typed_data';

import '../platform/generated/mobile_platform_api.dart';

/// What the native authenticator needs from WebAuthn creation options.
class PasskeyCreationRequest {
  const PasskeyCreationRequest({
    required this.relyingPartyId,
    required this.challenge,
    required this.userId,
    required this.userName,
  });

  final String relyingPartyId;
  final Uint8List challenge;
  final Uint8List userId;
  final String userName;
}

/// What the native authenticator needs from WebAuthn request options.
class PasskeyAssertionRequest {
  const PasskeyAssertionRequest({
    required this.relyingPartyId,
    required this.challenge,
  });

  final String relyingPartyId;
  final Uint8List challenge;
}

/// Translates between the server's WebAuthn JSON and the raw values of the
/// iOS authenticator. The server validates everything; this only reshapes.
abstract final class PasskeyCeremony {
  static PasskeyCreationRequest creationRequest(String optionsJson) {
    final options = _object(jsonDecode(optionsJson));
    final rp = _object(options['rp']);
    final user = _object(options['user']);
    return PasskeyCreationRequest(
      relyingPartyId: _string(rp, 'id'),
      challenge: base64UrlDecode(_string(options, 'challenge')),
      userId: base64UrlDecode(_string(user, 'id')),
      userName: _string(user, 'name'),
    );
  }

  static PasskeyAssertionRequest assertionRequest(String optionsJson) {
    final options = _object(jsonDecode(optionsJson));
    return PasskeyAssertionRequest(
      relyingPartyId: _string(options, 'rpId'),
      challenge: base64UrlDecode(_string(options, 'challenge')),
    );
  }

  /// `PublicKeyCredential` JSON of `navigator.credentials.create()`.
  static String registrationJson(PlatformPasskeyRegistration registration) =>
      _credential(registration.credentialId, {
        'clientDataJSON': base64UrlEncode(registration.clientDataJson),
        'attestationObject': base64UrlEncode(registration.attestationObject),
        'transports': ['internal', 'hybrid'],
      });

  /// `PublicKeyCredential` JSON of `navigator.credentials.get()`.
  static String assertionJson(PlatformPasskeyAssertion assertion) =>
      _credential(assertion.credentialId, {
        'clientDataJSON': base64UrlEncode(assertion.clientDataJson),
        'authenticatorData': base64UrlEncode(assertion.authenticatorData),
        'signature': base64UrlEncode(assertion.signature),
        'userHandle': base64UrlEncode(assertion.userHandle),
      });

  /// WebAuthn uses Base64Url without padding.
  static String base64UrlEncode(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static Uint8List base64UrlDecode(String value) =>
      base64Url.decode(base64Url.normalize(value));

  static String _credential(Uint8List id, Map<String, Object> response) {
    final encodedId = base64UrlEncode(id);
    return jsonEncode({
      'id': encodedId,
      'rawId': encodedId,
      'type': 'public-key',
      'authenticatorAttachment': 'platform',
      'response': response,
      'clientExtensionResults': <String, Object>{},
    });
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value is Map<String, dynamic>) return value;
    throw const FormatException('Invalid passkey options.');
  }

  static String _string(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String && value.isNotEmpty) return value;
    throw FormatException('Passkey options are missing "$key".');
  }
}
