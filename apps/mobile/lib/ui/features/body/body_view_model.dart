import 'package:flutter/foundation.dart';

import '../../../data/repositories/body/body_repository.dart';
import '../../../data/repositories/health/check_in_health_coordinator.dart';
import '../../../domain/models/body/body_tracking.dart';

class BodyViewModel extends ChangeNotifier {
  BodyViewModel(this.repository, {this.health});

  final BodyRepository repository;

  /// Apple-Health-Anbindung des Check-ins; ohne sie bleibt der Check-in manuell.
  final CheckInHealthCoordinator? health;

  /// Health-Werte des gerade geöffneten Check-in-Tags.
  CheckInHealthSnapshot? checkInHealth;
  String? _checkInHealthDate;
  int _healthRequest = 0;
  BodyTrackingSnapshot? snapshot;
  bool isLoading = false;
  bool isSaving = false;
  String? errorMessage;

  /// Feldfehler der letzten Validierung, z. B. `weightKg` → Meldung.
  Map<String, String> fieldErrors = const {};
  bool _disposed = false;

  Future<void> load() => _run(() async {
    await repository.flushPendingResting();
    final loaded = await repository.read();
    if (_disposed) return;
    snapshot = loaded;
  });

  Future<void> saveGoal({
    required BodyGoalKind kind,
    required double startWeightKg,
    required double targetWeightKg,
    required String startDate,
    required String? targetDate,
  }) => _run(() async {
    await repository.activateGoal(
      kind: kind,
      startWeightKg: startWeightKg,
      targetWeightKg: targetWeightKg,
      startDate: startDate,
      targetDate: targetDate,
    );
    if (_disposed) return;
    final loaded = await repository.read();
    if (_disposed) return;
    snapshot = loaded;
  }, saving: true);

  /// Liest die Health-Werte des Tages; null ohne Anbindung oder wenn eine
  /// neuere Anfrage die Antwort überholt hat. Wirft nie.
  Future<CheckInHealthSnapshot?> loadCheckInHealth(String localDate) async {
    final coordinator = health;
    if (coordinator == null) return null;
    final request = ++_healthRequest;
    checkInHealth = null;
    _checkInHealthDate = null;
    final loaded = await coordinator.load(localDate);
    if (_disposed || request != _healthRequest) return null;
    checkInHealth = loaded;
    _checkInHealthDate = localDate;
    _notify();
    return loaded;
  }

  /// Speichert den Check-in. Kalorien und Makros eines vorhandenen Check-ins
  /// bleiben erhalten; Schritte kommen aus Health (sonst der alte Wert).
  /// Schreiben nach Health ist best effort und blockiert das Speichern nie.
  Future<void> saveCheckIn({
    required String localDate,
    required double weightKg,
    int? sleepMinutes,
    DateTime? bedtime,
    DateTime? wake,
  }) => _run(() async {
    final existing = snapshot?.checkIns
        .where((item) => item.value.localDate == localDate)
        .firstOrNull
        ?.value;
    final healthSnapshot = _checkInHealthDate == localDate
        ? checkInHealth
        : null;
    await repository.saveCheckIn(
      localDate: localDate,
      weightKg: weightKg,
      caloriesKcal: existing?.caloriesKcal,
      proteinGrams: existing?.proteinGrams,
      carbohydrateGrams: existing?.carbohydrateGrams,
      fatGrams: existing?.fatGrams,
      steps: healthSnapshot?.steps ?? existing?.steps,
      sleepMinutes: sleepMinutes,
    );
    if (_disposed) return;
    if (health != null && healthSnapshot != null) {
      await health!.writeBack(
        localDate: localDate,
        snapshot: healthSnapshot,
        weightKg: weightKg,
        bedtime: bedtime,
        wake: wake,
      );
    }
    if (_disposed) return;
    final loaded = await repository.read();
    if (_disposed) return;
    snapshot = loaded;
  }, saving: true);

  Future<void> _run(
    Future<void> Function() action, {
    bool saving = false,
  }) async {
    if (_disposed) return;
    isLoading = !saving;
    isSaving = saving;
    errorMessage = null;
    fieldErrors = const {};
    _notify();
    try {
      await action();
    } on BodyTrackingValidationException catch (error) {
      if (!_disposed) fieldErrors = Map.unmodifiable(error.fields);
    } catch (error) {
      if (!_disposed) errorMessage = error.toString();
    } finally {
      if (!_disposed) {
        isLoading = false;
        isSaving = false;
        _notify();
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
