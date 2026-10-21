import '../../../domain/models/training/training_schedule.dart';
import '../cardio/cardio_format.dart';
import '../training/training_format.dart';
import '../training/training_schedule_format.dart';

/// „Oktober 2026“.
String calendarMonthTitle(LocalDay month) =>
    formatMonthTitle(month.toDateTime());

/// „Donnerstag, 22. Oktober“.
String calendarDayLabel(LocalDay day) =>
    '${scheduleWeekdayLong(day.weekday - 1)}, ${day.day}. '
    '${formatMonthName(day.month)}';

/// Gewicht mit höchstens einer Nachkommastelle: „82,4 kg“, „82 kg“.
String calendarWeight(double kg) => '${formatCardioNumber(kg)} kg';

/// „2.350 von 2.600 kcal“ bzw. „2.350 kcal“ ohne Ziel.
String calendarKcal(double value, double? target) =>
    '${_withTarget(value, target)} kcal';

/// „142 von 180 g“ bzw. „142 g“ ohne Ziel.
String calendarGrams(double value, double? target) =>
    '${_withTarget(value, target)} g';

/// Ganze Zahl, die Volumen-Kennzahl der Trainingszeile: „1.200“.
String calendarWholeNumber(double value) =>
    formatCardioNumber(value, maxDecimals: 0);

String _withTarget(double value, double? target) => target == null
    ? calendarWholeNumber(value)
    : '${calendarWholeNumber(value)} von ${calendarWholeNumber(target)}';
