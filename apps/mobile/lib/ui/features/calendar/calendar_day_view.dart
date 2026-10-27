import 'package:flutter/cupertino.dart';

import '../../../domain/models/cardio/cardio_analysis.dart';
import '../../../domain/models/cardio/cardio_session.dart';
import '../../../domain/models/training/training_schedule.dart';
import '../../../domain/models/training/workout_model.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import '../body/check_in_format.dart';
import '../cardio/cardio_format.dart';
import '../progress/progress_view_model.dart';
import '../progress/today_overview.dart';
import '../training/training_format.dart';
import '../training/training_schedule_format.dart';
import '../training/training_today_card.dart';
import 'calendar_format.dart';
import 'calendar_nutrition_overview.dart';
import 'calendar_view_model.dart';

/// Tagesansicht unter dem Monatsraster: gruppierte Karten für Plan,
/// Training, Ernährung und Check-in, jede nur mit Inhalt. Für heute kommen
/// Gewichtsverlauf und Trainingsübersicht aus [overview] dazu.
class CalendarDayView extends StatelessWidget {
  const CalendarDayView({
    required this.day,
    required this.today,
    required this.projection,
    required this.onStart,
    required this.onSetup,
    required this.onActions,
    required this.onOpenWorkout,
    required this.onOpenNutrition,
    required this.onOpenCheckIn,
    this.onDayKind,
    this.onOpenCardio,
    this.onOpenTraining,
    this.onToday,
    this.liveSteps,
    this.overview,
    super.key,
  });

  final CalendarDay day;
  final LocalDay today;
  final TrainingScheduleProjection projection;

  /// Startet ein Training aus dem Plan (nur heute).
  final ValueChanged<String> onStart;

  /// Öffnet den Rhythmus-Editor.
  final VoidCallback onSetup;

  /// Tagesaktionen für ein geplantes Training.
  final ValueChanged<ScheduledTraining> onActions;
  final ValueChanged<Workout> onOpenWorkout;
  final ValueChanged<CardioSession>? onOpenCardio;
  final VoidCallback onOpenNutrition;
  final VoidCallback onOpenCheckIn;

  /// Öffnet „Zählt als“ für die Tagesart des Tages.
  final VoidCallback? onDayKind;

  /// Öffnet den Trainings-Tab aus der Trainingsübersicht.
  final VoidCallback? onOpenTraining;

  /// Zurück zum heutigen Tag; null, wenn heute gezeigt wird.
  final VoidCallback? onToday;

  /// Schritte von heute aus Apple Health. Sie ersetzen für heute den Wert des
  /// Check-ins, der meist morgens gespeichert wurde.
  final int? liveSteps;

  /// Dashboard-Daten des früheren Heute-Tabs; nur für heute gesetzt.
  final ProgressViewModel? overview;

  bool get _isToday => day.date == today;

  @override
  Widget build(BuildContext context) {
    final dashboard = overview;
    if (_isToday && dashboard != null) {
      return ListenableBuilder(
        listenable: dashboard,
        builder: (context, _) => _content(context, dashboard),
      );
    }
    return _content(context, null);
  }

  Widget _content(BuildContext context, ProgressViewModel? dashboard) {
    final colors = GainerDesign.colorsOf(context);
    final sections = _sections(dashboard);
    final emptyText = _emptyText(sections);

    return Column(
      key: ValueKey('calendar-day-view-${day.date.toIso()}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(colors),
        const SizedBox(height: GainerSpacing.s),
        for (var i = 0; i < sections.length; i++) ...[
          if (i > 0) const SizedBox(height: GainerSpacing.m),
          sections[i],
        ],
        if (emptyText != null) ...[
          if (sections.isNotEmpty) const SizedBox(height: GainerSpacing.m),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: GainerSpacing.xxs,
              vertical: GainerSpacing.xs,
            ),
            child: Text(
              emptyText,
              key: const ValueKey('calendar-day-empty'),
              style: GainerTypography.body.copyWith(
                color: colors.secondaryText,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _header(GainerColors colors) => Row(
    children: [
      Expanded(child: GainerSectionHeader(title: calendarDayLabel(day.date))),
      if (onToday case final toToday?)
        CupertinoButton(
          key: const ValueKey('calendar-today'),
          padding: const EdgeInsets.symmetric(horizontal: GainerSpacing.xs),
          minimumSize: const Size(0, GainerRadii.iconButtonDiameter),
          onPressed: toToday,
          child: Text(
            'Zu heute',
            style: GainerTypography.label.copyWith(
              color: colors.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
    ],
  );

  List<Widget> _sections(ProgressViewModel? dashboard) {
    final plan = _isToday
        ? TrainingTodayCard(
            projection: projection,
            onStart: onStart,
            onSetup: onSetup,
            onActions: onActions,
          )
        : _planSection();
    return [
      ?plan,
      ?_trainingSection(),
      // Ernährung zuerst: Sie ändert sich über den Tag am meisten.
      ?_nutritionSection(),
      if (dashboard != null &&
          (dashboard.dashboard != null ||
              dashboard.errorMessage != null ||
              dashboard.isLoading))
        TodayWeightOverview(
          viewModel: dashboard,
          today: today.toDateTime(),
          todayWeightKg: day.checkIn?.weightKg,
          onTap: onOpenCheckIn,
        ),
      if (dashboard != null && dashboard.dashboard != null)
        TodayTrainingOverview(viewModel: dashboard, onTap: onOpenTraining),
      ?_checkInSection(dashboard),
    ];
  }

  String? _emptyText(List<Widget> sections) {
    final isPast = day.date.isBefore(today);
    if (isPast && !day.hasEntries) return 'Keine Einträge';
    if (!isPast && !_isToday && sections.isEmpty) return 'Nichts geplant';
    return null;
  }

  Widget? _planSection() {
    final schedule = day.schedule;
    final rows = <Widget>[
      for (final training in schedule.trainings)
        _PlanRow(
          training: training,
          today: today,
          actionable: projection.actionsFor(training).isNotEmpty,
          onActions: () => onActions(training),
        ),
    ];
    if (rows.isEmpty) {
      switch (schedule.baseKind) {
        case ScheduleBaseKind.rest:
          rows.add(
            const GainerListRow(
              title: 'Ruhetag',
              leadingIcon: CupertinoIcons.moon,
            ),
          );
        case ScheduleBaseKind.paused:
          rows.add(
            const GainerListRow(
              title: 'Pausiert',
              subtitle: 'Der Rhythmus wurde verschoben.',
              leadingIcon: CupertinoIcons.pause_circle,
            ),
          );
        case ScheduleBaseKind.none:
        case ScheduleBaseKind.training:
          return null;
      }
    }
    return GainerGroupedSection(
      key: const ValueKey('calendar-plan-card'),
      header: 'Plan',
      children: rows,
    );
  }

  Widget? _trainingSection() {
    if (day.workouts.isEmpty && day.cardio.isEmpty) return null;
    return GainerGroupedSection(
      key: const ValueKey('calendar-training-card'),
      header: 'Training',
      children: [
        for (final item in day.workouts)
          GainerListRow(
            title: item.workout.title,
            subtitle: [
              formatDurationMinutes(item.duration),
              if (item.volumeKg > 0)
                'Volumen ${calendarWholeNumber(item.volumeKg)} kg',
            ].join(' · '),
            leadingIcon: CupertinoIcons.sportscourt,
            showChevron: true,
            onTap: () => onOpenWorkout(item.workout),
          ),
        for (final session in day.cardio)
          GainerListRow(
            title: session.activityType.label,
            subtitle: _cardioSummary(session),
            leadingIcon: CupertinoIcons.heart,
            showChevron: onOpenCardio != null,
            onTap: onOpenCardio == null ? null : () => onOpenCardio!(session),
          ),
      ],
    );
  }

  String _cardioSummary(CardioSession session) {
    final analysis = CardioAnalysis.of(session);
    final average = analysis.averageBpm;
    return [
      formatCardioDuration(session.endedAtUtc.difference(session.startedAtUtc)),
      if (average != null) 'Ø ${formatBpm(average.round())}',
    ].join(' · ');
  }

  /// Heute immer (auch ohne Einträge), vergangene Tage nur mit erfasster
  /// Ernährung, künftige Tage nie.
  Widget? _nutritionSection() {
    if (day.date.isAfter(today)) return null;
    final nutrition =
        day.nutrition ??
        (_isToday ? CalendarNutrition.empty(day.nutritionTarget) : null);
    if (nutrition == null) return null;
    return CalendarNutritionOverview(
      nutrition: nutrition,
      onTap: onOpenNutrition,
      onDayKind: onDayKind,
    );
  }

  Widget? _checkInSection(ProgressViewModel? dashboard) {
    final checkIn = day.checkIn;
    final steps = (_isToday ? liveSteps : null) ?? checkIn?.steps;
    if (checkIn == null) {
      // Heute ohne Check-in: die Schritte aus Apple Health trotzdem zeigen.
      if (!_isToday || steps == null) return null;
      return GainerGroupedSection(
        key: const ValueKey('calendar-checkin-card'),
        header: 'Check-in',
        children: [
          _ValueRow(
            label: 'Schritte',
            value: formatStepCount(steps),
            onTap: onOpenCheckIn,
          ),
        ],
      );
    }
    // Heute zeigt die Gewichtskarte das lokal erfasste Gewicht; es steht
    // dann nicht noch einmal im Check-in.
    final weightShown = _isToday && dashboard?.dashboard != null;
    final rows = <Widget>[
      if (!weightShown)
        _ValueRow(
          label: 'Gewicht',
          value: calendarWeight(checkIn.weightKg),
          onTap: onOpenCheckIn,
        ),
      if (steps != null)
        _ValueRow(
          label: 'Schritte',
          value: formatStepCount(steps),
          onTap: onOpenCheckIn,
        ),
      if (checkIn.sleepMinutes case final minutes?)
        _ValueRow(
          label: 'Schlaf',
          value: formatSleepDuration(minutes),
          onTap: onOpenCheckIn,
        ),
      if (checkIn.restingHeartRateBpm case final rate?)
        _ValueRow(
          label: 'Ruhepuls',
          value: formatBpm(rate),
          onTap: onOpenCheckIn,
        ),
      if (checkIn.restingHrvMs case final hrv?)
        _ValueRow(label: 'HRV', value: '$hrv ms', onTap: onOpenCheckIn),
    ];
    if (rows.isEmpty) return null;
    return GainerGroupedSection(
      key: const ValueKey('calendar-checkin-card'),
      header: 'Check-in',
      children: rows,
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({
    required this.training,
    required this.today,
    required this.actionable,
    required this.onActions,
  });

  final ScheduledTraining training;
  final LocalDay today;
  final bool actionable;
  final VoidCallback onActions;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final status = scheduledStatusLabel(training, today);
    final subtitle = training.isMovedIn
        ? '$status · von ${scheduleDayShort(training.originDate, today)}'
        : status;
    final (IconData? icon, Color color) = switch (training.status) {
      ScheduledTrainingStatus.done => (
        CupertinoIcons.checkmark_circle_fill,
        colors.accent,
      ),
      ScheduledTrainingStatus.missed => (
        CupertinoIcons.exclamationmark_circle,
        colors.warning,
      ),
      ScheduledTrainingStatus.skipped || ScheduledTrainingStatus.moved => (
        CupertinoIcons.arrow_right_circle,
        colors.secondaryText,
      ),
      ScheduledTrainingStatus.insteadOf => (
        CupertinoIcons.arrow_2_squarepath,
        colors.secondaryText,
      ),
      ScheduledTrainingStatus.planned => (null, colors.accent),
    };
    return Semantics(
      hint: actionable ? 'Tippen für Tagesaktionen' : null,
      child: GainerListRow(
        key: ValueKey('calendar-plan-${training.planId}'),
        title: training.planName,
        subtitle: subtitle,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) Icon(icon, size: 20, color: color),
            if (actionable) ...[
              if (icon != null) const SizedBox(width: GainerSpacing.s),
              Icon(
                CupertinoIcons.ellipsis_circle,
                size: 22,
                color: colors.accent,
              ),
            ],
          ],
        ),
        onTap: actionable ? onActions : null,
      ),
    );
  }
}

/// Zeile mit Beschriftung und Wert. Bei großer Schrift steht der Wert unter
/// der Beschriftung, damit keine Wörter mitten im Wort umbrechen.
class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.4;
    return stacked
        ? GainerListRow(
            title: label,
            subtitle: value,
            showChevron: true,
            onTap: onTap,
          )
        : GainerListRow(
            title: label,
            value: value,
            showChevron: true,
            onTap: onTap,
          );
  }
}
