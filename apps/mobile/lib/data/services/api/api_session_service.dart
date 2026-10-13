import 'dart:typed_data';

import '../../models/api/api_models.dart';
import '../platform/platform_ports.dart';
import 'api_client.dart';

/// Owns session bootstrap and stores only an opaque API-host-bound cookie
/// checkpoint through the platform's secure storage port.
class ApiSessionService {
  ApiSessionService({required this.api, required this.secureStorage});

  final ApiClient api;
  final SecureSessionPlatform secureStorage;

  Future<ApiSession?> restore() async {
    final bytes = await secureStorage.readCheckpoint(
      api.configuration.canonicalApiOrigin,
    );
    if (bytes == null || bytes.isEmpty) return null;

    late ApiSessionCheckpoint checkpoint;
    try {
      checkpoint = await api.restoreSecureCheckpoint(bytes);
    } on FormatException {
      await _clearLocalSession();
      return null;
    } on StateError {
      await _clearLocalSession();
      return null;
    }

    final session = await api.getSession();
    if (session == null || session.userId != checkpoint.userId) {
      await _clearLocalSession();
      return null;
    }
    return session;
  }

  Future<ApiSession> login(String email, String password) async {
    await _clearLocalSession();
    try {
      await api.login(ApiLoginRequest(email: email, password: password));
      final session = await api.getSession();
      if (session == null) {
        throw const ApiException(
          statusCode: 401,
          code: 'session_not_confirmed',
          message: 'Die Anmeldung konnte nicht bestätigt werden.',
        );
      }
      final checkpoint = await api.createSecureCheckpoint(session);
      await secureStorage.writeCheckpoint(
        api.configuration.canonicalApiOrigin,
        Uint8List.fromList(checkpoint),
      );
      return session;
    } catch (_) {
      await _clearLocalSession();
      rethrow;
    }
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

  Future<void> _clearLocalSession() async {
    await api.clearCookies();
    await secureStorage.clearCheckpoint(api.configuration.canonicalApiOrigin);
  }
}
