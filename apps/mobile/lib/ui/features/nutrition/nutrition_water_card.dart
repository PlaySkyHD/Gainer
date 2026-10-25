import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../../domain/models/nutrition/water_intake.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'nutrition_averages_view.dart';

/// Milliliter deutsch formatiert, z. B. `1.250`.
String formatWaterMl(int value) => formatNutritionNumber(value.toDouble());

/// Wasser des Tages: Menge und Ziel, Fortschritt und Schnellknöpfe (D8).
/// Antippen der Menge öffnet die Korrektur.
class NutritionWaterCard extends StatelessWidget {
  const NutritionWaterCard({
    required this.amountMl,
    required this.goalMl,
    required this.onAdd,
    required this.onEdit,
    super.key,
  });

  final int amountMl;
  final int goalMl;
  final ValueChanged<int> onAdd;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.5;
    final label = '${formatWaterMl(amountMl)} / ${formatWaterMl(goalMl)} ml';
    final buttons = [
      for (final amount in WaterIntakeLimits.quickAmountsMl)
        GainerPillButton(
          key: ValueKey('nutrition-water-add-$amount'),
          label: '+$amount ml',
          variant: GainerPillVariant.tonal,
          compact: true,
          expand: !large,
          onPressed: WaterIntakeLimits.canAdd(amountMl, amount)
              ? () => onAdd(amount)
              : null,
        ),
    ];
    return GainerGroupedSection(
      children: [
        Semantics(
          liveRegion: true,
          // Bei großer Schrift steht die Menge unter dem Titel, sonst bricht
          // „Wasser“ mitten im Wort um.
          child: GainerListRow(
            key: const ValueKey('nutrition-water-amount'),
            title: 'Wasser',
            leadingIcon: CupertinoIcons.drop,
            value: large ? null : label,
            subtitle: large ? label : null,
            showChevron: true,
            onTap: onEdit,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            GainerSpacing.m,
            GainerSpacing.s,
            GainerSpacing.m,
            GainerSpacing.m,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GainerProgressBar(
                consumed: amountMl.toDouble(),
                target: goalMl.toDouble(),
                warnWhenExceeded: false,
              ),
              const SizedBox(height: GainerSpacing.s),
              // Bei großer Schrift brechen die Knöpfe um statt überzulaufen.
              if (large)
                Wrap(
                  spacing: GainerSpacing.xs,
                  runSpacing: GainerSpacing.xs,
                  children: buttons,
                )
              else
                Row(
                  children: [
                    for (var i = 0; i < buttons.length; i++) ...[
                      if (i > 0) const SizedBox(width: GainerSpacing.xs),
                      Expanded(child: buttons[i]),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Öffnet die Korrektur der Tagesmenge. [onSave] liefert true, wenn
/// gespeichert wurde; dann schließt das Sheet, sonst bleibt es offen.
Future<void> showWaterAmountSheet(
  BuildContext context, {
  required int currentMl,
  required Future<bool> Function(int amountMl) onSave,
}) => showGainerSheet<void>(
  context: context,
  builder: (_) => WaterAmountSheet(currentMl: currentMl, onSave: onSave),
);

/// Inhalt des Sheets „Wasser“; öffentlich für Tests und Vorschauen.
class WaterAmountSheet extends StatefulWidget {
  const WaterAmountSheet({
    required this.currentMl,
    required this.onSave,
    super.key,
  });

  final int currentMl;
  final Future<bool> Function(int amountMl) onSave;

  @override
  State<WaterAmountSheet> createState() => _WaterAmountSheetState();
}

class _WaterAmountSheetState extends State<WaterAmountSheet> {
  late final _amount = TextEditingController(text: '${widget.currentMl}');
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  int? get _value => int.tryParse(_amount.text.trim());

  bool get _valid {
    final value = _value;
    return value != null && WaterIntakeLimits.isValidDaily(value);
  }

  String? get _error => _amount.text.trim().isEmpty || _valid
      ? null
      : 'Erlaubt sind 0 bis ${formatWaterMl(WaterIntakeLimits.maxDailyMl)} ml.';

  Future<void> _save(int value) async {
    setState(() => _saving = true);
    final saved = await widget.onSave(value);
    if (!mounted) return;
    if (saved) {
      Navigator.of(context).pop();
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: GainerSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GainerSheetHeader(
            title: 'Wasser',
            // Der kurze Titel lässt „Sichern“ auch bei großer Schrift ganz.
            compactTrailing: true,
            trailing: GainerPillButton(
              key: const ValueKey('nutrition-water-save'),
              label: 'Sichern',
              isLoading: _saving,
              onPressed: _valid && !_saving ? () => _save(_value!) : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              GainerSpacing.m,
              GainerSpacing.m,
              GainerSpacing.m,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GainerGroupedSection(
                  footer:
                      'Korrigiere die Menge des Tages, etwa wenn ein Glas '
                      'doppelt gezählt ist.',
                  children: [
                    GainerTextFieldRow(
                      label: 'Tagesmenge',
                      unit: 'ml',
                      controller: _amount,
                      fieldKey: const ValueKey('nutrition-water-field'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(5),
                      ],
                      onChanged: (_) => setState(() {}),
                      errorText: _error,
                    ),
                  ],
                ),
                const SizedBox(height: GainerSpacing.l),
                GainerPillButton(
                  key: const ValueKey('nutrition-water-reset'),
                  label: 'Auf 0 ml zurücksetzen',
                  variant: GainerPillVariant.destructive,
                  expand: true,
                  onPressed: widget.currentMl == 0 || _saving
                      ? null
                      : () => _save(0),
                ),
                if (widget.currentMl == 0)
                  Padding(
                    padding: const EdgeInsets.only(top: GainerSpacing.xs),
                    child: Text(
                      'Für diesen Tag ist noch kein Wasser erfasst.',
                      textAlign: TextAlign.center,
                      style: GainerTypography.label.copyWith(
                        color: colors.secondaryText,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
