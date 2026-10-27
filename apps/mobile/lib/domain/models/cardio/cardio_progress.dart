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

  static Duration _timeInZone(CardioSession session, CardioZone zone) {
    final inZone = session.heartRateBpm
        .where((bpm) => bpm > 0 && bpm >= zone.lowBpm && bpm < zone.highBpm)
        .length;
    return Duration(seconds: inZone * session.sampleIntervalSeconds);
  }

  static List<CardioEfficiencyPoint> _efficiencyPoints(
    List<CardioSession> ordered,
  ) {
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
    return points;
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
    final ordered = [...sessions]
      ..sort((a, b) => a.startedAtUtc.compareTo(b.startedAtUtc));
    final totals = _WeekTotals.of(ordered, starts, zone2);

    // Effizienz und Vergleich: alle Einheiten mit Leistung und Puls.
    final points = _efficiencyPoints(ordered);
    final recovered = _recoveryDrops(ordered);

    return CardioProgress(
      weeks: [
        for (var i = 0; i < weekCount; i++)
          CardioWeek(
            start: starts[i],
            timeInTarget: totals.targetTime[i],
            timeInZone2: zone2 == null ? null : totals.zone2Time[i],
            sessionCount: totals.counts[i],
            totalDuration: totals.durations[i],
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
      hasSessions: totals.any,
    );
  }

  static List<int> _recoveryDrops(List<CardioSession> ordered) => [
    for (final session in ordered.reversed)
      if (session.deletedAtUtc == null && session.recoveryDropBpm != null)
        session.recoveryDropBpm!,
  ].take(recoverySessionCount).toList();

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

/// Summen je Woche, in der Reihenfolge von `starts`.
class _WeekTotals {
  _WeekTotals._()
    : targetTime = List.filled(CardioProgress.weekCount, Duration.zero),
      zone2Time = List.filled(CardioProgress.weekCount, Duration.zero),
      counts = List.filled(CardioProgress.weekCount, 0),
      durations = List.filled(CardioProgress.weekCount, Duration.zero);

  /// Summiert die nach Startzeit geordneten, nicht gelöschten Einheiten in die
  /// Woche, in der sie lokal liegen; Einheiten außerhalb der Wochen zählen nicht.
  factory _WeekTotals.of(
    List<CardioSession> ordered,
    List<DateTime> starts,
    CardioZone? zone2,
  ) {
    final totals = _WeekTotals._();
    for (final session in ordered) {
      if (session.deletedAtUtc != null) continue;
      final index = _indexOf(
        starts,
        _weekStart(session.startedAtUtc.toLocal()),
      );
      if (index >= 0) totals._add(index, session, zone2);
    }
    return totals;
  }

  final List<Duration> targetTime;
  final List<Duration> zone2Time;
  final List<int> counts;
  final List<Duration> durations;
  bool any = false;

  void _add(int index, CardioSession session, CardioZone? zone2) {
    any = true;
    targetTime[index] += CardioAnalysis.of(session).timeInZone;
    counts[index]++;
    durations[index] += session.duration;
    if (zone2 != null) {
      zone2Time[index] += CardioProgress._timeInZone(session, zone2);
    }
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
