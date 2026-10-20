import 'package:flutter/cupertino.dart';

import '../../../domain/models/training/muscle_volume.dart';
import '../../../domain/models/training/muscles.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'body_map.dart';

/// Farbe einer Satzstufe (Design D4); `null` = Grundfarbe der Karte.
Color? muscleLevelColor(MuscleLevel level, GainerColors colors) =>
    switch (level) {
      MuscleLevel.none => null,
      MuscleLevel.low => colors.accent.withValues(alpha: 0.3),
      MuscleLevel.medium => colors.accent.withValues(alpha: 0.6),
      MuscleLevel.high => colors.accent,
      MuscleLevel.veryHigh => colors.warning,
    };

Map<Muscle, Color> volumeFills(MuscleVolume volume, GainerColors colors) => {
  for (final muscle in Muscle.values)
    muscle: ?muscleLevelColor(volume.levelFor(muscle), colors),
};

/// Hauptmuskeln voll, Hilfsmuskeln halb eingefärbt.
Map<Muscle, Color> roleFills(
  List<Muscle> primary,
  List<Muscle> secondary,
  GainerColors colors,
) => {
  for (final muscle in secondary) muscle: colors.accent.withValues(alpha: 0.4),
  for (final muscle in primary) muscle: colors.accent,
};

/// „1 Satz“, „7,5 Sätze“; Ø-Werte mit höchstens einer Nachkommastelle.
String formatMuscleSets(double sets) {
  final rounded = (sets * 10).round() / 10;
  final text = rounded == rounded.roundToDouble()
      ? rounded.toInt().toString()
      : rounded.toStringAsFixed(1).replaceAll('.', ',');
  return rounded == 1 ? '1 Satz' : '$text Sätze';
}

/// Körperkarte mit Legende der Satzstufen in einer Karte.
class MuscleVolumeCard extends StatelessWidget {
  const MuscleVolumeCard({
    required this.volume,
    this.onMuscleTap,
    this.mapHeight,
    super.key,
  });

  final MuscleVolume volume;
  final ValueChanged<Muscle>? onMuscleTap;

  /// Feste Höhe der Karte; ohne Wert füllt sie die Breite.
  final double? mapHeight;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final trained = [
      for (final muscle in volume.ranked)
        if (volume.setsFor(muscle) > 0) muscle,
    ];
    return GainerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sized(
            BodyMap(
              fills: volumeFills(volume, colors),
              onMuscleTap: onMuscleTap,
              semanticLabel: trained.isEmpty
                  ? 'Körperkarte: keine Muskeln trainiert'
                  : 'Körperkarte: ${[for (final m in trained) '${m.label} ${formatMuscleSets(volume.setsFor(m))}'].join(', ')}',
            ),
          ),
          const SizedBox(height: GainerSpacing.s),
          const MuscleLevelLegend(),
        ],
      ),
    );
  }

  Widget _sized(Widget map) => switch (mapHeight) {
    final height? => Center(
      child: SizedBox(height: height, child: map),
    ),
    null => map,
  };
}

/// Farbfelder mit den Satzgrenzen der Stufen.
class MuscleLevelLegend extends StatelessWidget {
  const MuscleLevelLegend({super.key});

  static const _labels = {
    MuscleLevel.none: '0',
    MuscleLevel.low: 'unter 4',
    MuscleLevel.medium: '4–9',
    MuscleLevel.high: '10–20',
    MuscleLevel.veryHigh: 'über 20',
  };

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Semantics(
      label: 'Legende Sätze: ${_labels.values.join(', ')}',
      excludeSemantics: true,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: GainerSpacing.s,
        runSpacing: GainerSpacing.xxs,
        children: [
          for (final MapEntry(key: level, value: label) in _labels.entries)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: muscleLevelColor(level, colors) ?? colors.separator,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: GainerSpacing.xxs),
                Text(
                  label,
                  style: GainerTypography.caption.copyWith(
                    color: colors.secondaryText,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Sheet mit den Übungen, die zu [muscle] beitragen.
Future<void> showMuscleDetailSheet(
  BuildContext context, {
  required Muscle muscle,
  required MuscleVolume volume,
}) {
  return showGainerSheet<void>(
    context: context,
    builder: (sheetContext) {
      final colors = GainerDesign.colorsOf(sheetContext);
      final contributions = volume.contributionsFor(muscle);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GainerSheetHeader(title: muscle.label),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(GainerSpacing.m),
              child: contributions.isEmpty
                  ? Text(
                      'Keine Übung trainiert diesen Muskel.',
                      textAlign: TextAlign.center,
                      style: GainerTypography.body.copyWith(
                        color: colors.secondaryText,
                      ),
                    )
                  : GainerGroupedSection(
                      footer: 'Hilfsmuskeln zählen einen halben Satz.',
                      children: [
                        for (final contribution in contributions)
                          GainerListRow(
                            title: contribution.exerciseName,
                            subtitle: contribution.role == MuscleRole.primary
                                ? 'Hauptmuskel'
                                : 'Hilfsmuskel',
                            value: formatMuscleSets(contribution.sets),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      );
    },
  );
}
