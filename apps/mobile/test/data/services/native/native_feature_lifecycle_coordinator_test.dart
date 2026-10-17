import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/data/services/native/native_feature_lifecycle_coordinator.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';
import 'package:gainer_mobile/ui/features/body/body_view_model.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('session end tombstones the neutral extension snapshot', (
    tester,
  ) async {
    final database = LocalDatabase(NativeDatabase.memory());
    final snapshots = _Snapshots();
    final coordinator = _coordinator(database: database, snapshots: snapshots);

    coordinator.activate();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.runAsync(() => coordinator.disposeForSessionEnd());

    expect(snapshots.published, hasLength(1));
    expect(snapshots.published.single.availableRoutes, {
      'training',
      'checkIn',
      'nutrition',
    });
    expect(snapshots.clearedGenerations, [
      snapshots.published.single.generation + 1,
    ]);
    await database.close();
  });
}

NativeFeatureLifecycleCoordinator _coordinator({
  required LocalDatabase database,
  _Snapshots? snapshots,
}) => NativeFeatureLifecycleCoordinator(
  installationDatabase: database,
  body: _Body(),
  nutrition: _Nutrition(),
  snapshots: snapshots ?? _Snapshots(),
  haptics: _Haptics(),
  isSessionActive: () => true,
);

class _Body extends ChangeNotifier implements BodyViewModel {
  @override
  bool isSaving = false;
  @override
  String? errorMessage;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Nutrition extends ChangeNotifier implements NutritionViewModel {
  @override
  bool isSaving = false;
  @override
  String? errorMessage;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Snapshots implements ExtensionSnapshotPlatform {
  final published = <NeutralExtensionSnapshot>[];
  final clearedGenerations = <int>[];

  @override
  Future<void> publish(NeutralExtensionSnapshot snapshot) async =>
      published.add(snapshot);
  @override
  Future<void> clear({required int minimumGeneration}) async =>
      clearedGenerations.add(minimumGeneration);
}

class _Haptics implements HapticsPlatform {
  @override
  Future<void> perform(HapticIntent intent) async {}
}
