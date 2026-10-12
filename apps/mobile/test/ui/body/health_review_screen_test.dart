import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/body/body_repository.dart';
import 'package:gainer_mobile/data/repositories/health/health_review_coordinator.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/data/services/platform/generated/mobile_platform_api.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';
import 'package:gainer_mobile/ui/features/body/health/health_review_screen.dart';
import 'package:gainer_mobile/ui/features/body/health/health_review_view_model.dart';

const accountId = '00000000-0000-4000-8000-000000000006';

class _HealthFake implements HealthPlatform {
  int authorizationRequests = 0;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<PlatformAuthorizationRequestResult>
  requestBodyMassReadAuthorization() async {
    authorizationRequests++;
    return PlatformAuthorizationRequestResult.requestCompleted;
  }

  @override
  Future<List<BodyMassSample>> readBodyMassSamples({
    required DateTime fromUtc,
    required DateTime toUtc,
  }) async => const [];

  @override
  Future<PlatformAuthorizationRequestResult>
  requestWorkoutWriteAuthorization() async =>
      PlatformAuthorizationRequestResult.requestCompleted;

  @override
  Future<WorkoutExportReceipt> exportCompletedWorkout(
    CompletedWorkoutHealthExport workout,
  ) async => const WorkoutExportReceipt(
    status: HealthExportStatus.saved,
    syncIdentifier: 'health-workout-id',
    syncVersion: 1,
  );
}

void main() {
  testWidgets('Health screen explains empty results after an explicit query', (
    tester,
  ) async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final store = LocalSyncStore(database: database, accountId: accountId);
    final health = _HealthFake();
    final coordinator = HealthReviewCoordinator(
      store: store,
      bodyRepository: BodyRepository(store: store),
      platform: health,
      accountId: accountId,
      currentSessionIdentity: () =>
          const HealthSessionIdentity(accountId: accountId, generation: 1),
    );
    final viewModel = HealthReviewViewModel(coordinator);
    await tester.pumpWidget(
      MaterialApp(home: HealthReviewScreen(viewModel: viewModel)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Health-Proben laden'));
    await tester.pumpAndSettle();

    expect(health.authorizationRequests, 1);
    expect(find.text('Keine Werte im Zeitraum gefunden.'), findsOneWidget);
    expect(
      find.text(
        'Das bedeutet nicht automatisch, dass der Zugriff verweigert wurde.',
      ),
      findsOneWidget,
    );
    expect(find.text('Auswahl übernehmen'), findsOneWidget);
  });
}
