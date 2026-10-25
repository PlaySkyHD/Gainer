import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../../data/repositories/nutrition/nutrition_preferences.dart';
import '../../../domain/models/nutrition/water_intake.dart';
import '../../core/components/components.dart';
import '../../core/navigation/single_instance_route.dart';
import 'nutrition_water_card.dart';

Future<void> openNutritionSettings(
  BuildContext context, {
  required NutritionPreferences preferences,
}) => pushSingleInstance<void>(
  context,
  key: 'nutrition-settings',
  rootNavigator: false,
  fullscreenDialog: false,
  builder: (_) => NutritionSettingsScreen(preferences: preferences),
);

/// Einstellungen der Ernährung (D7): Wasser erfassen und Tagesziel. Gelten nur
/// auf diesem Gerät und für dieses Konto; Änderungen gelten sofort.
class NutritionSettingsScreen extends StatefulWidget {
  const NutritionSettingsScreen({required this.preferences, super.key});

  final NutritionPreferences preferences;

  @override
  State<NutritionSettingsScreen> createState() =>
      _NutritionSettingsScreenState();
}

class _NutritionSettingsScreenState extends State<NutritionSettingsScreen> {
  late final _goal = TextEditingController(
    text: '${widget.preferences.values.value.waterGoalMl}',
  );
  String? _goalError;

  @override
  void initState() {
    super.initState();
    widget.preferences.read().then((values) {
      if (mounted) _goal.text = '${values.waterGoalMl}';
    });
  }

  @override
  void dispose() {
    _goal.dispose();
    super.dispose();
  }

  /// Ein Wert im Bereich wird gespeichert, sonst erscheint ein Fehler und
  /// das Ziel bleibt unverändert.
  void _goalChanged(String text) {
    final value = int.tryParse(text.trim());
    if (value == null || !WaterIntakeLimits.isValidGoal(value)) {
      setState(
        () => _goalError =
            'Erlaubt sind ${formatWaterMl(WaterIntakeLimits.minGoalMl)} bis '
            '${formatWaterMl(WaterIntakeLimits.maxGoalMl)} ml.',
      );
      return;
    }
    setState(() => _goalError = null);
    widget.preferences.update(
      (current) => current.copyWith(waterGoalMl: value),
    );
  }

  @override
  Widget build(BuildContext context) => GainerScaffold(
    title: 'Einstellungen',
    children: [
      ValueListenableBuilder<NutritionPreferenceValues>(
        valueListenable: widget.preferences.values,
        builder: (context, values, _) => GainerGroupedSection(
          header: 'Wasser',
          footer:
              'Zeigt im Ernährungstag eine Karte mit Schnellknöpfen. Beim '
              'Ausschalten bleiben erfasste Mengen erhalten. Gilt nur auf '
              'diesem iPhone.',
          children: [
            GainerListRow(
              title: 'Wasser erfassen',
              trailing: CupertinoSwitch(
                key: const ValueKey('nutrition-settings-water'),
                value: values.waterEnabled,
                onChanged: (value) => widget.preferences.update(
                  (current) => current.copyWith(waterEnabled: value),
                ),
              ),
            ),
            if (values.waterEnabled)
              GainerTextFieldRow(
                label: 'Tagesziel',
                unit: 'ml',
                controller: _goal,
                fieldKey: const ValueKey('nutrition-settings-water-goal'),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(5),
                ],
                onChanged: _goalChanged,
                errorText: _goalError,
              ),
          ],
        ),
      ),
    ],
  );
}
