import '../../repositories/training/training_repository.dart';
import '../platform/platform_ports.dart';

/// Keeps durable workout edits independent from the optional OS notification.
class BestEffortRestTimerNotificationPort implements RestTimerNotificationPort {
  const BestEffortRestTimerNotificationPort(
    this.platform, {
    this.onUnavailable,
  });

  final TimerNotificationPlatform platform;
  final void Function()? onUnavailable;

  @override
  Future<void> schedule({
    required String workoutId,
    required DateTime targetUtc,
  }) async {
    try {
      final allowed = await platform.requestPermission();
      if (!allowed) {
        _reportUnavailable();
        return;
      }
      await platform.schedule(
        workoutId: workoutId,
        generation: targetUtc.millisecondsSinceEpoch,
        targetAtUtc: targetUtc,
      );
    } catch (_) {
      _reportUnavailable();
    }
  }

  @override
  Future<void> cancel({required String workoutId}) async {
    try {
      await platform.cancel(workoutId);
    } catch (_) {
      _reportUnavailable();
    }
  }

  void _reportUnavailable() {
    try {
      onUnavailable?.call();
    } catch (_) {
      // A status callback cannot change the result of a workout operation.
    }
  }
}
