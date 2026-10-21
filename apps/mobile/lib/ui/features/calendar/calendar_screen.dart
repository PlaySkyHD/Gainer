import 'package:flutter/cupertino.dart';

import '../../../data/repositories/cardio/cardio_repository.dart';
import '../../../data/repositories/nutrition/nutrition_repository.dart';
import '../../../data/repositories/training/training_log_repository.dart';
import '../../../domain/models/cardio/cardio_session.dart';
import '../../../domain/models/training/training_schedule.dart';
import '../../../domain/models/training/workout_model.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import '../../core/view_models/mobile_shell_view_model.dart';
import '../cardio/cardio_detail_screen.dart';
import '../cardio/cardio_feature.dart';
import '../progress/progress_view_model.dart';
import '../training/active_workout_controller.dart';
import '../training/plan_start.dart';
import '../training/schedule_day_actions.dart';
import '../training/training_schedule_sheet.dart';
import '../training/workout_screen.dart';
import 'calendar_day_view.dart';
import 'calendar_month_grid.dart';
import 'calendar_view_model.dart';

/// Tab „Kalender“: Monatsraster mit Markierungen und darunter die
/// Tagesansicht des gewählten Tages. Rechnet nur mit lokalen Daten.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({
    required this.training,
    required this.activeWorkout,
    this.cardioSessions,
    this.cardio,
    this.nutrition,
    this.overview,
    this.onOpenArea,
    this.onOpenNutritionDay,
    this.visibility,
    this.isVisible,
    this.refresh,
    super.key,
  });

  final TrainingLogRepository training;
  final ActiveWorkoutController activeWorkout;

  /// Cardio-Einheiten für die Markierungen.
  final CardioRepository? cardioSessions;

  /// Öffnet die Detailansicht einer Cardio-Einheit; ohne Wert nicht antippbar.
  final CardioFeature? cardio;
  final NutritionRepository? nutrition;

  /// Dashboard-Daten des früheren Heute-Tabs für die Ansicht von heute.
  final ProgressViewModel? overview;

  /// Wechselt in einen anderen Tab.
  final ValueChanged<MobileArea>? onOpenArea;

  /// Öffnet den Tab „Essen“ für den Tag `JJJJ-MM-TT`.
  final ValueChanged<String>? onOpenNutritionDay;

  /// Meldet Tab-Wechsel; zusammen mit [isVisible] lädt der Kalender neu,
  /// sobald der Tab wieder sichtbar wird.
  final Listenable? visibility;
  final bool Function()? isVisible;

  /// Meldet geänderte Daten, etwa nach einem Sync; der Kalender lädt dann
  /// neu, wenn er sichtbar ist.
  final Listenable? refresh;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late final CalendarViewModel _viewModel = CalendarViewModel(
    training: widget.training,
    cardio: widget.cardioSessions ?? widget.cardio?.repository,
    nutrition: widget.nutrition,
  );
  bool _wasVisible = true;

  bool get _visible => widget.isVisible?.call() ?? true;

  @override
  void initState() {
    super.initState();
    widget.visibility?.addListener(_onVisibility);
    widget.refresh?.addListener(_onRefresh);
    _wasVisible = _visible;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _viewModel.load();
      widget.overview?.load();
    });
  }

  @override
  void didUpdateWidget(CalendarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.visibility, widget.visibility)) {
      oldWidget.visibility?.removeListener(_onVisibility);
      widget.visibility?.addListener(_onVisibility);
    }
    if (!identical(oldWidget.refresh, widget.refresh)) {
      oldWidget.refresh?.removeListener(_onRefresh);
      widget.refresh?.addListener(_onRefresh);
    }
  }

  @override
  void dispose() {
    widget.visibility?.removeListener(_onVisibility);
    widget.refresh?.removeListener(_onRefresh);
    _viewModel.dispose();
    super.dispose();
  }

  void _onVisibility() {
    final visible = _visible;
    if (visible && !_wasVisible) _viewModel.load();
    _wasVisible = visible;
  }

  void _onRefresh() {
    // Ein verdeckter Kalender lädt beim nächsten Anzeigen ohnehin neu.
    if (_visible) _viewModel.load();
  }

  Future<void> _reload() async {
    if (mounted) await _viewModel.load();
  }

  Future<void> _refreshAll() => Future.wait([
    _viewModel.load(),
    if (widget.overview case final overview?) overview.load(),
  ]);

  Future<void> _start(String planId) async {
    await startPlanWorkout(
      context,
      repository: widget.training,
      activeWorkout: widget.activeWorkout,
      planId: planId,
    );
    await _reload();
  }

  Future<void> _openSchedule() async {
    final changed = await showTrainingScheduleSheet(
      context,
      repository: widget.training,
    );
    if (changed) await _reload();
  }

  Future<void> _openActions(ScheduledTraining training) async {
    final projection = _viewModel.projection;
    if (projection == null) return;
    final changed = await showScheduledTrainingActions(
      context,
      repository: widget.training,
      projection: projection,
      training: training,
    );
    if (changed) await _reload();
  }

  Future<void> _openWorkout(Workout workout) async {
    await openWorkoutScreen(
      context,
      repository: widget.training,
      activeWorkout: widget.activeWorkout,
      workoutId: workout.workoutId,
    );
    await _reload();
  }

  Future<void> _openCardio(CardioSession session) async {
    final cardio = widget.cardio;
    if (cardio == null) return;
    await openCardioDetail(context, cardio, session.sessionId);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final model = _viewModel;
        final colors = GainerDesign.colorsOf(context);
        final projection = model.projection;
        final day = model.selectedDay;
        return GainerScaffold(
          title: 'Kalender',
          onRefresh: _refreshAll,
          trailing: [
            GainerPillButton(
              key: const ValueKey('calendar-today'),
              label: 'Heute',
              variant: GainerPillVariant.tonal,
              onPressed: model.goToToday,
            ),
            GainerToolbarButton(
              key: const ValueKey('calendar-schedule'),
              icon: CupertinoIcons.ellipsis,
              semanticLabel: 'Rhythmus',
              onPressed: _openSchedule,
            ),
          ],
          children: [
            CalendarMonthGrid(
              month: model.month,
              today: model.today,
              selected: model.selected,
              markersOf: (date) =>
                  model.day(date)?.markersFor(model.today) ?? const [],
              onSelect: model.select,
              onChangeMonth: model.changeMonth,
            ),
            const SizedBox(height: GainerSpacing.l),
            if (model.errorMessage case final message?) ...[
              Text(
                message,
                style: GainerTypography.body.copyWith(color: colors.warning),
              ),
              const SizedBox(height: GainerSpacing.m),
            ],
            if (projection == null || day == null)
              if (model.isLoading)
                const Center(child: CupertinoActivityIndicator())
              else
                const SizedBox.shrink()
            else
              CalendarDayView(
                day: day,
                today: model.today,
                projection: projection,
                overview: widget.overview,
                onStart: _start,
                onSetup: _openSchedule,
                onActions: _openActions,
                onOpenWorkout: _openWorkout,
                onOpenCardio: widget.cardio == null ? null : _openCardio,
                onOpenNutrition: () =>
                    widget.onOpenNutritionDay?.call(model.selected.toIso()),
                onOpenCheckIn: () => widget.onOpenArea?.call(MobileArea.body),
                onOpenTraining: () =>
                    widget.onOpenArea?.call(MobileArea.training),
              ),
          ],
        );
      },
    );
  }
}
