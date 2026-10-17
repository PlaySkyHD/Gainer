import 'package:flutter/cupertino.dart';

import '../../core/components/components.dart';

/// Schalter „Aufwärmsätze einbeziehen“ für Statistiken. Der Wert ist gerätelokal
/// und kontogebunden gespeichert, Standard ist aus.
class WarmupSetsRow extends StatelessWidget {
  const WarmupSetsRow({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GainerGroupedSection(
      children: [
        GainerListRow(
          title: 'Aufwärmsätze einbeziehen',
          subtitle: 'Gilt für Statistik, Rekorde und Verlauf',
          trailing: CupertinoSwitch(value: value, onChanged: onChanged),
        ),
      ],
    );
  }
}
