import 'package:flutter/widgets.dart';

import '../../../ui/features/body/body_view_model.dart';
import '../../../ui/features/nutrition/nutrition_view_model.dart';
import '../../services/local/local_database.dart';
import '../../services/platform/platform_ports.dart';

/// Publishes neutral extension routes. It never publishes account data,
/// nutrition, or credentials to the App Group.
class NativeFeatureLifecycleCoordinator with WidgetsBindingObserver {
  NativeFeatureLifecycleCoordinator({
    required this.installationDatabase,
    required this.body,
    required this.nutrition,
    required this.snapshots,
    required this.haptics,
    required this.isSessionActive,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now {
    WidgetsBinding.instance.addObserver(this);
    body.addListener(_onBodyChanged);
    nutrition.addListener(_onNutritionChanged);
  }

  final LocalDatabase installationDatabase;
  final BodyViewModel body;
  final NutritionViewModel nutrition;
  final ExtensionSnapshotPlatform snapshots;
  final HapticsPlatform haptics;
  final bool Function() isSessionActive;
  final DateTime Function() clock;
  Future<void> _pending = Future<void>.value();
  bool _active = true;
  bool _bodySaving = false;
  bool _nutritionSaving = false;

  void activate() => _chain(_publishNeutralSnapshot);

  void _chain(Future<void> Function() action) {
    _pending = _pending.then((_) async {
      if (!_active || !isSessionActive()) return;
      try {
        await action();
      } catch (_) {
        // Extension features are optional. Local workouts remain usable.
      }
    });
  }

  void _onBodyChanged() {
    final wasSaving = _bodySaving;
    _bodySaving = body.isSaving;
    if (wasSaving && !_bodySaving && body.errorMessage == null) {
      _performHaptic(HapticIntent.commit);
    }
  }

  void _onNutritionChanged() {
    final wasSaving = _nutritionSaving;
    _nutritionSaving = nutrition.isSaving;
    if (wasSaving && !_nutritionSaving && nutrition.errorMessage == null) {
      _performHaptic(HapticIntent.commit);
    }
  }

  void _performHaptic(HapticIntent intent) {
    if (!_active || !isSessionActive()) return;
    haptics.perform(intent).catchError((Object _) {});
  }

  Future<void> _publishNeutralSnapshot() async {
    if (!_active || !isSessionActive()) return;
    final generation = await _nextGeneration();
    if (!_active || !isSessionActive()) return;
    await snapshots.publish(
      NeutralExtensionSnapshot(
        schemaVersion: 1,
        generation: generation,
        updatedAtUtc: clock().toUtc(),
        availableRoutes: const {'training', 'checkIn', 'nutrition'},
      ),
    );
  }

  Future<int> _nextGeneration() => installationDatabase.transaction(() async {
    final row =
        await (installationDatabase.select(
              installationDatabase.installationMetadata,
            )..where((table) => table.key.equals('native-feature-generation')))
            .getSingleOrNull();
    final previous = row == null ? 0 : (int.tryParse(row.value) ?? 0);
    final next = previous + 1;
    await installationDatabase
        .into(installationDatabase.installationMetadata)
        .insertOnConflictUpdate(
          InstallationMetadataCompanion.insert(
            key: 'native-feature-generation',
            value: '$next',
          ),
        );
    return next;
  });

  Future<void> disposeForSessionEnd() async {
    if (!_active) return;
    _active = false;
    WidgetsBinding.instance.removeObserver(this);
    body.removeListener(_onBodyChanged);
    nutrition.removeListener(_onNutritionChanged);
    await _pending;
    final generation = await _nextGeneration();
    try {
      await snapshots.clear(minimumGeneration: generation);
    } catch (_) {}
  }
}
