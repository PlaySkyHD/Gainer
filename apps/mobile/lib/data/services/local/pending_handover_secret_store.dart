import 'dart:convert';
import 'dart:typed_data';

/// Versioned crash-recovery record for the single in-flight account handover.
/// It contains the one-time code and therefore must only live in a
/// purpose-bound Keychain/Keystore item, never SQLite or preferences.
class PendingHandoverRecord {
  const PendingHandoverRecord({
    required this.apiOrigin,
    required this.accountId,
    required this.requestId,
    required this.sourceClientId,
    required this.phase,
    required this.expiresAtUtc,
    this.handoverId,
    this.targetClientId,
    this.frozenRevision,
    this.oneTimeCode,
  });

  static const currentVersion = 1;

  final String apiOrigin;
  final String accountId;
  final String requestId;
  final String sourceClientId;
  final String? handoverId;
  final String? targetClientId;
  final int? frozenRevision;
  final String phase;
  final DateTime? expiresAtUtc;
  final String? oneTimeCode;

  Uint8List encode() => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'version': currentVersion,
        'apiOrigin': apiOrigin,
        'accountId': accountId,
        'requestId': requestId,
        'sourceClientId': sourceClientId,
        'handoverId': handoverId,
        'targetClientId': targetClientId,
        'frozenRevision': frozenRevision,
        'phase': phase,
        'expiresAtUtc': expiresAtUtc?.toUtc().toIso8601String(),
        'oneTimeCode': oneTimeCode,
      }),
    ),
  );

  static PendingHandoverRecord decode(Uint8List bytes) {
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, dynamic> || value['version'] != currentVersion) {
      throw const FormatException('Unsupported pending handover record.');
    }
    DateTime? expiry;
    final rawExpiry = value['expiresAtUtc'];
    if (rawExpiry is String) expiry = DateTime.parse(rawExpiry).toUtc();
    return PendingHandoverRecord(
      apiOrigin: value['apiOrigin'] as String,
      accountId: value['accountId'] as String,
      requestId: value['requestId'] as String,
      sourceClientId: value['sourceClientId'] as String,
      handoverId: value['handoverId'] as String?,
      targetClientId: value['targetClientId'] as String?,
      frozenRevision: value['frozenRevision'] as int?,
      phase: value['phase'] as String,
      expiresAtUtc: expiry,
      oneTimeCode: value['oneTimeCode'] as String?,
    );
  }
}

/// Secure platform adapter. A single discoverable item is bound to canonical
/// API origin and account so source recovery works before a server handover ID
/// exists. Implementations must use a dedicated Keychain/Keystore purpose.
abstract interface class PendingHandoverSecretStore {
  Future<void> write({
    required String apiOrigin,
    required String accountId,
    required Uint8List record,
  });

  Future<Uint8List?> read({
    required String apiOrigin,
    required String accountId,
  });

  Future<void> clear({required String apiOrigin, required String accountId});
}
