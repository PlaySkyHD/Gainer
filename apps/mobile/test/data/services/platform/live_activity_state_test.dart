import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';
import 'package:gainer_mobile/domain/models/timer/rest_timer_state.dart';

void main() {
  const detail = LiveActivityDetail(
    title: 'Pull',
    exerciseName: 'Latzug',
    setIndex: 2,
    setCount: 3,
    exerciseIndex: 1,
    exerciseCount: 4,
    targetText: 'Ziel 60 kg × 10',
  );

  LiveActivityState state({
    int? restDurationSeconds = 180,
    LiveActivityDetail? detail = detail,
  }) => LiveActivityState(
    sessionId: 'workout-1',
    timerPhase: RestTimerPhase.running,
    startedAtUtc: DateTime.utc(2026, 10, 17, 10),
    staleAtUtc: DateTime.utc(2026, 10, 17, 10, 3),
    timerTargetAtUtc: DateTime.utc(2026, 10, 17, 10, 3),
    restDurationSeconds: restDurationSeconds,
    detail: detail,
  );

  test('gleiche Details sind gleich und haben denselben Hash', () {
    const copy = LiveActivityDetail(
      title: 'Pull',
      exerciseName: 'Latzug',
      setIndex: 2,
      setCount: 3,
      exerciseIndex: 1,
      exerciseCount: 4,
      targetText: 'Ziel 60 kg × 10',
    );

    expect(copy, detail);
    expect(copy.hashCode, detail.hashCode);
  });

  test('Details unterscheiden sich in Position und Zielwert', () {
    const otherTarget = LiveActivityDetail(
      title: 'Pull',
      exerciseName: 'Latzug',
      setIndex: 2,
      setCount: 3,
      exerciseIndex: 1,
      exerciseCount: 4,
      targetText: 'Ziel 62,5 kg × 8',
    );
    const otherPosition = LiveActivityDetail(
      title: 'Pull',
      exerciseName: 'Latzug',
      setIndex: 2,
      setCount: 3,
      exerciseIndex: 2,
      exerciseCount: 4,
      targetText: 'Ziel 60 kg × 10',
    );

    expect(otherTarget, isNot(detail));
    expect(otherPosition, isNot(detail));
  });

  test('Zustände vergleichen Pausendauer und Details', () {
    expect(state(), state());
    expect(state().hashCode, state().hashCode);
    expect(state(restDurationSeconds: 240), isNot(state()));
    expect(state(detail: null), isNot(state()));
    expect(state().expired, isFalse);
  });
}
