import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../../../data/repositories/cardio/cardio_repository.dart';
import '../../../data/repositories/health/health_steps_sync.dart';
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
import '../nutrition/nutrition_day_kind.dart';
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
    this.onOpenCheckInDay,
    this.steps,
    this.visibility,
    this.isVisible,
    this.takeRequestedDay,
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

  /// Öffnet den Check-in des Tages `JJJJ-MM-TT`; ohne Wert nur den Tab.
  final ValueChanged<String>? onOpenCheckInDay;

  /// Schritte aus Apple Health: heute live, vergangene Tage nachgezogen.
  final HealthStepsSync? steps;

  /// Meldet Tab-Wechsel; zusammen mit [isVisible] lädt der Kalender neu,
  /// sobald der Tab wieder sichtbar wird.
  final Listenable? visibility;
  final bool Function()? isVisible;

  /// Liefert einen von außen angefragten Tag einmal (etwa aus der Heatmap der
  /// Trainingsstatistik); geprüft bei jeder Meldung von [visibility].
  final LocalDay? Function()? takeRequestedDay;

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
  late final AppLifecycleListener _lifecycle;
  Timer? _midnight;
  bool _wasVisible = true;

  /// Monatskalender unten; Ziel für „Tag auswählen“.
  final _monthGrid = GlobalKey();

  /// Schritte von heute aus Apple Health; null ohne Zugriff oder Daten.
  int? _todaySteps;

  bool get _visible => widget.isVisible?.call() ?? true;

  /// Ob [_showRequestedDayAfterFrame] schon auf das nächste Bild wartet.
  bool _requestedDayScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.visibility?.addListener(_onVisibility);
    widget.refresh?.addListener(_onRefresh);
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    _wasVisible = _visible;
    _scheduleMidnight();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showRequestedDay();
      _reloadAll();
    });
  }

  /// Wählt einen von außen angefragten Tag und scrollt zu seinen Werten.
  void _showRequestedDay() {
    if (widget.takeRequestedDay?.call() case final day?) _selectFromGrid(day);
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
    _lifecycle.dispose();
    _midnight?.cancel();
    _viewModel.dispose();
    super.dispose();
  }

  /// Lädt Kalender, Dashboard und Schritte neu.
  Future<void> _reloadAll() => Future.wait([
    _viewModel.load(),
    if (widget.overview case final overview?) overview.load(),
    _refreshSteps(),
  ]);

  /// Liest die Schritte von heute live und zieht vergangene Check-ins nach;
  /// hat sich dabei etwas geändert, lädt der Kalender die Tage neu.
  Future<void> _refreshSteps() async {
    final steps = widget.steps;
    if (steps == null) return;
    final today = await steps.today();
    if (mounted && today != _todaySteps) setState(() => _todaySteps = today);
    if (await steps.syncRecent() > 0 && mounted) await _viewModel.load();
  }

  /// Zeigt einen angefragten Tag erst nach dem nächsten Bild. Ein Tab-Wechsel
  /// schaltet Offstage und TickerMode erst dann um; vorher scrollte der
  /// Kalender unsichtbar mit stummgeschalteten Tickern.
  void _showRequestedDayAfterFrame() {
    if (_requestedDayScheduled) return;
    _requestedDayScheduled = true;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        _requestedDayScheduled = false;
        if (mounted && _visible) _showRequestedDay();
      })
      ..ensureVisualUpdate();
  }

  void _onVisibility() {
    final visible = _visible;
    if (visible) _showRequestedDayAfterFrame();
    if (visible && !_wasVisible) _reloadAll();
    _wasVisible = visible;
  }

  void _onRefresh() {
    // Ein verdeckter Kalender lädt beim nächsten Anzeigen ohnehin neu.
    if (_visible) _reloadAll();
  }

  void _onResume() {
    // Nach der Rückkehr in die App kann ein neuer Tag begonnen haben.
    if (_visible) {
      _reloadAll();
    } else {
      _viewModel.checkToday();
    }
    _scheduleMidnight();
  }

  /// Weckt kurz nach Mitternacht, damit „heute“ mitwandert, auch wenn die App
  /// über Nacht geöffnet bleibt.
  void _scheduleMidnight() {
    _midnight?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1, 0, 0, 5);
    _midnight = Timer(next.difference(now), () {
      if (!mounted) return;
      _viewModel.checkToday();
      _scheduleMidnight();
    });
  }

  Future<void> _reload() async {
    if (mounted) await _viewModel.load();
  }

  Future<void> _start(String planId) async {
    await startPlanWorkout(
      context,
      repository: widget.training,
      activeWorkout: widget.activeWorkout,
      planId: planId,
    );
    await _reload();
  }

  /// „Zählt als“ für einen Tag; ändert nur das Ernährungsziel.
  Future<void> _chooseDayKind(CalendarDay day) async {
    final nutrition = widget.nutrition;
    final target = day.nutritionTarget;
    if (nutrition == null || target == null || target.kind == null) return;
    final result = await showDayKindSheet(
      context,
      automatic: target.automaticKind,
      current: target.manual ? target.kind : null,
    );
    if (!result.changed || !mounted) return;
    try {
      await nutrition.setDayKind(day.date.toIso(), result.kind);
    } catch (_) {
      if (!mounted) return;
      await showGainerStackedDialog<bool>(
        context: context,
        title: 'Hinweis',
        message: 'Die Tagesart konnte nicht gespeichert werden.',
        actions: const [GainerDialogAction(label: 'OK', value: true)],
      );
      return;
    }
    if (mounted) await _viewModel.load();
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

  static const _scrollDuration = Duration(milliseconds: 300);

  /// Scrollt zum Kalender unten. Er ist das letzte Element; die Liste baut
  /// ihn womöglich erst beim Scrollen, daher erst ans Ende, dann ausrichten.
  Future<void> _scrollToCalendar() async {
    final scroll = PrimaryScrollController.maybeOf(context);
    if (scroll == null || !scroll.hasClients) return;
    await scroll.animateTo(
      scroll.position.maxScrollExtent,
      duration: _scrollDuration,
      curve: Curves.easeOutCubic,
    );
    if (_monthGrid.currentContext case final grid? when grid.mounted) {
      await Scrollable.ensureVisible(grid, duration: _scrollDuration);
    }
  }

  /// Tag im Kalender unten gewählt: zurück nach oben zu seinen Werten.
  void _selectFromGrid(LocalDay date) {
    _viewModel.select(date);
    final scroll = PrimaryScrollController.maybeOf(context);
    if (scroll == null || !scroll.hasClients) return;
    scroll.animateTo(0, duration: _scrollDuration, curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final model = _viewModel;
        return GainerScaffold(
          title: 'Übersicht',
          onRefresh: _reloadAll,
          leading: GainerDayNavigator(
            pillKey: const ValueKey('calendar-date-pill'),
            label: gainerDayLabel(
              model.selected.toDateTime(),
              model.today.toDateTime(),
            ),
            onPrevious: () => model.select(model.selected.addDays(-1)),
            onNext: () => model.select(model.selected.addDays(1)),
            onPick: _scrollToCalendar,
          ),
          trailing: [
            GainerToolbarButton(
              key: const ValueKey('calendar-schedule'),
              icon: CupertinoIcons.ellipsis,
              semanticLabel: 'Rhythmus',
              onPressed: _openSchedule,
            ),
          ],
          children: _children(model),
        );
      },
    );
  }

  List<Widget> _children(CalendarViewModel model) {
    final colors = GainerDesign.colorsOf(context);
    final projection = model.projection;
    final day = model.selectedDay;
    return [
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
          onOpenCheckIn: () => widget.onOpenCheckInDay == null
              ? widget.onOpenArea?.call(MobileArea.body)
              : widget.onOpenCheckInDay!(model.selected.toIso()),
          onDayKind: () => _chooseDayKind(day),
          onOpenTraining: () => widget.onOpenArea?.call(MobileArea.training),
          // Neben der Datumsüberschrift statt in der Kopfzeile: Dort
          // läge es bei langen Daten über dem Pfeil der Tages-Pille.
          onToday: model.selected == model.today ? null : model.goToToday,
          liveSteps: _todaySteps,
        ),
      // Der Kalender steht unten: Meist interessiert der heutige Tag.
      const SizedBox(height: GainerSpacing.l),
      CalendarMonthGrid(
        key: _monthGrid,
        month: model.month,
        today: model.today,
        selected: model.selected,
        markersOf: (date) =>
            model.day(date)?.markersFor(model.today) ?? const [],
        onSelect: _selectFromGrid,
        onChangeMonth: model.changeMonth,
      ),
    ];
  }
}
