import '../../models/api/api_models.dart';
import '../auth/passkey_ceremony.dart';
import '../platform/platform_ports.dart';
import 'api_client.dart';

/// Owns session bootstrap and keeps the device session's refresh token in the
/// platform's secure storage, bound to the API host.
class ApiSessionService {
  ApiSessionService({
    required this.api,
    required this.secureStorage,
    this.deviceName = defaultDeviceName,
  });

  static const defaultDeviceName = 'Gainer iPhone';

  final ApiClient api;
  final SecureSessionPlatform secureStorage;
  final String deviceName;

  Future<ApiSession?> restore() async {
    final bytes = await secureStorage.readCheckpoint(
      api.configuration.canonicalApiOrigin,
    );
    if (bytes == null || bytes.isEmpty) return null;

    late ApiSessionCheckpoint checkpoint;
    try {
      checkpoint = api.restoreSecureCheckpoint(bytes);
    } on FormatException {
      await _clearLocalSession();
      return null;
    }
    _persistRotations(checkpoint);

    final session = await api.getSession();
    if (session == null || session.userId != checkpoint.userId) {
      await _clearLocalSession();
      return null;
    }
    return session;
  }

  /// Restores the stored device session without contacting the API, so a
  /// known account can open offline. Returns null without a usable checkpoint.
  Future<ApiSessionCheckpoint?> restoreOffline() async {
    final bytes = await secureStorage.readCheckpoint(
      api.configuration.canonicalApiOrigin,
    );
    if (bytes == null || bytes.isEmpty) return null;
    final checkpoint = api.restoreSecureCheckpoint(bytes);
    _persistRotations(checkpoint);
    return checkpoint;
  }

  Future<ApiSession> login(String email, String password) async {
    await _clearLocalSession();
    try {
      await api.login(
        ApiLoginRequest(
          email: email,
          password: password,
          deviceName: deviceName,
        ),
      );
      return await _confirmSession();
    } catch (_) {
      await _clearLocalSession();
      rethrow;
    }
  }

  /// Signs in with a passkey via the system sheet. Returns null when the user
  /// cancels; the previous local session is kept in that case.
  Future<ApiSession?> loginWithPasskey(PasskeyPlatform passkeys) async {
    final options = await api.passkeyRequestOptions();
    final request = PasskeyCeremony.assertionRequest(options.optionsJson);
    final assertion = await passkeys.assertPasskey(
      relyingPartyId: request.relyingPartyId,
      challenge: request.challenge,
    );
    if (assertion == null) return null;
    await _clearLocalSession();
    try {
      await api.loginWithPasskey(
        credentialJson: PasskeyCeremony.assertionJson(assertion),
        state: options.state,
        deviceName: deviceName,
      );
      return await _confirmSession();
    } catch (_) {
      await _clearLocalSession();
      rethrow;
    }
  }

  /// Creates a passkey for the signed-in account. Returns null when the user
  /// cancels the system sheet.
  Future<ApiPasskey?> registerPasskey(
    PasskeyPlatform passkeys, {
    String? name,
  }) async {
    final options = await api.passkeyCreationOptions();
    final request = PasskeyCeremony.creationRequest(options.optionsJson);
    final registration = await passkeys.createPasskey(
      relyingPartyId: request.relyingPartyId,
      challenge: request.challenge,
      userId: request.userId,
      userName: request.userName,
    );
    if (registration == null) return null;
    return api.registerPasskey(
      credentialJson: PasskeyCeremony.registrationJson(registration),
      state: options.state,
      name: name,
    );
  }

  Future<ApiSession> _confirmSession() async {
    final session = await api.getSession();
    if (session == null) {
      throw const ApiException(
        statusCode: 401,
        code: 'session_not_confirmed',
        message: 'Die Anmeldung konnte nicht bestätigt werden.',
      );
    }
    await _writeCheckpoint(session.userId, session.email);
    _persistRotations(
      ApiSessionCheckpoint(userId: session.userId, email: session.email),
    );
    return session;
  }

  Future<void> acceptInvitation(String token, String password) =>
      api.acceptInvitation(
        ApiAcceptInvitationRequest(token: token, password: password),
      );

  Future<void> logout() async {
    try {
      await api.logout();
    } finally {
      await _clearLocalSession();
    }
  }

  /// Every refresh rotates the token; the keychain must follow, or the next
  /// launch would present a token the server already replaced.
  void _persistRotations(ApiSessionCheckpoint checkpoint) {
    api.onRefreshTokenRotated = (_) =>
        _writeCheckpoint(checkpoint.userId, checkpoint.email);
  }

  Future<void> _writeCheckpoint(String userId, String email) =>
      secureStorage.writeCheckpoint(
        api.configuration.canonicalApiOrigin,
        api.createSecureCheckpoint(
          ApiSession(userId: userId, email: email, isAccountOperator: false),
        ),
      );

  Future<void> _clearLocalSession() async {
    api.onRefreshTokenRotated = null;
    api.clearTokens();
    await secureStorage.clearCheckpoint(api.configuration.canonicalApiOrigin);
  }
}
