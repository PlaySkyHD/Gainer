import 'rest_timer_state.dart';

const defaultRestTimerShortcuts = [60, 120, 180];

/// Immutable, sorted set of duration shortcuts without duplicates.
class RestTimerShortcuts {
  RestTimerShortcuts._(this.seconds);

  factory RestTimerShortcuts.fromSeconds(Iterable<int> seconds) {
    final values = seconds.toSet().toList()..sort();
    for (final value in values) {
      _requireShortcut(value);
    }
    return RestTimerShortcuts._(List.unmodifiable(values));
  }

  static final defaults = RestTimerShortcuts.fromSeconds(
    defaultRestTimerShortcuts,
  );

  final List<int> seconds;

  RestTimerShortcuts add(int value) {
    _requireShortcut(value);
    if (seconds.contains(value)) return this;
    return RestTimerShortcuts.fromSeconds([...seconds, value]);
  }

  RestTimerShortcuts remove(int value) {
    if (!seconds.contains(value)) return this;
    return RestTimerShortcuts.fromSeconds(seconds.where((s) => s != value));
  }

  @override
  bool operator ==(Object other) =>
      other is RestTimerShortcuts && _sameValues(seconds, other.seconds);

  @override
  int get hashCode => Object.hashAll(seconds);

  @override
  String toString() => 'RestTimerShortcuts($seconds)';
}

bool _sameValues(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void _requireShortcut(int seconds) {
  if (seconds < restTimerMinSeconds || seconds > restTimerMaxSeconds) {
    throw ArgumentError.value(
      seconds,
      'seconds',
      'Expected a shortcut from $restTimerMinSeconds s to $restTimerMaxSeconds s.',
    );
  }
}
