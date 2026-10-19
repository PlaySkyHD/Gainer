import 'package:flutter/cupertino.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../../data/repositories/training/training_preferences.dart';
import '../../../domain/models/training/training_statistics.dart';
import '../../../domain/models/training/workout_input.dart';
import '../../../domain/models/training/workout_model.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import '../cardio/cardio_feature.dart';
import '../cardio/cardio_offer_card.dart';
import 'training_format.dart';

/// Ergebnis der Zusammenfassung: „Fertig“ schließt das Training, „Training
/// fortsetzen“ öffnet es wieder.
enum WorkoutSummaryResult { done, resumed }

/// Öffnet die Zusammenfassung eines beendeten Trainings als Vollbild.
Future<WorkoutSummaryResult?> openWorkoutSummary(
  BuildContext context, {
  required TrainingLogRepository repository,
  required String workoutId,
  CardioFeature? cardio,
}) {
  return Navigator.of(context).push<WorkoutSummaryResult>(
    CupertinoPageRoute<WorkoutSummaryResult>(
      fullscreenDialog: true,
      builder: (_) => WorkoutSummaryScreen(
        repository: repository,
        workoutId: workoutId,
        cardio: cardio,
      ),
    ),
  );
}

class WorkoutSummaryScreen extends StatefulWidget {
  const WorkoutSummaryScreen({
    required this.repository,
    required this.workoutId,
    this.cardio,
    super.key,
  });

  final TrainingLogRepository repository;
  final String workoutId;

  /// Mit Cardio erscheint die Karte „Cardio anhängen“. Die Zusammenfassung
  /// öffnet nur nach dem Beenden eines aktiven Trainings, nie für historische.
  final CardioFeature? cardio;

  @override
  State<WorkoutSummaryScreen> createState() => _WorkoutSummaryScreenState();
}

/// Alle Kennzahlen der Zusammenfassung, berechnet aus `training_statistics.dart`.
class _SummaryData {
  const _SummaryData({
    required this.workout,
    required this.summary,
    required this.counts,
    required this.unit,
    required this.bodyweightMissing,
  });

  final Workout workout;
  final TrainingSummary summary;
  final WorkoutCounts counts;
  final WeightUnit unit;
  final bool bodyweightMissing;

  String exerciseName(String sourceExerciseId) {
    for (final block in workout.exercises) {
      if (block.sourceExerciseId == sourceExerciseId) {
        return block.exerciseNameSnapshot;
      }
    }
    return '';
  }
}

class _WorkoutSummaryScreenState extends State<WorkoutSummaryScreen> {
  _SummaryData? _data;
  bool _failed = false;
  bool _resuming = false;
  String? _resumeError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repository = widget.repository;
      final workout = await repository.readWorkout(widget.workoutId);
      final diary = await repository.readDiary();
      final checkIns = await repository.readCheckIns();
      final catalog = await repository.readExercises(includeArchived: true);
      final settings = await TrainingPreferences(store: repository.store)
          .read();
      if (workout == null || workout.endedAtUtc == null) {
        throw StateError('Das Training ist nicht beendet.');
      }
      final stats = workoutExerciseStats(
        workout,
        checkIns: checkIns,
        catalog: catalog,
      );
      final data = _SummaryData(
        workout: workout,
        summary: summarizeTraining(
          workout,
          history: diary,
          checkIns: checkIns,
          catalog: catalog,
        ),
        counts: workoutCounts(diary, now: workout.endedAtUtc!),
        unit: settings.weightUnit,
        bodyweightMissing: stats.any((stat) => stat.bodyweightMissing),
      );
      if (!mounted) return;
      setState(() => _data = data);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _resume() async {
    setState(() {
      _resuming = true;
      _resumeError = null;
    });
    try {
      await widget.repository.resumeWorkout(widget.workoutId);
      if (mounted) Navigator.of(context).pop(WorkoutSummaryResult.resumed);
    } on ActiveWorkoutExistsException {
      _setResumeError(
        'Ein anderes Training ist bereits aktiv. Beende es zuerst, um dieses Training fortzusetzen.',
      );
    } catch (_) {
      _setResumeError('Das Training konnte nicht fortgesetzt werden.');
    }
  }

  void _setResumeError(String message) {
    if (!mounted) return;
    setState(() {
      _resuming = false;
      _resumeError = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final data = _data;
    return CupertinoPageScaffold(
      backgroundColor: colors.background,
      child: SafeArea(
        child: data == null
            ? Center(
                child: _failed
                    ? Text(
                        'Die Zusammenfassung konnte nicht geladen werden.',
                        style: GainerTypography.body.copyWith(
                          color: colors.secondaryText,
                        ),
                      )
                    : const CupertinoActivityIndicator(),
              )
            : _content(context, data),
      ),
    );
  }

  Widget _content(BuildContext context, _SummaryData data) {
    final colors = GainerDesign.colorsOf(context);
    final summary = data.summary;
    final workout = data.workout;
    final unit = data.unit;
    final volume = formatWeight(summary.volumeKg, unit);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        GainerSpacing.m,
        GainerSpacing.l,
        GainerSpacing.m,
        GainerSpacing.l,
      ),
      children: [
        Center(
          child: Container(
            width: 96,
            height: 96,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.accent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              CupertinoIcons.checkmark_seal_fill,
              size: 52,
              color: colors.onAccent,
            ),
          ),
        ),
        const SizedBox(height: GainerSpacing.m),
        Text(
          'Stark gemacht!',
          textAlign: TextAlign.center,
          style: GainerTypography.largeTitle.copyWith(
            color: colors.primaryText,
          ),
        ),
        const SizedBox(height: GainerSpacing.xxs),
        Text(
          'Dein ${data.counts.total}. Training · ${data.counts.thisWeek}. diese Woche',
          textAlign: TextAlign.center,
          style: GainerTypography.body.copyWith(color: colors.secondaryText),
        ),
        const SizedBox(height: GainerSpacing.m),
        GainerCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                workout.title,
                style: GainerTypography.cardTitle.copyWith(
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: GainerSpacing.xxs),
              Text(
                '${formatShortDate(workout.startedAtUtc.toLocal())} · ${formatDurationMinutes(summary.duration)}',
                style: GainerTypography.label.copyWith(
                  color: colors.secondaryText,
                ),
              ),
              const SizedBox(height: GainerSpacing.m),
              Row(
                children: [
                  _Metric(
                    icon: CupertinoIcons.chart_bar_alt_fill,
                    label: 'Volumen',
                    value: '$volume ${unit.label}',
                  ),
                  _Metric(
                    icon: CupertinoIcons.square_stack_3d_up_fill,
                    label: 'Sätze',
                    value: '${summary.setCount}',
                  ),
                  _Metric(
                    icon: CupertinoIcons.repeat,
                    label: 'Wdh.',
                    value: '${summary.totalRepetitions}',
                  ),
                ],
              ),
              if (data.bodyweightMissing) ...[
                const SizedBox(height: GainerSpacing.m),
                Text(
                  'Kein Körpergewicht im Check-in gefunden. Körpergewichtsanteile fehlen in der Zusammenfassung.',
                  style: GainerTypography.caption.copyWith(
                    color: colors.secondaryText,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (widget.cardio case final cardio?) CardioOfferCard(feature: cardio),
        if (summary.bestSets.isNotEmpty) ...[
          const SizedBox(height: GainerSpacing.m),
          GainerCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TableRow(
                  left: 'Übung',
                  right: 'Bester Satz',
                  style: GainerTypography.caption.copyWith(
                    color: colors.secondaryText,
                  ),
                ),
                for (final best in summary.bestSets) ...[
                  const SizedBox(height: GainerSpacing.xs),
                  _TableRow(
                    left: data.exerciseName(best.sourceExerciseId),
                    right: _bestSetText(best.set, unit),
                    style: GainerTypography.label.copyWith(
                      color: colors.primaryText,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (summary.newRecords.isNotEmpty) ...[
          const SizedBox(height: GainerSpacing.m),
          GainerCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final record in summary.newRecords)
                  Padding(
                    padding: const EdgeInsets.only(bottom: GainerSpacing.xs),
                    child: Row(
                      children: [
                        Icon(
                          CupertinoIcons.star_fill,
                          size: 20,
                          color: colors.accent,
                        ),
                        const SizedBox(width: GainerSpacing.xs),
                        Expanded(
                          child: Text(
                            '${data.exerciseName(record.sourceExerciseId)}: Neuer Rekord: ${_recordText(record, unit)}',
                            style: GainerTypography.label.copyWith(
                              color: colors.primaryText,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: GainerSpacing.l),
        GainerPillButton(
          label: 'Fertig',
          expand: true,
          onPressed: () => Navigator.of(context).pop(WorkoutSummaryResult.done),
        ),
        const SizedBox(height: GainerSpacing.s),
        if (_resumeError case final message?) ...[
          Text(
            message,
            textAlign: TextAlign.center,
            style: GainerTypography.caption.copyWith(color: colors.destructive),
          ),
          const SizedBox(height: GainerSpacing.xs),
        ],
        CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size.square(44),
          onPressed: _resuming ? null : _resume,
          child: Text(
            'Noch nicht fertig? Training fortsetzen',
            textAlign: TextAlign.center,
            style: GainerTypography.label.copyWith(
              color: _resuming ? colors.placeholderText : colors.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

String _bestSetText(SetResult set, WeightUnit unit) {
  if (set.effectiveWeightKg <= 0) return '${set.repetitions} Wdh.';
  return '${formatWeight(set.effectiveWeightKg, unit)} ${unit.label} × ${set.repetitions}';
}

String _recordText(NewRecord record, WeightUnit unit) {
  final weight = formatWeight(record.value, unit);
  return switch (record.kind) {
    RecordKind.estimatedOneRepMax => '1RM $weight ${unit.label}',
    RecordKind.maxWeight => 'Gewicht $weight ${unit.label}',
    RecordKind.volume => 'Volumen $weight ${unit.label}',
    RecordKind.maxRepetitions => 'Wdh. ${record.value.round()}',
  };
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 22, color: colors.accent),
          const SizedBox(height: GainerSpacing.xxs),
          Text(
            value,
            style: GainerTypography.cardTitle.copyWith(
              color: colors.primaryText,
            ),
          ),
          Text(
            label,
            style: GainerTypography.caption.copyWith(
              color: colors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.left,
    required this.right,
    required this.style,
  });

  final String left;
  final String right;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(
            left,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(right, textAlign: TextAlign.end, style: style),
        ),
      ],
    );
  }
}
