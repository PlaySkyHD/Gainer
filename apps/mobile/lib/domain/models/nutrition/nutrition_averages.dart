import 'nutrition.dart';

/// Toleranz für „im Zielbereich“: ±10 % des Kalorienziels des jeweiligen Tages.
const nutritionTargetTolerance = 0.10;

/// Ein Kalendertag im Auswertungsfenster.
class NutritionAverageDay {
  const NutritionAverageDay({
    required this.localDate,
    required this.kilocalories,
    required this.targetKilocalories,
  });

  final String localDate;

  /// Summe des Tages; `null`, wenn nichts erfasst wurde (kein Nullbalken).
  final double? kilocalories;

  /// Kalorienziel, das an diesem Tag galt; `null` ohne Zielplan.
  final double? targetKilocalories;

  bool get isLogged => kilocalories != null;

  /// Nur für erfasste Tage mit Ziel; Grenze ±10 % ist inklusive.
  bool get isWithinTarget {
    final kcal = kilocalories;
    final target = targetKilocalories;
    if (kcal == null || target == null) return false;
    return (kcal - target).abs() <= target * nutritionTargetTolerance + 1e-9;
  }
}

/// Durchschnitt über die erfassten Tage eines Fensters von [windowDays] Tagen.
///
/// Tage ohne Einträge zählen nicht mit (Ø je erfasstem Tag). Das Fenster endet
/// heute, aber nur wenn heute Einträge hat. Sonst endet es gestern, damit ein
/// leerer, noch nicht begonnener Tag den Schnitt nicht verfälscht und das
/// Fenster immer [windowDays] volle Kalendertage zeigt.
class NutritionAverages {
  NutritionAverages._({
    required this.windowDays,
    required this.days,
    required this.loggedDays,
    required this.averageKilocalories,
    required this.averageProteinGrams,
    required this.averageCarbohydrateGrams,
    required this.averageFatGrams,
    required this.averageTargetKilocalories,
    required this.daysWithinTarget,
    required this.daysWithTarget,
    required this.includesToday,
  });

  factory NutritionAverages.compute({
    required List<NutritionDay> days,
    required NutritionTargetSchedule? schedule,
    required String today,
    required int windowDays,
  }) {
    if (windowDays < 1) throw RangeError.value(windowDays, 'windowDays');
    final byDate = {for (final day in days) day.localDate: day};
    final includesToday = byDate[today]?.entries.isNotEmpty ?? false;
    final end = includesToday ? today : shiftLocalDate(today, -1);
    final window = <NutritionAverageDay>[];
    for (var offset = windowDays - 1; offset >= 0; offset--) {
      final date = shiftLocalDate(end, -offset);
      final day = byDate[date];
      final logged = day != null && day.entries.isNotEmpty;
      window.add(
        NutritionAverageDay(
          localDate: date,
          kilocalories: logged ? day.totals.kilocalories : null,
          targetKilocalories: _targetOn(schedule, date)?.kilocalories,
        ),
      );
    }
    final logged = [
      for (final item in window)
        if (item.isLogged) byDate[item.localDate]!,
    ];
    double? mean(double? Function(NutritionTotals) select) {
      final values = [for (final day in logged) ?select(day.totals)];
      if (values.isEmpty) return null;
      return values.reduce((a, b) => a + b) / values.length;
    }

    final withTarget = [
      for (final item in window)
        if (item.isLogged && item.targetKilocalories != null) item,
    ];
    return NutritionAverages._(
      windowDays: windowDays,
      days: List.unmodifiable(window),
      loggedDays: logged.length,
      averageKilocalories: mean((totals) => totals.kilocalories),
      averageProteinGrams: mean((totals) => totals.proteinGrams),
      averageCarbohydrateGrams: mean((totals) => totals.carbohydrateGrams),
      averageFatGrams: mean((totals) => totals.fatGrams),
      averageTargetKilocalories: withTarget.isEmpty
          ? null
          : withTarget
                    .map((item) => item.targetKilocalories!)
                    .reduce((a, b) => a + b) /
                withTarget.length,
      daysWithinTarget: withTarget.where((item) => item.isWithinTarget).length,
      daysWithTarget: withTarget.length,
      includesToday: includesToday,
    );
  }

  final int windowDays;

  /// Älteste zuerst; genau [windowDays] Einträge.
  final List<NutritionAverageDay> days;
  final int loggedDays;
  final double? averageKilocalories;
  final double? averageProteinGrams;
  final double? averageCarbohydrateGrams;
  final double? averageFatGrams;

  /// Ø Kalorienziel über die erfassten Tage mit Ziel.
  final double? averageTargetKilocalories;
  final int daysWithinTarget;

  /// Erfasste Tage, für die ein Ziel galt (Nenner von [daysWithinTarget]).
  final int daysWithTarget;
  final bool includesToday;

  bool get hasData => loggedDays > 0;
  bool get hasTarget => daysWithTarget > 0;
}

/// Gleiche Regel wie im Tagebuch: die zuletzt beginnende passende Phase.
NutritionTargetVersion? _targetOn(
  NutritionTargetSchedule? schedule,
  String date,
) => schedule?.versions
    .where(
      (phase) =>
          phase.effectiveFrom.compareTo(date) <= 0 &&
          (phase.effectiveUntil == null ||
              phase.effectiveUntil!.compareTo(date) >= 0),
    )
    .lastOrNull;

/// Verschiebt einen lokalen Kalendertag (`JJJJ-MM-TT`) um [days] Tage.
String shiftLocalDate(String localDate, int days) {
  final base = DateTime.parse(localDate);
  final shifted = DateTime.utc(base.year, base.month, base.day + days);
  return '${shifted.year.toString().padLeft(4, '0')}-'
      '${shifted.month.toString().padLeft(2, '0')}-'
      '${shifted.day.toString().padLeft(2, '0')}';
}

/// Beide Fenster der Ansicht „Durchschnitt“.
class NutritionAveragesOverview {
  NutritionAveragesOverview({
    required List<NutritionDay> days,
    required NutritionTargetSchedule? schedule,
    required String today,
  }) : week = NutritionAverages.compute(
         days: days,
         schedule: schedule,
         today: today,
         windowDays: 7,
       ),
       month = NutritionAverages.compute(
         days: days,
         schedule: schedule,
         today: today,
         windowDays: 30,
       );

  final NutritionAverages week;
  final NutritionAverages month;
}
