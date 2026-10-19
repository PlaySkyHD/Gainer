/// Wie frisch der letzte Gewichtseintrag ist.
enum WeightAgeSeverity {
  /// Heute oder gestern: unauffällig.
  fresh,

  /// 2 bis 6 Tage: Warnfarbe.
  aging,

  /// 7 Tage und mehr: Fehlerfarbe.
  stale,
}

/// Alter eines Gewichtseintrags, gemessen in Kalendertagen (lokales Datum).
class WeightAge {
  const WeightAge(this.days);

  /// Berechnet das Alter aus `yyyy-MM-dd` und dem lokalen heutigen Datum.
  /// Zukünftige oder ungültige Daten zählen als „Heute“.
  factory WeightAge.fromDate(String isoDate, DateTime today) {
    final parsed = DateTime.tryParse(isoDate);
    if (parsed == null) return const WeightAge(0);
    // UTC-Mitternacht je Kalendertag, damit Sommerzeit nichts verschiebt.
    final entry = DateTime.utc(parsed.year, parsed.month, parsed.day);
    final now = DateTime.utc(today.year, today.month, today.day);
    final days = now.difference(entry).inDays;
    return WeightAge(days < 0 ? 0 : days);
  }

  final int days;

  WeightAgeSeverity get severity {
    if (days <= 1) return WeightAgeSeverity.fresh;
    if (days < 7) return WeightAgeSeverity.aging;
    return WeightAgeSeverity.stale;
  }

  String get label => switch (days) {
    0 => 'Heute',
    1 => 'Gestern',
    _ => 'vor $days Tagen',
  };
}
