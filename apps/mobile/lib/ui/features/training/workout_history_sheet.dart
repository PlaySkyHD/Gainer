import 'package:flutter/cupertino.dart';

import '../../../domain/models/training/exercise_history.dart';
import '../../../domain/models/training/workout_input.dart';
import '../../../domain/models/training/workout_model.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'workout_metadata_card.dart';

/// Verlaufs-Sheet einer Übung: frühere Trainings mit ihren erfassten Sätzen,
/// neuestes zuerst.
Future<void> showWorkoutHistorySheet({
  required BuildContext context,
  required String exerciseName,
  required List<ExerciseHistoryEntry> entries,
  required WeightUnit unit,
}) {
  return showCupertinoModalPopup<void>(
    context: context,
    builder: (_) => _WorkoutHistorySheet(
      exerciseName: exerciseName,
      entries: entries,
      unit: unit,
    ),
  );
}

/// Beschreibung eines Satzes für den Verlauf, etwa „60 kg × 10“.
String describeHistorySet(ExerciseKind kind, LoggedSet set, WeightUnit unit) {
  final weight = set.weightKg == null
      ? null
      : formatWeight(set.weightKg!, unit);
  final repetitions = set.repetitions?.toString() ?? '–';
  return switch (kind) {
    ExerciseKind.bodyweightOnly => '$repetitions Wdh.',
    ExerciseKind.bodyweightLoaded =>
      weight == null
          ? '$repetitions Wdh.'
          : '+$weight ${unit.label} × $repetitions',
    ExerciseKind.assisted =>
      'Unterst. ${weight ?? '–'} ${unit.label} × $repetitions',
    ExerciseKind.strength => '${weight ?? '–'} ${unit.label} × $repetitions',
  };
}

class _WorkoutHistorySheet extends StatelessWidget {
  const _WorkoutHistorySheet({
    required this.exerciseName,
    required this.entries,
    required this.unit,
  });

  final String exerciseName;
  final List<ExerciseHistoryEntry> entries;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(GainerRadii.card),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(GainerSpacing.m),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Verlauf · $exerciseName',
                      style: GainerTypography.title.copyWith(
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Schließen',
                      style: GainerTypography.body.copyWith(
                        color: colors.accent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: GainerSpacing.s),
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: GainerSpacing.l,
                  ),
                  child: Text(
                    'Noch keine erfassten Sätze für diese Übung.',
                    textAlign: TextAlign.center,
                    style: GainerTypography.body.copyWith(
                      color: colors.secondaryText,
                    ),
                  ),
                )
              else
                Flexible(
                  child: SingleChildScrollView(
                    child: GainerCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < entries.length; i++) ...[
                            if (i > 0) const SizedBox(height: GainerSpacing.s),
                            _HistoryEntry(entry: entries[i], unit: unit),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryEntry extends StatelessWidget {
  const _HistoryEntry({required this.entry, required this.unit});

  final ExerciseHistoryEntry entry;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${entry.workout.title} · ${formatWorkoutDateTime(entry.workout.startedAtUtc.toLocal())}',
          style: GainerTypography.label.copyWith(color: colors.secondaryText),
        ),
        const SizedBox(height: GainerSpacing.xxs),
        for (final set in entry.sets)
          Padding(
            padding: const EdgeInsets.only(bottom: GainerSpacing.xxs),
            child: Text(
              describeHistorySet(entry.kind, set, unit),
              style: GainerTypography.value.copyWith(color: colors.primaryText),
            ),
          ),
      ],
    );
  }
}
