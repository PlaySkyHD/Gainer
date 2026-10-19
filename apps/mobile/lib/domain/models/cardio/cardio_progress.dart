import 'cardio_analysis.dart';
import 'cardio_session.dart';
import 'cardio_zones.dart';

/// Eine Woche (Montag bis Sonntag, lokal) der Cardio-Statistik.
class CardioWeek {
  const CardioWeek({
    required this.start,
    required this.timeInTarget,
    required this.timeInZone2,
    required this.sessionCount,
    required this.totalDuration,
  });

  /// Montag 00:00 lokal.
  final DateTime start;

  /// Summe der Zeit im Zielbereich der jeweiligen Einheit.
  final Duration timeInTarget;

  /// Zeit in Zone 2 der aktuellen Einstellungen; null ohne Zonen.
  final Duration? timeInZone2;
  final int sessionCount;
  final Duration totalDuration;

  /// Ganze Minuten im Zielbereich (gerundet).
  int get targetMinutes => _minutes(timeInTarget);
  int? get zone2Minutes => timeInZone2 == null ? null : _minutes(timeInZone2!);
}

/// Effizienzfaktor einer Einheit: Ø-Leistung ÷ Ø-Puls.
class CardioEfficiencyPoint {
  const CardioEfficiencyPoint({
    required this.sessionId,
    required this.startedAtUtc,
    required this.efficiency,
    required this.averageBpm,
    required this.powerWatts,
  });

  final String sessionId;
  final DateTime startedAtUtc;

  /// Auf zwei Nachkommastellen gerundet.
  final double efficiency;
  final double averageBpm;
  final double powerWatts;
}

/// „bei 150 W: 138 → 131 bpm“.
class CardioSamePowerComparison {
  const CardioSamePowerComparison({
    required this.powerWatts,
    required this.firstBpm,
    required this.lastBpm,
    required this.sessionCount,
  });

  /// Leistungsstufe, auf 10 W gerundet.
  final int powerWatts;
  final int firstBpm;
  final int lastBpm;
  final int sessionCount;
}

/// Auswertung der Cardio-Einheiten über mehrere Wochen, rein aus lokalen
/// Daten. Wie [CardioAnalysis] bewusst im Client berechnet, damit sie offline
/// verfügbar ist.
class CardioProgress {
  const CardioProgress({
    required this.weeks,
    required this.weeklyTargetMinutes,
    required this.efficiency,
    required this.samePower,
    required this.recoveryAverageBpm,
    required this.recoverySampleCount,
    required this.hasSessions,
  });

  static const weekCount = 8;
  static const efficiencyPointCount = 20;
  static const minSamePowerSessions = 3;
  static const recoverySessionCount = 5;

  /// Älteste Woche zuerst; die letzte ist die laufende Woche.
  final List<CardioWeek> weeks;
  final int weeklyTargetMinutes;

  /// Letzte höchstens 20 Einheiten mit Leistung und Puls, älteste zuerst.
  final List<CardioEfficiencyPoint> efficiency;
  final CardioSamePowerComparison? samePower;

  /// Mittlerer Pulsabfall der letzten 5 Einheiten mit Erholung (negativ), auf
  /// ganze bpm gerundet; null ohne Erholungswerte.
  final int? recoveryAverageBpm;
  final int recoverySampleCount;

  /// Mindestens eine Einheit in den letzten [weekCount] Wochen.
  final bool hasSessions;

  CardioWeek get currentWeek => weeks.last;

  /// Ob die Zone-2-Ansicht möglich ist (Zonen konfiguriert).
  bool get hasZone2 => weeks.isNotEmpty && weeks.last.timeInZone2 != null;

  /// „Diese Woche 95 / 150 min · 3 Einheiten · 1:42 h“.
  String currentWeekSummary({bool zone2 = false}) {
    final week = currentWeek;
    final minutes = zone2 ? (week.zone2Minutes ?? 0) : week.targetMinutes;
    final count = week.sessionCount == 1
        ? '1 Einheit'
        : '${week.sessionCount} Einheiten';
    return 'Diese Woche $minutes / $weeklyTargetMinutes min · $count · '
        '${formatHoursMinutes(week.totalDuration)}';
  }

  /// Berechnet die Auswertung. [now] bestimmt die laufende Woche (lokal).
  /// [zones] sind die Zonen der aktuellen Einstellungen; ohne sie entfällt
  /// „Zone 2“.
  factory CardioProgress.compute(
    List<CardioSession> sessions, {
    required DateTime now,
    int weeklyTargetMinutes = 150,
    List<CardioZone> zones = const [],
  }) {
    final firstWeek = _weekStart(now);
    final starts = [
      for (var i = weekCount - 1; i >= 0; i--)
        DateTime(firstWeek.year, firstWeek.month, firstWeek.day - 7 * i),
    ];
    final zone2 = zones.where((zone) => zone.number == 2).firstOrNull;
    final targetTime = List.filled(weekCount, Duration.zero);
    final zone2Time = List.filled(weekCount, Duration.zero);
    final counts = List.filled(weekCount, 0);
    final totals = List.filled(weekCount, Duration.zero);
    var any = false;

    final ordered = [...sessions]
      ..sort((a, b) => a.startedAtUtc.compareTo(b.startedAtUtc));
    for (final session in ordered) {
      if (session.deletedAtUtc != null) continue;
      final index = _indexOf(
        starts,
        _weekStart(session.startedAtUtc.toLocal()),
      );
      if (index < 0) continue;
      any = true;
      final analysis = CardioAnalysis.of(session);
      targetTime[index] += analysis.timeInZone;
      counts[index]++;
      totals[index] += session.duration;
      if (zone2 != null) {
        final inZone = session.heartRateBpm
            .where(
              (bpm) => bpm > 0 && bpm >= zone2.lowBpm && bpm < zone2.highBpm,
            )
            .length;
        zone2Time[index] += Duration(
          seconds: inZone * session.sampleIntervalSeconds,
        );
      }
    }

    // Effizienz und Vergleich: alle Einheiten mit Leistung und Puls.
    final points = <CardioEfficiencyPoint>[];
    for (final session in ordered) {
      if (session.deletedAtUtc != null) continue;
      final power = session.averagePowerWatts;
      final average = CardioAnalysis.of(session).averageBpm;
      if (power == null || power <= 0 || average == null) continue;
      points.add(
        CardioEfficiencyPoint(
          sessionId: session.sessionId,
          startedAtUtc: session.startedAtUtc,
          efficiency: (power / average * 100).round() / 100,
          averageBpm: average,
          powerWatts: power,
        ),
      );
    }

    final recovered = [
      for (final session in ordered.reversed)
        if (session.deletedAtUtc == null && session.recoveryDropBpm != null)
          session.recoveryDropBpm!,
    ].take(recoverySessionCount).toList();

    return CardioProgress(
      weeks: [
        for (var i = 0; i < weekCount; i++)
          CardioWeek(
            start: starts[i],
            timeInTarget: targetTime[i],
            timeInZone2: zone2 == null ? null : zone2Time[i],
            sessionCount: counts[i],
            totalDuration: totals[i],
          ),
      ],
      weeklyTargetMinutes: weeklyTargetMinutes,
      efficiency: points.length > efficiencyPointCount
          ? points.sublist(points.length - efficiencyPointCount)
          : points,
      samePower: _samePower(points),
      recoveryAverageBpm: recovered.isEmpty
          ? null
          : (recovered.reduce((a, b) => a + b) / recovered.length).round(),
      recoverySampleCount: recovered.length,
      hasSessions: any,
    );
  }

  /// Häufigste Leistungsstufe (auf 10 W gerundet) ab drei Einheiten; bei
  /// Gleichstand die höhere Stufe. Erster und letzter Ø-Puls nach Startzeit.
  static CardioSamePowerComparison? _samePower(
    List<CardioEfficiencyPoint> points,
  ) {
    final buckets = <int, List<CardioEfficiencyPoint>>{};
    for (final point in points) {
      (buckets[(point.powerWatts / 10).round() * 10] ??= []).add(point);
    }
    int? best;
    for (final entry in buckets.entries) {
      if (entry.value.length < minSamePowerSessions) continue;
      final current = best;
      if (current == null ||
          entry.value.length > buckets[current]!.length ||
          (entry.value.length == buckets[current]!.length &&
              entry.key > current)) {
        best = entry.key;
      }
    }
    if (best == null) return null;
    final group = buckets[best]!;
    return CardioSamePowerComparison(
      powerWatts: best,
      firstBpm: group.first.averageBpm.round(),
      lastBpm: group.last.averageBpm.round(),
      sessionCount: group.length,
    );
  }
}

/// Montag 00:00 der lokalen Woche von [local].
DateTime _weekStart(DateTime local) =>
    DateTime(local.year, local.month, local.day - (local.weekday - 1));

int _indexOf(List<DateTime> starts, DateTime weekStart) {
  for (var i = 0; i < starts.length; i++) {
    if (starts[i] == weekStart) return i;
  }
  return -1;
}

int _minutes(Duration duration) => (duration.inSeconds + 30) ~/ 60;

/// „1:42 h“ (Stunden:Minuten, auf die Minute gerundet).
String formatHoursMinutes(Duration duration) {
  final total = _minutes(duration);
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')} h';
}
