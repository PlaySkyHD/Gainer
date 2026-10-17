import 'package:flutter/cupertino.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../../domain/models/training/workout_model.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'active_workout_controller.dart';
import 'training_format.dart';
import 'workout_screen.dart';

/// Sheet „Training wiederholen“: wählt die Vorwertquelle und startet ein neues
/// Training mit Titel, Blöcken und Satztypen von [source], aber ohne Satzwerte.
/// Existiert schon ein aktives Training, wird dessen Fortsetzen angeboten.
Future<void> showRepeatWorkoutSheet(
  BuildContext context, {
  required TrainingLogRepository repository,
  required ActiveWorkoutController activeWorkout,
  required Workout source,
}) async {
  final previousValueSource =
      await showCupertinoModalPopup<PreviousValueSource>(
        context: context,
        builder: (_) => _RepeatWorkoutSheet(source: source),
      );
  if (previousValueSource == null || !context.mounted) return;

  final running = await repository.readActiveWorkout();
  if (!context.mounted) return;
  if (running != null) {
    final resume = await showGainerStackedDialog<bool>(
      context: context,
      title: 'Aktives Training',
      message:
          'Es kann nur ein aktives Training geben. „${running.title}“ läuft noch.',
      actions: const [
        GainerDialogAction(label: 'Aktives Training fortsetzen', value: true),
        GainerDialogAction(label: 'Abbrechen', value: false),
      ],
    );
    if (resume == true && context.mounted) {
      await openWorkoutScreen(
        context,
        repository: repository,
        activeWorkout: activeWorkout,
        workoutId: running.workoutId,
      );
    }
    return;
  }

  String workoutId;
  try {
    workoutId = (await repository.startRepeat(
      source.workoutId,
      previousValueSource: previousValueSource,
    )).workoutId;
  } on ActiveWorkoutExistsException catch (error) {
    workoutId = error.workoutId;
  } catch (_) {
    if (context.mounted) {
      await showGainerStackedDialog<bool>(
        context: context,
        title: 'Training nicht gestartet',
        message: 'Das Training konnte nicht gestartet werden. Es wurde nichts gespeichert.',
        actions: const [GainerDialogAction(label: 'OK', value: true)],
      );
    }
    return;
  }

  await activeWorkout.load();
  if (!context.mounted) return;
  await openWorkoutScreen(
    context,
    repository: repository,
    activeWorkout: activeWorkout,
    workoutId: workoutId,
  );
}

class _RepeatWorkoutSheet extends StatefulWidget {
  const _RepeatWorkoutSheet({required this.source});

  final Workout source;

  @override
  State<_RepeatWorkoutSheet> createState() => _RepeatWorkoutSheetState();
}

class _RepeatWorkoutSheetState extends State<_RepeatWorkoutSheet> {
  PreviousValueSource _selected = PreviousValueSource.exercise;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final source = widget.source;
    final options = [
      (
        PreviousValueSource.exercise,
        'Aktuellste',
        'Ziele immer von der letzten Durchführung der jeweiligen Übung',
      ),
      (
        PreviousValueSource.workout,
        'Wiederholtes Training',
        'Werte vom ${formatShortDate(source.startedAtUtc.toLocal())}',
      ),
      if (source.sourcePlanId != null)
        (
          PreviousValueSource.plan,
          'Trainingsplan',
          'Werte aus dem Plan dieses Trainings',
        ),
    ];

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(GainerSpacing.xs),
        padding: const EdgeInsets.fromLTRB(
          GainerSpacing.m,
          GainerSpacing.s,
          GainerSpacing.m,
          GainerSpacing.m,
        ),
        decoration: BoxDecoration(
          color: colors.elevatedSurface,
          borderRadius: BorderRadius.circular(GainerRadii.card),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Semantics(
                    button: true,
                    label: 'Schließen',
                    excludeSemantics: true,
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size.square(
                        GainerRadii.iconButtonDiameter,
                      ),
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(
                        GainerRadii.iconButtonDiameter / 2,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Icon(
                        CupertinoIcons.xmark,
                        size: 18,
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Training wiederholen',
                      textAlign: TextAlign.center,
                      style: GainerTypography.cardTitle.copyWith(
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                  const SizedBox(width: GainerRadii.iconButtonDiameter),
                ],
              ),
              const SizedBox(height: GainerSpacing.s),
              GainerCard(
                padding: EdgeInsets.zero,
                child: GainerListRow(
                  title: 'Training beginnen',
                  leadingIcon: CupertinoIcons.play_fill,
                  showChevron: false,
                  onTap: () => Navigator.of(context).pop(_selected),
                ),
              ),
              const SizedBox(height: GainerSpacing.s),
              GainerGroupedSection(
                header: 'Vorwertquelle',
                children: [
                  for (final (value, title, subtitle) in options)
                    GainerListRow(
                      title: title,
                      subtitle: subtitle,
                      trailing: value == _selected
                          ? Icon(
                              CupertinoIcons.checkmark,
                              size: 20,
                              color: colors.accent,
                            )
                          : null,
                      onTap: () => setState(() => _selected = value),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
