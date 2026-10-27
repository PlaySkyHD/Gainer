import 'package:flutter/cupertino.dart';

import '../../../data/services/platform/platform_ports.dart';
import '../../../domain/models/cardio/cardio_template.dart';
import '../../../domain/models/cardio/cardio_zones.dart';
import '../../core/theme.dart';

/// Zahl mit deutschem Komma und Tausenderpunkt, ohne überflüssige Nachkommastellen.
String formatCardioNumber(num value, {int maxDecimals = 1}) {
  var text = value.toStringAsFixed(maxDecimals);
  if (text.contains('.')) {
    text = text
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
  final negative = text.startsWith('-');
  if (negative) text = text.substring(1);
  final parts = text.split('.');
  final digits = parts.first;
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write('.');
    grouped.write(digits[i]);
  }
  final fraction = parts.length > 1 ? ',${parts[1]}' : '';
  return '${negative ? '-' : ''}$grouped$fraction';
}

/// „132 bpm“.
String formatBpm(num value) =>
    '${formatCardioNumber(value, maxDecimals: 0)} bpm';

/// Ø-Puls mit höchstens einer Nachkommastelle: „128,5 bpm“.
String formatAverageBpm(double value) => '${formatCardioNumber(value)} bpm';

/// Pulsänderung mit Vorzeichen und Minuszeichen: „−28 bpm“, „+3 bpm“.
String formatBpmChange(int change) {
  final sign = switch (change) {
    < 0 => '−',
    > 0 => '+',
    _ => '',
  };
  return '$sign${change.abs()} bpm';
}

/// „78 %“.
String formatPercent(double share) => '${(share * 100).round()} %';

/// Dauer als „1:20 min“ (ohne führende Null bei Minuten), ab einer Stunde als
/// „1:02 h“ (Stunden:Minuten, Sekunden entfallen).
String formatCardioDuration(Duration duration) {
  final total = duration.isNegative ? Duration.zero : duration;
  if (total.inHours > 0) {
    final minutes = (total.inMinutes % 60).toString().padLeft(2, '0');
    return '${total.inHours}:$minutes h';
  }
  final seconds = (total.inSeconds % 60).toString().padLeft(2, '0');
  return '${total.inMinutes}:$seconds min';
}

/// Countdown als „0:42“ bzw. „2:30“ (Minuten ohne führende Null).
String formatCountdown(Duration remaining) {
  final total = remaining.isNegative ? Duration.zero : remaining;
  final seconds = (total.inSeconds % 60).toString().padLeft(2, '0');
  return '${total.inMinutes}:$seconds';
}

/// Statustext der Zonenlogik.
String cardioZoneLabel(HeartRateZoneState state, {required bool hasSensor}) =>
    switch (state) {
      HeartRateZoneState.inZone => 'Im Zielbereich',
      HeartRateZoneState.above => 'Zu hoch',
      HeartRateZoneState.below => 'Zu niedrig',
      HeartRateZoneState.noSignal => 'Kein Signal',
      HeartRateZoneState.none => hasSensor ? 'Kein Signal' : 'Kein Gurt',
    };

/// Farbe des Zonenstatus.
Color cardioZoneColor(
  BuildContext context,
  GainerColors colors,
  HeartRateZoneState state,
) {
  final brightness = MediaQuery.platformBrightnessOf(context);
  return switch (state) {
    HeartRateZoneState.inZone => GainerStatusColors.success(brightness),
    HeartRateZoneState.above => colors.destructive,
    HeartRateZoneState.below => GainerStatusColors.info(brightness),
    _ => colors.secondaryText,
  };
}

/// Text für ein Bluetooth-Problem.
String bluetoothProblemText(BluetoothProblem problem) => switch (problem) {
  BluetoothProblem.poweredOff =>
    'Bluetooth ist aus. Schalte es ein, um einen Gurt zu verbinden.',
  BluetoothProblem.unauthorized =>
    'Gainer darf Bluetooth nicht nutzen. Erlaube es in den Einstellungen.',
  BluetoothProblem.unsupported =>
    'Dieses Gerät unterstützt kein Bluetooth für Pulsgurte.',
};

/// Gurtzustand für Zeilen: „Verbunden · Akku 80 %“.
String cardioSensorStatus(
  HeartRateConnectionState state, {
  int? batteryPercent,
}) {
  final connection = switch (state) {
    HeartRateConnectionState.connected => 'Verbunden',
    HeartRateConnectionState.connecting ||
    HeartRateConnectionState.reconnecting => 'Verbinde …',
    HeartRateConnectionState.idle => 'Nicht verbunden',
  };
  return batteryPercent == null
      ? connection
      : '$connection · Akku $batteryPercent\u00A0%';
}

/// Dauer einer Phase als „10:00“ bzw. „1:05:00“ ab einer Stunde.
String formatPhaseDuration(int seconds) {
  final total = Duration(seconds: seconds < 0 ? 0 : seconds);
  final secs = (total.inSeconds % 60).toString().padLeft(2, '0');
  if (total.inHours > 0) {
    final minutes = (total.inMinutes % 60).toString().padLeft(2, '0');
    return '${total.inHours}:$minutes:$secs';
  }
  return '${total.inMinutes}:$secs';
}

/// Ziel einer aufgelösten Phase: „152–171 bpm“ oder „Kein Ziel“.
String formatPhaseZone(CardioPhase phase) =>
    phase.zone == null ? 'Kein Ziel' : '${phase.zone} bpm';

/// Ziel einer Vorlagenphase: „Zone 2 · 114–133“, „140–150 bpm“ oder „Kein
/// Ziel“. Ohne bekannte [zones] fehlt bei Zonenzielen die bpm-Angabe.
String formatTemplateTarget(
  CardioPhaseTarget target, [
  List<CardioZone> zones = const [],
]) {
  switch (target) {
    case CardioZoneTarget(:final number):
      final zone = zones.where((z) => z.number == number).firstOrNull;
      return zone == null
          ? 'Zone $number'
          : 'Zone $number · ${zone.lowBpm}–${zone.highBpm}';
    case CardioBpmTarget(:final low, :final high):
      return '$low–$high bpm';
    case CardioNoTarget():
      return 'Kein Ziel';
  }
}

/// Eine Zeile je Phase: „Aufwärmen 10:00 · Zone 2 · 114–133“.
String formatTemplatePhase(
  CardioTemplatePhase phase, [
  List<CardioZone> zones = const [],
]) =>
    '${phase.name} ${formatPhaseDuration(phase.durationSeconds)} · '
    '${formatTemplateTarget(phase.target, zones)}';

/// Gesamtdauer einer Vorlage: „30 min“, „1 h 5 min“.
String formatTemplateTotal(int seconds) {
  final minutes = (seconds / 60).round();
  if (minutes < 60) return '$minutes min';
  final rest = minutes % 60;
  return rest == 0 ? '${minutes ~/ 60} h' : '${minutes ~/ 60} h $rest min';
}
