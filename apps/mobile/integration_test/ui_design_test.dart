import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/api/api_models.dart';
import 'package:gainer_mobile/data/repositories/body/body_repository.dart';
import 'package:gainer_mobile/data/repositories/health/health_review_coordinator.dart';
import 'package:gainer_mobile/data/repositories/insights/insights_repository.dart';
import 'package:gainer_mobile/data/repositories/nutrition/nutrition_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/repositories/sync/sync_repository.dart';
import 'package:gainer_mobile/data/repositories/training/training_repository.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';
import 'package:gainer_mobile/data/services/auth/mobile_auth_controller.dart';
import 'package:gainer_mobile/data/services/auth/sync_foreground_scheduler.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/data/services/native/native_feature_lifecycle_coordinator.dart';
import 'package:gainer_mobile/data/services/platform/generated/mobile_platform_api.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';
import 'package:gainer_mobile/domain/models/body/body_tracking.dart';
import 'package:gainer_mobile/domain/models/nutrition/nutrition.dart';
import 'package:gainer_mobile/domain/models/training/training.dart';
import 'package:gainer_mobile/ui/core/shell/mobile_shell.dart';
import 'package:gainer_mobile/ui/core/theme.dart';
import 'package:gainer_mobile/ui/core/view_models/mobile_shell_view_model.dart';
import 'package:gainer_mobile/ui/features/body/body_view_model.dart';
import 'package:gainer_mobile/ui/features/body/health/health_review_view_model.dart';
import 'package:gainer_mobile/ui/features/coach/coach_view_model.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_view_model.dart';
import 'package:gainer_mobile/ui/features/progress/progress_view_model.dart';
import 'package:gainer_mobile/ui/features/training/training_view_model.dart';
import 'package:integration_test/integration_test.dart';

const _accountId = '00000000-0000-4000-8000-000000000003';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('programmatic tab changes keep routes and tab content in sync', (
    tester,
  ) async {
    final fixture = await createUiDesignFixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app(GainerTheme.light));
    await tester.pumpAndSettle();
    await _tapTab(tester, 'Essen');
    await tester.tap(find.byKey(const ValueKey('nutrition-add-food')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nutrition-mode-manual')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nutrition-entry-name')), findsOneWidget);

    fixture.controller.shell.selectTab(MobileArea.body.index);
    await tester.pumpAndSettle();
    expect(
      find.text('Dein aktueller Stand und tägliche Check-ins'),
      findsOneWidget,
    );
    fixture.controller.shell.selectTab(MobileArea.nutrition.index);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nutrition-entry-name')), findsOneWidget);
    expect(
      fixture.controller.shell.tabController.index,
      MobileArea.nutrition.index,
    );
  });

  testWidgets('captures populated native tabs and the check-in sheet', (
    tester,
  ) async {
    final fixture = await createUiDesignFixture();
    addTearDown(fixture.dispose);

    await tester.pumpWidget(fixture.app(GainerTheme.light));
    await tester.pumpAndSettle();
    await _waitForExerciseProgress(tester, fixture);
    await _capture(binding, 'tab-heute');
    expect(find.text('Dein Fortschritt aus deinen Einträgen'), findsOneWidget);
    expect(find.text('Letzter Eintrag · 14.10.2026'), findsOneWidget);
    expect(find.text('Ø 7 Tage · 82.7 kg'), findsOneWidget);
    expect(find.text('148 g Protein pro erfasstem Tag'), findsOneWidget);
    await tester.ensureVisible(find.text('Übungsfortschritt'));
    await tester.pumpAndSettle();
    await _capture(binding, 'exercise-progress');
    expect(
      fixture.account.progressViewModel.exerciseProgress!.points,
      isNotEmpty,
    );

    await _tapTab(tester, 'Check-in');
    expect(
      find.text('Dein aktueller Stand und tägliche Check-ins'),
      findsOneWidget,
    );
    await _capture(binding, 'tab-checkin');
    await tester.tap(find.byKey(const ValueKey('body-open-checkin')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('body-save-checkin')), findsOneWidget);
    await _capture(binding, 'sheet-checkin');
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('body-open-goal')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('body-save-goal')), findsOneWidget);
    await _capture(binding, 'sheet-goal');
    await tester.tap(find.byKey(const ValueKey('body-start-date')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('body-date-done')), findsOneWidget);
    await _capture(binding, 'date-picker');
    await tester.tap(find.byKey(const ValueKey('body-date-cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();

    await _tapTab(tester, 'Essen');
    await _capture(binding, 'tab-essen');
    await tester.tap(find.byKey(const ValueKey('nutrition-add-food')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nutrition-mode-manual')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('nutrition-entry-name')),
    );
    expect(find.byKey(const ValueKey('nutrition-entry-name')), findsOneWidget);
    await _capture(binding, 'editor-essen');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Ernährungstagebuch'), findsOneWidget);

    await _tapTab(tester, 'Training');
    await _capture(binding, 'tab-training');
    await tester.tap(
      find.byKey(const ValueKey('training-create-template-route')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('training-cancel-template')),
      findsOneWidget,
    );
    await _capture(binding, 'editor-training');
    await _tapTab(tester, 'Mehr');
    await _tapTab(tester, 'Training');
    expect(
      find.byKey(const ValueKey('training-cancel-template')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('training-cancel-template')));
    await tester.pumpAndSettle();
    expect(find.text('Dein Training'), findsOneWidget);

    await _tapTab(tester, 'Mehr');
    await _capture(binding, 'tab-mehr');
    expect(find.text('Apple Health'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // All five destinations are captured again under native dark appearance.
    await tester.pumpWidget(fixture.app(GainerTheme.dark));
    await tester.pumpAndSettle();
    for (final tab in const [
      ('Heute', 'tab-dark-heute'),
      ('Check-in', 'tab-dark-checkin'),
      ('Essen', 'tab-dark-essen'),
      ('Training', 'tab-dark-training'),
      ('Mehr', 'tab-dark-mehr'),
    ]) {
      await _tapTab(tester, tab.$1);
      if (tab.$1 == 'Heute') {
        _resetProgressScroll(tester);
        await tester.pumpAndSettle();
        expect(
          find.text('Dein Fortschritt aus deinen Einträgen'),
          findsOneWidget,
        );
      }
      await _capture(binding, tab.$2);
    }
    await _tapTab(tester, 'Heute');
    await tester.ensureVisible(find.text('Übungsfortschritt'));
    await tester.pumpAndSettle();
    await _capture(binding, 'exercise-dark-progress');
    expect(
      fixture.account.progressViewModel.exerciseProgress!.points,
      isNotEmpty,
    );
    await _tapTab(tester, 'Check-in');
    await tester.tap(find.byKey(const ValueKey('body-open-checkin')));
    await tester.pumpAndSettle();
    await _capture(binding, 'sheet-dark-checkin');
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();

    await _tapTab(tester, 'Essen');
    await tester.tap(find.byKey(const ValueKey('nutrition-add-food')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nutrition-mode-manual')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('nutrition-entry-name')),
    );
    await _capture(binding, 'editor-dark-essen');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await _tapTab(tester, 'Training');
    await tester.tap(
      find.byKey(const ValueKey('training-create-template-route')),
    );
    await tester.pumpAndSettle();
    await _capture(binding, 'editor-dark-training');
    await tester.tap(find.byKey(const ValueKey('training-cancel-template')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

/// Creates the same offline, populated account used by the native screenshot
/// gate. Native feature ports are inert fakes; screenshots only exercise UI.
Future<UiDesignFixture> createUiDesignFixture() async {
  final database = LocalDatabase(NativeDatabase.memory());
  final store = LocalSyncStore(database: database, accountId: _accountId);
  final api = _FixtureApi();
  final native = _FixtureNativeFeatures();
  final session = const ApiSession(
    userId: _accountId,
    email: 'gainer@example.test',
    isAccountOperator: false,
  );
  bool isActive() => true;

  final bodyRepository = BodyRepository(store: store);
  await bodyRepository.activateGoal(
    kind: BodyGoalKind.cut,
    startWeightKg: 84,
    targetWeightKg: 78,
    startDate: _date(DateTime.now()),
    targetDate: null,
  );
  await bodyRepository.saveCheckIn(
    localDate: _date(DateTime.now()),
    weightKg: 82.4,
    caloriesKcal: 2130,
    proteinGrams: 148,
    carbohydrateGrams: 220,
    fatGrams: 66,
    steps: 8460,
    sleepMinutes: 438,
  );

  final trainingRepository = TrainingRepository(
    store: store,
    catalog: _FixtureExerciseCatalog(),
  );
  final templateId = await trainingRepository.saveTemplate(
    name: 'Ganzkörper A',
    items: const [
      TrainingTemplateItem(
        id: 'template-item-1',
        exerciseId: '00000000-0000-4000-8000-000000000004',
        plannedSets: 3,
        minimumRepetitions: 8,
        maximumRepetitions: 10,
        targetRir: 2,
        restSeconds: 120,
        notes: null,
      ),
    ],
  );
  await trainingRepository.saveRotation([templateId]);
  final nutritionRepository = NutritionRepository(store: store);
  final today = _date(DateTime.now());
  await nutritionRepository.saveEntry(
    today,
    NutritionEntry(
      entryId: 'food-entry-1',
      meal: NutritionMeal.breakfast,
      position: 1,
      productName: 'Haferflocken mit Joghurt',
      brand: null,
      amountGrams: 250,
      per100Grams: const NutritionTotals(
        kilocalories: 152,
        proteinGrams: 7.5,
        carbohydrateGrams: 21,
        fatGrams: 4,
      ),
      source: null,
    ),
  );

  final body = BodyViewModel(bodyRepository);
  final training = TrainingViewModel(trainingRepository);
  final nutrition = NutritionViewModel(
    repository: nutritionRepository,
    localDate: today,
  );
  final progress = ProgressViewModel(
    InsightsRepository(api, store: store),
    trainingRepository: trainingRepository,
  );
  final sync = SyncRepository(
    store: store,
    api: api,
    installationIdentity: InstallationIdentityStore(database),
    displayName: 'iOS review fixture',
  );
  final scheduler = SyncForegroundScheduler(
    synchronize: () async => const SyncRunReport(
      state: SyncRunState.idle,
      pushed: 0,
      pulledBatches: 0,
    ),
    isActive: isActive,
    observeLifecycle: false,
  );
  final health = HealthReviewViewModel(
    HealthReviewCoordinator(
      store: store,
      bodyRepository: bodyRepository,
      platform: native,
      accountId: _accountId,
      currentSessionIdentity: () =>
          HealthSessionIdentity(accountId: _accountId, generation: 1),
    ),
  );
  final account = AccountScope(
    session: session,
    generation: 1,
    api: api,
    database: database,
    store: store,
    sync: sync,
    syncScheduler: scheduler,
    isSessionActive: isActive,
    online: false,
    bodyViewModel: body,
    trainingViewModel: training,
    nutritionViewModel: nutrition,
    healthViewModel: health,
    progressViewModel: progress,
    coachViewModel: CoachViewModel(CoachRepository(api)),
    nativeLifecycle: NativeFeatureLifecycleCoordinator(
      installationDatabase: database,
      training: training,
      body: body,
      nutrition: nutrition,
      snapshots: native,
      activities: native,
      haptics: native,
      notifications: native,
      isSessionActive: isActive,
    ),
  );
  final controller = MobileAuthController(
    configuration: MobileAppConfiguration(
      api: Uri.parse('https://api.gainer.example'),
      trustedOrigin: Uri.parse('https://app.gainer.example'),
    ),
  );
  return UiDesignFixture(account: account, controller: controller);
}

class UiDesignFixture {
  const UiDesignFixture({required this.account, required this.controller});

  final AccountScope account;
  final MobileAuthController controller;

  CupertinoApp app(CupertinoThemeData theme) => CupertinoApp(
    debugShowCheckedModeBanner: false,
    theme: theme,
    supportedLocales: const [Locale('de')],
    localizationsDelegates: const [
      GlobalWidgetsLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: MobileShell(
      key: ValueKey('${account.session.userId}:${account.generation}'),
      controller: controller,
      account: account,
    ),
  );

  Future<void> dispose() async {
    await account.dispose();
    controller.dispose();
  }
}

Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void _resetProgressScroll(WidgetTester tester) {
  final scrollable = find.descendant(
    of: find.byKey(const ValueKey('progress-overview-scroll')),
    matching: find.byType(Scrollable),
  );
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
}

Future<void> _waitForExerciseProgress(
  WidgetTester tester,
  UiDesignFixture fixture,
) async {
  final viewModel = fixture.account.progressViewModel;
  for (
    var attempt = 0;
    attempt < 30 &&
        (viewModel.dashboard == null || viewModel.exerciseProgress == null);
    attempt++
  ) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(viewModel.dashboard, isNotNull);
  expect(viewModel.selectedExerciseId, isNotNull);
  expect(viewModel.selectedProgressWindow, '30');
  expect(viewModel.exerciseOptions, isNotEmpty);
  expect(viewModel.exerciseProgress, isNotNull);
  expect(viewModel.exerciseProgress!.points, isNotEmpty);
}

Future<void> _capture(
  IntegrationTestWidgetsFlutterBinding binding,
  String name,
) async {
  await binding.takeScreenshot(name);
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

class _FixtureApi extends ApiClient {
  _FixtureApi()
    : super(
        configuration: ApiConfiguration(
          apiOrigin: Uri.parse('https://api.gainer.example'),
          trustedFrontendOrigin: Uri.parse('https://app.gainer.example'),
        ),
      );

  @override
  Future<ApiDashboardInsights> getDashboardInsights({
    int days = 30,
    DateTime? through,
  }) async => ApiDashboardInsights(
    asOfRevision: 1,
    from: '2026-09-15',
    through: '2026-10-14',
    weightSeries: const [
      ApiWeightPoint(date: '2026-10-01', weightKg: 83.4),
      ApiWeightPoint(date: '2026-10-06', weightKg: 82.9),
      ApiWeightPoint(date: '2026-10-10', weightKg: 82.7),
      ApiWeightPoint(date: '2026-10-14', weightKg: 82.4),
    ],
    sevenDayWeight: const ApiWeightInsights(
      unit: 'kg',
      expectedDays: 7,
      observedDays: 4,
      coverage: .57,
      averageKg: 82.7,
      trendKgPerWeek: -.3,
    ),
    weight: const ApiWeightInsights(
      unit: 'kg',
      expectedDays: 30,
      observedDays: 11,
      coverage: .36,
      averageKg: 82.9,
      trendKgPerWeek: -.4,
    ),
    nutrition: const ApiNutritionInsights(
      expectedDays: 30,
      observedDays: 9,
      coverage: .3,
      mealDiaryDays: 9,
      legacyCheckInDays: 4,
      caloriesKcal: ApiMetricAverage(observedDays: 8, value: 2130),
      proteinGrams: ApiMetricAverage(observedDays: 8, value: 148),
      carbohydrateGrams: ApiMetricAverage(observedDays: 8, value: 220),
      fatGrams: ApiMetricAverage(observedDays: 8, value: 66),
    ),
    training: const ApiTrainingInsights(
      workoutCount: 6,
      volumeKgRepetitions: 12480,
    ),
    workoutsLast7Days: 3,
    activeGoal: const ApiActiveGoalInsight(
      kind: 'cut',
      startWeightKg: 84,
      targetWeightKg: 78,
      startDate: '2026-09-15',
    ),
    latestWeight: const ApiWeightPoint(date: '2026-10-14', weightKg: 82.4),
  );

  @override
  Future<ApiExerciseProgress> getExerciseProgress({
    required String exerciseId,
    required String window,
    String timeZone = 'Europe/Berlin',
  }) async {
    final now = DateTime.now().toUtc();
    final days = window == 'all' ? 90 : int.parse(window);
    final points = [
      for (final (index, day) in [days, (days / 2).round(), 0].indexed)
        ApiExerciseProgressPoint(
          workoutId:
              '00000000-0000-4000-8000-${(index + 6).toString().padLeft(12, '0')}',
          completedAtUtc: now.subtract(Duration(days: day)),
          volumeKgRepetitions: 5400 + (index * 360),
          bestWeightKg: 90 + (index * 2),
          bestRepetitions: 8,
          estimatedOneRepMaxKg: 114 + (index * 3),
        ),
    ];
    final last = points.last;
    return ApiExerciseProgress(
      asOfRevision: 1,
      exerciseId: exerciseId,
      windowDays: window == 'all' ? null : days,
      fromUtc: now.subtract(Duration(days: days)),
      throughUtc: now,
      points: points,
      bestSet: ApiBestSetInsight(
        workoutId: last.workoutId,
        exerciseId: exerciseId,
        completedAtUtc: last.completedAtUtc,
        weightKg: last.bestWeightKg!,
        repetitions: last.bestRepetitions!,
        estimatedOneRepMaxKg: last.estimatedOneRepMaxKg!,
      ),
    );
  }
}

class _FixtureExerciseCatalog implements ExerciseCatalogProvider {
  @override
  Future<List<ExerciseCatalogEntry>> loadExercises() async => const [
    ExerciseCatalogEntry(
      id: '00000000-0000-4000-8000-000000000004',
      name: 'Kniebeuge',
      catalogVersion: 1,
    ),
    ExerciseCatalogEntry(
      id: '00000000-0000-4000-8000-000000000005',
      name: 'Rudern',
      catalogVersion: 1,
    ),
  ];
}

class _FixtureNativeFeatures
    implements
        CapturePlatform,
        TimerNotificationPlatform,
        HapticsPlatform,
        HealthPlatform,
        ExtensionSnapshotPlatform,
        LiveActivityPlatform {
  @override
  Future<String?> scanBarcode() async => null;

  @override
  Future<CapturedImage?> capturePhoto() async => null;

  @override
  Future<CapturedImage?> chooseImage() async => null;

  @override
  Future<void> perform(HapticIntent intent) async {}

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> schedule({
    required String workoutId,
    required int generation,
    required DateTime targetAtUtc,
  }) async {}

  @override
  Future<void> cancel(String workoutId) async {}

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<PlatformAuthorizationRequestResult>
  requestBodyMassReadAuthorization() async =>
      PlatformAuthorizationRequestResult.requestCompleted;

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
    syncIdentifier: 'fixture',
    syncVersion: 1,
  );

  @override
  Future<void> publish(NeutralExtensionSnapshot snapshot) async {}

  @override
  Future<void> clear({required int minimumGeneration}) async {}

  @override
  Future<bool> start({required LiveActivityState state}) async => false;

  @override
  Future<bool> update({required LiveActivityState state}) async => false;

  @override
  Future<void> end(String sessionId) async {}

  @override
  Future<void> endAll() async {}
}
