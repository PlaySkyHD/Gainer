import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/sync/sync_repository.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';
import 'package:gainer_mobile/data/services/auth/sync_foreground_scheduler.dart';

class _TimerStub implements Timer {
  _TimerStub(this.callback, {this.duration = Duration.zero});
  final void Function() callback;
  final Duration duration;
  var cancelled = false;
  var fired = false;

  @override
  bool get isActive => !cancelled && !fired;
  @override
  int get tick => 0;
  @override
  void cancel() => cancelled = true;

  void fire() {
    if (!isActive) return;
    fired = true;
    callback();
  }
}

const _idle = SyncRunReport(
  state: SyncRunState.idle,
  pushed: 0,
  pulledBatches: 0,
);

void main() {
  test(
    'start and foreground triggers coalesce through a single in-flight run',
    () async {
      final gate = Completer<SyncRunReport>();
      var calls = 0;
      final scheduler = SyncForegroundScheduler(
        observeLifecycle: false,
        isActive: () => true,
        synchronize: () {
          calls++;
          return gate.future;
        },
      );

      final start = scheduler.start();
      final foreground = scheduler.onForeground();
      expect(calls, 1);
      gate.complete(_idle);
      await Future.wait([start, foreground]);

      expect(calls, 1);
      expect(scheduler.lastReport?.state, SyncRunState.idle);
      await scheduler.dispose();
    },
  );

  test('local commits during a run coalesce into one follow-up sync', () async {
    final firstRun = Completer<SyncRunReport>();
    var calls = 0;
    final scheduler = SyncForegroundScheduler(
      observeLifecycle: false,
      isActive: () => true,
      synchronize: () {
        calls++;
        return calls == 1 ? firstRun.future : Future.value(_idle);
      },
    );

    final initial = scheduler.start();
    final firstCommit = scheduler.onLocalCommit();
    final secondCommit = scheduler.onLocalCommit();
    expect(calls, 1);
    firstRun.complete(_idle);
    await Future.wait([initial, firstCommit, secondCommit]);

    expect(calls, 2);
    await scheduler.dispose();
  });

  test('retry-pending report waits until its server retry deadline', () async {
    final initialTime = DateTime.utc(2026, 10, 12, 10);
    var clock = initialTime;
    final timers = <_TimerStub>[];
    var calls = 0;
    final recovered = Completer<void>();
    final scheduler = SyncForegroundScheduler(
      observeLifecycle: false,
      isActive: () => true,
      clock: () => clock,
      timerFactory: (duration, callback) {
        final timer = _TimerStub(callback, duration: duration);
        timers.add(timer);
        return timer;
      },
      synchronize: () async {
        calls++;
        if (calls == 1) {
          return SyncRunReport(
            state: SyncRunState.retryPending,
            pushed: 0,
            pulledBatches: 0,
            nextRetryAtUtc: initialTime.add(const Duration(seconds: 3)),
          );
        }
        recovered.complete();
        return _idle;
      },
    );

    await scheduler.start();
    expect(timers.single.duration, const Duration(seconds: 3));
    clock = initialTime.add(const Duration(seconds: 3));
    timers.single.fire();
    await recovered.future;
    await Future<void>.delayed(Duration.zero);

    expect(calls, 2);
    expect(scheduler.lastReport?.state, SyncRunState.idle);
    expect(timers, hasLength(1));
    await scheduler.dispose();
  });

  test(
    'network retry continues at capped foreground interval until recovery',
    () async {
      final delays = <Duration>[];
      final timers = <_TimerStub>[];
      var calls = 0;
      final scheduler = SyncForegroundScheduler(
        observeLifecycle: false,
        isActive: () => true,
        retryDelays: const [Duration(seconds: 1), Duration(seconds: 2)],
        timerFactory: (duration, callback) {
          delays.add(duration);
          final timer = _TimerStub(callback);
          timers.add(timer);
          return timer;
        },
        synchronize: () async {
          calls++;
          if (calls >= 7) return _idle;
          throw const ApiException(
            statusCode: null,
            code: 'network_error',
            message: 'offline',
          );
        },
      );

      await scheduler.start();
      expect(delays, const [Duration(seconds: 1)]);
      for (var index = 0; index < 6; index++) {
        timers[index].fire();
        await Future<void>.delayed(Duration.zero);
      }
      expect(calls, 7);
      expect(delays, [
        const Duration(seconds: 1),
        const Duration(seconds: 2),
        const Duration(seconds: 2),
        const Duration(seconds: 2),
        const Duration(seconds: 2),
        const Duration(seconds: 2),
      ]);
      expect(scheduler.lastReport?.state, SyncRunState.idle);
      expect(timers.last.isActive, isFalse);
      await scheduler.dispose();
    },
  );

  test(
    'background and handover pause cancel retry; resume starts a new run',
    () async {
      final timers = <_TimerStub>[];
      var calls = 0;
      final scheduler = SyncForegroundScheduler(
        observeLifecycle: false,
        isActive: () => true,
        timerFactory: (duration, callback) {
          final timer = _TimerStub(callback);
          timers.add(timer);
          return timer;
        },
        synchronize: () async {
          calls++;
          throw const ApiException(
            statusCode: null,
            code: 'network_error',
            message: 'offline',
          );
        },
      );

      await scheduler.start();
      scheduler.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(timers.single.isActive, isFalse);
      timers.single.fire();
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);

      scheduler.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 2);
      expect(timers.last.isActive, isTrue);
      scheduler.pause();
      expect(timers.last.isActive, isFalse);
      await scheduler.resume();
      expect(calls, 3);
      await scheduler.dispose();
    },
  );

  test('allowing handover does not make a background app foreground', () async {
    var calls = 0;
    final scheduler = SyncForegroundScheduler(
      observeLifecycle: false,
      isActive: () => true,
      synchronize: () async {
        calls++;
        return _idle;
      },
    );

    await scheduler.start();
    expect(calls, 1);
    scheduler.pause();
    scheduler.didChangeAppLifecycleState(AppLifecycleState.paused);
    scheduler.allow();
    await scheduler.onLocalCommit();
    expect(calls, 1);

    await scheduler.resume();
    expect(calls, 2);
    await scheduler.dispose();
  });

  test(
    'auth-blocked report does not retry and inactive scopes do not sync',
    () async {
      var active = true;
      var calls = 0;
      final timers = <_TimerStub>[];
      final scheduler = SyncForegroundScheduler(
        observeLifecycle: false,
        isActive: () => active,
        timerFactory: (duration, callback) {
          final timer = _TimerStub(callback);
          timers.add(timer);
          return timer;
        },
        synchronize: () async {
          calls++;
          return const SyncRunReport(
            state: SyncRunState.authBlocked,
            pushed: 0,
            pulledBatches: 0,
          );
        },
      );

      await scheduler.start();
      expect(scheduler.lastReport?.state, SyncRunState.authBlocked);
      expect(timers, isEmpty);
      await scheduler.onLocalCommit();
      expect(calls, 1);
      active = false;
      await scheduler.onForeground();
      expect(calls, 1);
      await scheduler.dispose();
    },
  );

  test(
    'dispose cancels retry and prevents callbacks from starting another run',
    () async {
      final timers = <_TimerStub>[];
      var active = true;
      var calls = 0;
      final scheduler = SyncForegroundScheduler(
        observeLifecycle: false,
        isActive: () => active,
        timerFactory: (duration, callback) {
          final timer = _TimerStub(callback);
          timers.add(timer);
          return timer;
        },
        synchronize: () async {
          calls++;
          throw const ApiException(
            statusCode: null,
            code: 'network_error',
            message: 'offline',
          );
        },
      );

      await scheduler.start();
      expect(timers.single.isActive, isTrue);
      active = false;
      await scheduler.dispose();
      expect(timers.single.isActive, isFalse);
      timers.single.fire();
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
    },
  );
}
