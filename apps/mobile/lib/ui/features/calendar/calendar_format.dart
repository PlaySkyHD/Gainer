import '../../../domain/models/training/training_schedule.dart';
import '../progress/today_overview.dart';

const calendarWeekdayShort = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

const _weekdayLong = [
  'Montag',
  'Dienstag',
  'Mittwoch',
  'Donnerstag',
  'Freitag',
  'Samstag',
  'Sonntag',
];

const _months = [
  'Januar',
  'Februar',
  'März',
  'April',
  'Mai',
  'Juni',
  'Juli',
  'August',
  'September',
  'Oktober',
  'November',
  'Dezember',
];

/// „Oktober 2026“.
String calendarMonthTitle(LocalDay month) =>
    '${_months[month.month - 1]} ${month.year}';

/// „Donnerstag, 22. Oktober“.
String calendarDayLabel(LocalDay day) =>
    '${_weekdayLong[day.weekday - 1]}, ${day.day}. ${_months[day.month - 1]}';

/// Gewicht mit höchstens einer Nachkommastelle: „82,4 kg“, „82 kg“.
String calendarWeight(double kg) {
  final rounded = (kg * 10).round() / 10;
  final digits = rounded == rounded.roundToDouble() ? 0 : 1;
  return '${formatGermanNumber(rounded, digits: digits)} kg';
}

/// „2.350 von 2.600 kcal“ bzw. „2.350 kcal“ ohne Ziel.
String calendarKcal(double value, double? target) => target == null
    ? '${formatGermanNumber(value)} kcal'
    : '${formatGermanNumber(value)} von ${formatGermanNumber(target)} kcal';

/// „142 von 180 g“ bzw. „142 g“ ohne Ziel.
String calendarGrams(double value, double? target) => target == null
    ? '${formatGermanNumber(value)} g'
    : '${formatGermanNumber(value)} von ${formatGermanNumber(target)} g';
