import 'package:flutter/cupertino.dart';

import '../../core/components/components.dart';

const cardioWarmupMinutes = [0, 1, 2, 3, 5];

/// Wählt die Aufwärmzeit ohne Alarm (0, 1, 2, 3 oder 5 min). Andere Werte
/// rasten auf die nächste Stufe ein.
class CardioWarmupPicker extends StatelessWidget {
  const CardioWarmupPicker({
    required this.seconds,
    required this.onChanged,
    super.key,
  });

  final int seconds;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final minutes = cardioWarmupMinutes.reduce(
      (best, next) => (next * 60 - seconds).abs() < (best * 60 - seconds).abs()
          ? next
          : best,
    );
    return GainerSegmentedControl<int>(
      options: {for (final value in cardioWarmupMinutes) value: '$value'},
      value: minutes,
      onChanged: (value) => onChanged(value * 60),
    );
  }
}
