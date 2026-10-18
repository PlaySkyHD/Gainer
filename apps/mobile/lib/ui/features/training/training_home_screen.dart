import 'package:flutter/cupertino.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../../domain/models/cardio/cardio_session.dart';
import '../../../domain/models/training/workout_model.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import '../cardio/cardio_detail_screen.dart';
import '../cardio/cardio_feature.dart';
import '../cardio/cardio_live_screen.dart';
import '../cardio/cardio_running_card.dart';
import '../cardio/cardio_start_sheet.dart';
import 'active_workout_controller.dart';
import 'training_diary_section.dart';
import 'training_home_view_model.dart';
import 'training_plans_section.dart';
import 'training_statistics_section.dart';
import 'workout_screen.dart';

enum TrainingSegment { diary, plans, statistics }

/// Trainings-Tab mit Segmenten Tagebuch, Pläne und Statistik.
class TrainingHomeScreen extends StatefulWidget {
  const TrainingHomeScreen({
    required this.repository,
    required this.activeWorkout,
    this.cardio,
    super.key,
  });

  final TrainingLogRepository repository;
  final ActiveWorkoutController activeWorkout;

  /// Cardio mit Pulsgurt; ohne Wert entfällt der Herz-Button.
  final CardioFeature? cardio;

  @override
  State<TrainingHomeScreen> createState() => _TrainingHomeScreenState();
}

class _TrainingHomeScreenState extends State<TrainingHomeScreen> {
  late final TrainingHomeViewModel _viewModel;
  TrainingSegment _segment = TrainingSegment.diary;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _viewModel = TrainingHomeViewModel(
      repository: widget.repository,
      activeWorkout: widget.activeWorkout,
      cardio: widget.cardio?.repository,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _viewModel.loadDiary());
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _open(Workout workout) => _openById(workout.workoutId);

  Future<void> _openById(String workoutId) async {
    await openWorkoutScreen(
      context,
      repository: widget.repository,
      activeWorkout: widget.activeWorkout,
      workoutId: workoutId,
    );
    if (mounted) await _viewModel.loadDiary();
  }

  Future<void> _startCardio() async {
    final cardio = widget.cardio;
    if (cardio == null) return;
    await startOrOpenCardio(context, cardio);
    if (mounted) await _viewModel.loadDiary();
  }

  Future<void> _openCardio(CardioSession session) async {
    final cardio = widget.cardio;
    if (cardio == null) return;
    await openCardioDetail(context, cardio, session.sessionId);
    if (mounted) await _viewModel.loadDiary();
  }

  Future<void> _openRunningCardio() async {
    final cardio = widget.cardio;
    if (cardio == null) return;
    await openCardioLive(context, cardio);
    if (mounted) await _viewModel.loadDiary();
  }

  Future<void> _startWorkout() async {
    final active = widget.activeWorkout.active;
    if (active != null) {
      final resume = await showGainerStackedDialog<bool>(
        context: context,
        title: 'Aktives Training',
        message:
            'Es kann nur ein aktives Training geben. „${active.title}“ läuft noch.',
        actions: const [
          GainerDialogAction(label: 'Aktives Training fortsetzen', value: true),
          GainerDialogAction(label: 'Abbrechen', value: false),
        ],
      );
      if (resume == true && mounted) await _openById(active.workoutId);
      return;
    }
    final workoutId = await _viewModel.startEmptyWorkout();
    if (workoutId != null && mounted) await _openById(workoutId);
  }

  @override
  Widget build(BuildContext context) {
    final isDiary = _segment == TrainingSegment.diary;
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) => GainerScaffold(
        title: 'Training',
        leading: isDiary
            ? GainerPillButton(
                key: const ValueKey('training-edit-toggle'),
                label: _editing ? 'Fertig' : 'Bearbeiten',
                variant: GainerPillVariant.tonal,
                onPressed: () => setState(() => _editing = !_editing),
              )
            : null,
        trailing: [
          if (isDiary && widget.cardio != null)
            GainerToolbarButton(
              icon: CupertinoIcons.heart,
              semanticLabel: 'Cardio starten',
              onPressed: _startCardio,
            ),
          if (isDiary)
            GainerToolbarButton(
              icon: CupertinoIcons.add,
              semanticLabel: 'Leeres Training starten',
              onPressed: _startWorkout,
            ),
        ],
        children: [
          GainerSegmentedControl<TrainingSegment>(
            options: const {
              TrainingSegment.diary: 'Tagebuch',
              TrainingSegment.plans: 'Pläne',
              TrainingSegment.statistics: 'Statistik',
            },
            value: _segment,
            onChanged: (segment) => setState(() {
              _segment = segment;
              _editing = false;
            }),
          ),
          const SizedBox(height: GainerSpacing.m),
          if (isDiary && widget.cardio != null)
            CardioRunningCard(
              session: widget.cardio!.session,
              onOpen: _openRunningCardio,
            ),
          switch (_segment) {
            TrainingSegment.diary => TrainingDiarySection(
              viewModel: _viewModel,
              editing: _editing,
              onOpen: _open,
              onStart: _startWorkout,
              onOpenCardio: _openCardio,
            ),
            TrainingSegment.plans => TrainingPlansSection(
              repository: widget.repository,
              activeWorkout: widget.activeWorkout,
            ),
            TrainingSegment.statistics => TrainingStatisticsSection(
              repository: widget.repository,
            ),
          },
        ],
      ),
    );
  }
}
