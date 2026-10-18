import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../../domain/models/cardio/cardio_session.dart';
import '../../../domain/models/cardio/cardio_zones.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';

const zoneRangeError =
    'Der Zielbereich liegt zwischen 40 und 230 bpm, „von“ muss kleiner als „bis“ sein.';

/// Eingabe des Zielbereichs von–bis in bpm, darunter optional Zonen-Chips.
/// [onChanged] meldet den gültigen Bereich oder null, solange die Eingabe
/// ungültig ist.
class CardioZoneFields extends StatefulWidget {
  const CardioZoneFields({
    required this.initial,
    required this.onChanged,
    this.zones = const [],
    this.onOpenSettings,
    super.key,
  });

  final CardioTargetZone initial;
  final List<CardioZone> zones;
  final ValueChanged<CardioTargetZone?> onChanged;

  /// Öffnet die Cardio-Einstellungen; erscheint im Hinweis ohne Zonen.
  final VoidCallback? onOpenSettings;

  @override
  State<CardioZoneFields> createState() => CardioZoneFieldsState();
}

class CardioZoneFieldsState extends State<CardioZoneFields> {
  late final TextEditingController _low = TextEditingController(
    text: '${widget.initial.lowBpm}',
  );
  late final TextEditingController _high = TextEditingController(
    text: '${widget.initial.highBpm}',
  );

  @override
  void dispose() {
    _low.dispose();
    _high.dispose();
    super.dispose();
  }

  CardioTargetZone? get _zone {
    final low = int.tryParse(_low.text.trim());
    final high = int.tryParse(_high.text.trim());
    if (low == null || high == null) return null;
    final zone = CardioTargetZone(lowBpm: low, highBpm: high);
    return zone.isValid ? zone : null;
  }

  /// Setzt neue Werte, z. B. aus der Vorbelegung nach dem Laden.
  void setZone(CardioTargetZone zone) {
    _low.text = '${zone.lowBpm}';
    _high.text = '${zone.highBpm}';
    setState(() {});
    widget.onChanged(_zone);
  }

  void _changed() {
    setState(() {});
    widget.onChanged(_zone);
  }

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final zone = _zone;
    final typed = _low.text.isNotEmpty && _high.text.isNotEmpty;
    final formatters = [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(3),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GainerGroupedSection(
          header: 'Zielbereich',
          footer: zone == null && typed ? zoneRangeError : null,
          children: [
            GainerTextFieldRow(
              label: 'Von',
              unit: 'bpm',
              controller: _low,
              fieldKey: const ValueKey('cardio-zone-low'),
              keyboardType: TextInputType.number,
              inputFormatters: formatters,
              onChanged: (_) => _changed(),
            ),
            GainerTextFieldRow(
              label: 'Bis',
              unit: 'bpm',
              controller: _high,
              fieldKey: const ValueKey('cardio-zone-high'),
              keyboardType: TextInputType.number,
              inputFormatters: formatters,
              onChanged: (_) => _changed(),
            ),
          ],
        ),
        const SizedBox(height: GainerSpacing.s),
        if (widget.zones.isNotEmpty)
          Wrap(
            spacing: GainerSpacing.xs,
            runSpacing: GainerSpacing.xs,
            children: [
              for (final entry in widget.zones)
                _ZoneChip(
                  zone: entry,
                  selected:
                      zone != null &&
                      zone.lowBpm == entry.lowBpm &&
                      zone.highBpm == entry.highBpm,
                  onTap: () => setZone(
                    CardioTargetZone(
                      lowBpm: entry.lowBpm,
                      highBpm: entry.highBpm,
                    ),
                  ),
                ),
            ],
          )
        else
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onOpenSettings,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: GainerSpacing.xs),
              child: Text(
                'Maximalpuls in den Cardio-Einstellungen angeben, um Zonen '
                'vorzuschlagen',
                key: const ValueKey('cardio-zone-hint'),
                style: GainerTypography.label.copyWith(
                  color: widget.onOpenSettings == null
                      ? colors.secondaryText
                      : colors.accent,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ZoneChip extends StatelessWidget {
  const _ZoneChip({
    required this.zone,
    required this.selected,
    required this.onTap,
  });

  final CardioZone zone;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Semantics(
      button: true,
      selected: selected,
      label: 'Zone ${zone.number}, ${zone.lowBpm} bis ${zone.highBpm} bpm',
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('cardio-zone-chip-${zone.number}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: GainerSpacing.s,
            vertical: GainerSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: selected ? colors.accent : colors.surface,
            borderRadius: BorderRadius.circular(GainerRadii.field),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Zone ${zone.number}',
                style: GainerTypography.label.copyWith(
                  fontWeight: FontWeight.w600,
                  color: selected ? colors.onAccent : colors.primaryText,
                ),
              ),
              Text(
                '${zone.lowBpm}–${zone.highBpm}',
                style: GainerTypography.caption.copyWith(
                  color: selected ? colors.onAccent : colors.secondaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
