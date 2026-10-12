import 'dart:typed_data';

import '../local/pending_handover_secret_store.dart';
import 'generated/mobile_platform_api.dart';

/// Stores the opaque, versioned pending-handover record in its own Keychain
/// service, bound by native code to the API origin and account.
class PigeonPendingHandoverSecretStore implements PendingHandoverSecretStore {
  PigeonPendingHandoverSecretStore({MobilePlatformApi? api})
    : _api = api ?? MobilePlatformApi();

  final MobilePlatformApi _api;

  @override
  Future<void> write({
    required String apiOrigin,
    required String accountId,
    required Uint8List record,
  }) {
    return _api.writePendingHandover(apiOrigin, accountId, record);
  }

  @override
  Future<Uint8List?> read({
    required String apiOrigin,
    required String accountId,
  }) {
    return _api.readPendingHandover(apiOrigin, accountId);
  }

  @override
  Future<void> clear({required String apiOrigin, required String accountId}) {
    return _api.clearPendingHandover(apiOrigin, accountId);
  }
}
