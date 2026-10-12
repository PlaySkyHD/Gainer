import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/services/native/best_effort_rest_timer_notification_port.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';

void main() {
  test(
    'denial and native failures stay nonblocking for timer actions',
    () async {
      final platform = _TimerPlatform()..permissionGranted = false;
      var unavailableReports = 0;
      final port = BestEffortRestTimerNotificationPort(
        platform,
        onUnavailable: () => unavailableReports++,
      );

      await port.schedule(
        workoutId: 'workout-1',
        targetUtc: DateTime.utc(2026, 10, 12, 10),
      );
      expect(platform.schedules, 0);
      expect(unavailableReports, 1);

      platform.permissionGranted = true;
      platform.failSchedule = true;
      await port.schedule(
        workoutId: 'workout-1',
        targetUtc: DateTime.utc(2026, 10, 12, 10),
      );
      expect(unavailableReports, 2);

      platform.failCancel = true;
      await port.cancel(workoutId: 'workout-1');
      expect(unavailableReports, 3);
    },
  );
}

class _TimerPlatform implements TimerNotificationPlatform {
  bool permissionGranted = true;
  bool failSchedule = false;
  bool failCancel = false;
  int schedules = 0;

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  Future<void> schedule({
    required String workoutId,
    required int generation,
    required DateTime targetAtUtc,
  }) async {
    schedules++;
    if (failSchedule) throw StateError('native bridge unavailable');
  }

  @override
  Future<void> cancel(String workoutId) async {
    if (failCancel) throw StateError('native bridge unavailable');
  }
}
