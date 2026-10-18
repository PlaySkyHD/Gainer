/// Pulszone 1 bis 5. Die obere Grenze einer Zone ist die untere der nächsten.
class CardioZone {
  const CardioZone({
    required this.number,
    required this.lowBpm,
    required this.highBpm,
  });

  final int number;
  final int lowBpm;
  final int highBpm;

  @override
  bool operator ==(Object other) =>
      other is CardioZone &&
      other.number == number &&
      other.lowBpm == lowBpm &&
      other.highBpm == highBpm;

  @override
  int get hashCode => Object.hash(number, lowBpm, highBpm);

  @override
  String toString() => 'Z$number $lowBpm–$highBpm';
}

/// Zonenempfehlung aus Maximalpuls (und Ruhepuls nach Karvonen).
abstract final class CardioZones {
  /// Untere Grenzen in % von HFmax; die letzte ist das Ende von Zone 5.
  static const _percent = [50, 60, 70, 80, 90, 100];

  /// `round(208 − 0,7 × Alter)`.
  static int maxHeartRateFor(int age) => (208 - 0.7 * age).round();

  /// Zonen 1 bis 5. Ohne [restingHr]: Grenze = % × HFmax. Mit Ruhepuls
  /// (Karvonen): Ruhepuls + % × (HFmax − Ruhepuls). Auf ganze bpm gerundet.
  static List<CardioZone> compute(int maxHr, [int? restingHr]) {
    final rest = restingHr ?? 0;
    int bound(int percent) => (rest + percent * (maxHr - rest) / 100).round();
    return [
      for (var i = 0; i < 5; i++)
        CardioZone(
          number: i + 1,
          lowBpm: bound(_percent[i]),
          highBpm: bound(_percent[i + 1]),
        ),
    ];
  }
}
