/// Grenzen der Wassermenge eines Tages in ganzen Millilitern (wie der Server).
abstract final class WaterIntakeLimits {
  static const minDailyMl = 0;
  static const maxDailyMl = 10000;

  /// Schnellknöpfe der Wasser-Karte.
  static const quickAmountsMl = [200, 300, 500];

  /// Tagesziel: Standard und erlaubte Spanne in den Einstellungen.
  static const defaultGoalMl = 2500;
  static const minGoalMl = 250;
  static const maxGoalMl = 10000;

  /// True, wenn [amountMl] eine gültige Tagesmenge ist.
  static bool isValidDaily(int amountMl) =>
      amountMl >= minDailyMl && amountMl <= maxDailyMl;

  /// True, wenn [addedMl] zu [currentMl] passt, ohne die Grenze zu überschreiten.
  static bool canAdd(int currentMl, int addedMl) =>
      addedMl >= 1 && currentMl + addedMl <= maxDailyMl;

  static bool isValidGoal(int goalMl) =>
      goalMl >= minGoalMl && goalMl <= maxGoalMl;
}
