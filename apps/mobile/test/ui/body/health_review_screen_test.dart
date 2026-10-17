import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/body/body_repository.dart';
import 'package:gainer_mobile/data/repositories/health/health_review_coordinator.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/data/services/platform/generated/mobile_platform_api.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';
import 'package:gainer_mobile/ui/core/theme.dart';
import 'package:gainer_mobile/ui/features/body/health/health_review_screen.dart';
import 'package:gainer_mobile/ui/features/body/health/health_review_view_model.dart';

const accountId = '00000000-0000-4000-8000-000000000006';

class _HealthFake implements HealthPlatform {
  int authorizationRequests = 0;
  List<BodyMassSample> samples = const [];

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
  }) async => samples;

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
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('health review matches golden in ${brightness.name} mode', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final database = LocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final store = LocalSyncStore(database: database, accountId: accountId);
      final coordinator = HealthReviewCoordinator(
        store: store,
        bodyRepository: BodyRepository(store: store),
        platform: _HealthFake(),
        accountId: accountId,
        currentSessionIdentity: () =>
            const HealthSessionIdentity(accountId: accountId, generation: 1),
      );
      final viewModel = HealthReviewViewModel(coordinator);
      await tester.pumpWidget(
        CupertinoApp(
          debugShowCheckedModeBanner: false,
          theme: GainerTheme.forBrightness(brightness),
          home: HealthReviewScreen(viewModel: viewModel),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Health-Proben laden'));
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(HealthReviewScreen),
        matchesGoldenFile(
          'goldens/health_review_screen_${brightness.name}.png',
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }

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
      CupertinoApp(
        theme: const CupertinoThemeData(brightness: Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.8)),
          child: child!,
        ),
        home: HealthReviewScreen(viewModel: viewModel),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Health-Proben laden'));
    await tester.pumpAndSettle();

    expect(health.authorizationRequests, 1);
    expect(viewModel.review, isNotNull);
    await tester.scrollUntilVisible(
      find.text('Keine Werte im Zeitraum gefunden.'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Keine Werte im Zeitraum gefunden.'), findsOneWidget);
    expect(
      find.text(
        'Das bedeutet nicht automatisch, dass der Zugriff verweigert wurde.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'Health conflict choice and server sync confirmation use Cupertino dialogs and controls',
    (tester) async {
      final database = LocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final store = LocalSyncStore(database: database, accountId: accountId);
      final body = BodyRepository(store: store);
      await body.saveCheckIn(
        localDate: _today(),
        weightKg: 70,
        caloriesKcal: 2100,
        proteinGrams: 120,
        carbohydrateGrams: null,
        fatGrams: null,
        steps: null,
        sleepMinutes: null,
      );
      final health = _HealthFake()
        ..samples = [
          BodyMassSample(
            uuid: 'health-probe-test',
            measuredAtUtc: DateTime.now().toUtc(),
            weightKilograms: 71.5,
            sourceName: 'Test Apple Watch',
          ),
        ];
      final coordinator = HealthReviewCoordinator(
        store: store,
        bodyRepository: body,
        platform: health,
        accountId: accountId,
        currentSessionIdentity: () =>
            const HealthSessionIdentity(accountId: accountId, generation: 3),
      );
      final viewModel = HealthReviewViewModel(coordinator);
      await tester.pumpWidget(
        CupertinoApp(home: HealthReviewScreen(viewModel: viewModel)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Health-Proben laden'));
      await tester.pumpAndSettle();
      expect(viewModel.review, isNotNull);
      await tester.scrollUntilVisible(
        find.text('71.50 kg'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('71.50 kg'), findsOneWidget);
      final switches = find.byType(CupertinoSwitch);
      expect(switches, findsNWidgets(2));
      await tester.tap(switches.at(1));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Auswahl übernehmen'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Auswahl übernehmen'));
      await tester.pumpAndSettle();

      expect(find.byType(GainerStackedDialog<bool>), findsOneWidget);
      expect(find.text('Check-in an diesem Tag vorhanden'), findsOneWidget);
      await tester.tap(find.text('Überspringen'));
      await tester.pumpAndSettle();
      expect(
        viewModel.lastResults.single.status,
        HealthImportReviewStatus.skipped,
      );
    },
  );
}

String _today() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}
