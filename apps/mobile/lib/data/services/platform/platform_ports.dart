import 'dart:typed_data';

abstract interface class CapturePlatform {
  Future<String?> scanBarcode();
  Future<CapturedImage?> chooseImage();
}

class CapturedImage {
  const CapturedImage({required this.bytes, required this.mimeType});

  final Uint8List bytes;
  final String mimeType;
}

abstract interface class SecureSessionPlatform {
  Future<Uint8List?> readCheckpoint(String apiOrigin);
  Future<void> writeCheckpoint(String apiOrigin, Uint8List checkpoint);
  Future<void> clearCheckpoint(String apiOrigin);
}

abstract interface class TimerNotificationPlatform {
  Future<bool> requestPermission();
  Future<void> schedule({
    required String workoutId,
    required int generation,
    required DateTime targetAtUtc,
  });
  Future<void> cancel(String workoutId);
}

enum HapticIntent { commit, timerComplete, success }

abstract interface class HapticsPlatform {
  Future<void> perform(HapticIntent intent);
}

abstract interface class HealthPlatform {
  Future<bool> isAvailable();
}

abstract interface class ExtensionSnapshotPlatform {
  Future<void> publish(NeutralExtensionSnapshot snapshot);
  Future<void> clear();
}

class NeutralExtensionSnapshot {
  const NeutralExtensionSnapshot({
    required this.schemaVersion,
    required this.generation,
    required this.updatedAtUtc,
    required this.availableRoutes,
  });

  final int schemaVersion;
  final int generation;
  final DateTime updatedAtUtc;
  final Set<String> availableRoutes;
}
