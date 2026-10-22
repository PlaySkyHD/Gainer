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
    '${_withTarget(value, target, 0)} kcal';

/// „142 von 180 g“ bzw. „142 g“ ohne Ziel.
String calendarGrams(double value, double? target, {int decimals = 0}) =>
    '${_withTarget(value, target, decimals)} g';

/// Makro-Fortschritt kompakt: „120 / 332 g“, ohne Ziel „120 g“, ohne Wert
/// „– / 332 g“. Salz nutzt eine Nachkommastelle ([decimals]).
String calendarGramsOf(double? value, double? target, {int decimals = 0}) {
  String number(double v) => formatCardioNumber(v, maxDecimals: decimals);
  final actual = value == null ? '–' : number(value);
  return target == null ? '$actual g' : '$actual / ${number(target)} g';
}

/// Ganze Zahl, die Volumen-Kennzahl der Trainingszeile: „1.200“.
String calendarWholeNumber(double value) =>
    formatCardioNumber(value, maxDecimals: 0);

String _withTarget(double value, double? target, int decimals) {
  String number(double v) => formatCardioNumber(v, maxDecimals: decimals);
  return target == null
      ? number(value)
      : '${number(value)} von ${number(target)}';
}
