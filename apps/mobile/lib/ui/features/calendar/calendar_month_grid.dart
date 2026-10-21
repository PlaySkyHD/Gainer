import 'package:flutter/cupertino.dart';

import '../../../domain/models/training/training_schedule.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'calendar_format.dart';
import 'calendar_view_model.dart';

/// Monatsraster ab Montag mit Markierungen je Tag. Wischen nach links oder
/// rechts wechselt den Monat; die Pfeile tun dasselbe für VoiceOver.
class CalendarMonthGrid extends StatelessWidget {
  const CalendarMonthGrid({
    required this.month,
    required this.today,
    required this.selected,
    required this.markersOf,
    required this.onSelect,
    required this.onChangeMonth,
    super.key,
  });

  /// Erster Tag des angezeigten Monats.
  final LocalDay month;
  final LocalDay today;
  final LocalDay selected;
  final List<CalendarMarker> Function(LocalDay day) markersOf;
  final ValueChanged<LocalDay> onSelect;

  /// −1 für den Vormonat, +1 für den nächsten Monat.
  final ValueChanged<int> onChangeMonth;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final days = CalendarViewModel.visibleDaysOf(month);
    return GestureDetector(
      key: const ValueKey('calendar-month-grid'),
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity.abs() < 200) return;
        onChangeMonth(velocity < 0 ? 1 : -1);
      },
      child: GainerCard(
        padding: const EdgeInsets.fromLTRB(
          GainerSpacing.s,
          GainerSpacing.xs,
          GainerSpacing.s,
          GainerSpacing.s,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: GainerSpacing.xxs),
                    child: Semantics(
                      header: true,
                      child: Text(
                        calendarMonthTitle(month),
                        key: const ValueKey('calendar-month-title'),
                        style: GainerTypography.cardTitle.copyWith(
                          color: colors.primaryText,
                        ),
                      ),
                    ),
                  ),
                ),
                _MonthButton(
                  icon: CupertinoIcons.chevron_left,
                  label: 'Vorheriger Monat',
                  onPressed: () => onChangeMonth(-1),
                ),
                _MonthButton(
                  icon: CupertinoIcons.chevron_right,
                  label: 'Nächster Monat',
                  onPressed: () => onChangeMonth(1),
                ),
              ],
            ),
            const SizedBox(height: GainerSpacing.xxs),
            // Das Raster wächst nur begrenzt mit der Textgröße, damit sieben
            // Spalten auch bei Textgröße 2 ohne Überlauf passen.
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.4,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth / 7;
                  final scale = MediaQuery.textScalerOf(context).scale(1);
                  final diameter = (32 * scale).clamp(28.0, width - 2);
                  return Column(
                    children: [
                      ExcludeSemantics(
                        child: Row(
                          children: [
                            for (final name in calendarWeekdayShort)
                              SizedBox(
                                width: width,
                                child: Text(
                                  name,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.clip,
                                  style: GainerTypography.caption.copyWith(
                                    color: colors.secondaryText,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: GainerSpacing.xxs),
                      for (var week = 0; week < days.length ~/ 7; week++)
                        Row(
                          children: [
                            for (final day in days.skip(week * 7).take(7))
                              SizedBox(
                                width: width,
                                child: _DayCell(
                                  day: day,
                                  diameter: diameter,
                                  inMonth: day.month == month.month,
                                  isToday: day == today,
                                  isSelected: day == selected,
                                  markers: markersOf(day),
                                  onTap: () => onSelect(day),
                                ),
                              ),
                          ],
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthButton extends StatelessWidget {
  const _MonthButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        onPressed: onPressed,
        child: Icon(icon, size: 20, color: colors.accent),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.diameter,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.markers,
    required this.onTap,
  });

  final LocalDay day;
  final double diameter;
  final bool inMonth;
  final bool isToday;
  final bool isSelected;
  final List<CalendarMarker> markers;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final Color textColor;
    if (isSelected) {
      textColor = colors.onAccent;
    } else if (isToday) {
      textColor = colors.accent;
    } else if (inMonth) {
      textColor = colors.primaryText;
    } else {
      textColor = colors.placeholderText;
    }
    final label = [
      if (isToday) 'Heute',
      calendarDayLabel(day),
      for (final marker in markers) marker.label,
    ].join(', ');
    return Semantics(
      key: ValueKey('calendar-day-${day.toIso()}'),
      button: true,
      selected: isSelected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: diameter,
                height: diameter,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected
                      ? (isToday ? colors.accent : colors.primaryText)
                      : null,
                ),
                child: Text(
                  '${day.day}',
                  maxLines: 1,
                  style: GainerTypography.body.copyWith(
                    color: isSelected && !isToday
                        ? colors.background
                        : textColor,
                    fontWeight: isToday || isSelected
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              SizedBox(
                height: _dotSize,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < markers.length; i++) ...[
                      if (i > 0) const SizedBox(width: 2),
                      CalendarMarkerDot(marker: markers[i]),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const double _dotSize = 6;

/// Punkt einer Markierung: erledigt gefüllt, geplant als Ring, verpasst als
/// Ring in Warnfarbe.
class CalendarMarkerDot extends StatelessWidget {
  const CalendarMarkerDot({required this.marker, super.key});

  final CalendarMarker marker;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final brightness = CupertinoTheme.brightnessOf(context);
    final (Color color, bool filled) = switch (marker) {
      CalendarMarker.strength => (colors.accent, true),
      CalendarMarker.cardio => (GainerStatusColors.cardio(brightness), true),
      CalendarMarker.checkIn => (colors.secondaryText, true),
      CalendarMarker.planned => (colors.accent, false),
      CalendarMarker.missed => (colors.warning, false),
    };
    return Container(
      width: _dotSize,
      height: _dotSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? color : null,
        border: filled ? null : Border.all(color: color, width: 1.5),
      ),
    );
  }
}
