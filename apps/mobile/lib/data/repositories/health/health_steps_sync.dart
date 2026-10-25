import '../../../domain/models/training/training_schedule.dart';
import '../body/body_repository.dart';
import 'check_in_health_coordinator.dart';

/// Schritte aus Apple Health für die Übersicht: heute live, vergangene Tage
/// als fertige Tagessumme in die vorhandenen Check-ins übernommen. Der
/// Check-in liest Schritte sonst nur einmal, meist morgens.
class HealthStepsSync {
  HealthStepsSync({
    required this.health,
    required this.body,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final CheckInHealthCoordinator health;
  final BodyRepository body;
  final DateTime Function() _clock;

  /// Schritte von heute bis jetzt; null ohne Zugriff oder Daten.
  Future<int?> today() => health.readSteps(LocalDay.of(_clock()).toIso());

  /// Gleicht die Check-ins der letzten [days] Tage ohne heute mit Apple Health
  /// ab. Liefert, wie viele Check-ins sich geändert haben. Wirft nie.
  Future<int> syncRecent({int days = 7}) async {
    // Kalendertage statt 24 Stunden, sonst fehlt der Tag der Zeitumstellung.
    final today = LocalDay.of(_clock());
    final first = today.addDays(-days).toIso();
    final yesterday = today.addDays(-1).toIso();
    var changed = 0;
    try {
      final snapshot = await body.read();
      for (final item in snapshot.checkIns) {
        final date = item.value.localDate;
        if (date.compareTo(first) < 0 || date.compareTo(yesterday) > 0) {
          continue;
        }
        final steps = await health.readSteps(date);
        if (steps == null || steps == item.value.steps) continue;
        if (await body.updateSteps(localDate: date, steps: steps)) changed++;
      }
    } catch (_) {
      // Der Abgleich ist eine Nachbesserung; die Übersicht lädt trotzdem.
    }
    return changed;
  }
}
