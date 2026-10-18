import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:gainer_mobile/data/models/api/api_models.dart';
import 'package:gainer_mobile/data/repositories/body/body_repository.dart';
import 'package:gainer_mobile/data/repositories/health/health_review_coordinator.dart';
import 'package:gainer_mobile/data/repositories/insights/insights_repository.dart';
import 'package:gainer_mobile/data/repositories/nutrition/nutrition_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/repositories/sync/sync_repository.dart';
import 'package:gainer_mobile/data/repositories/training/api_exercise_catalog_provider.dart';
import 'package:gainer_mobile/data/repositories/training/training_log_repository.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';
import 'package:gainer_mobile/data/services/auth/mobile_auth_controller.dart';
import 'package:gainer_mobile/data/services/auth/sync_foreground_scheduler.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/data/services/native/native_feature_lifecycle_coordinator.dart';
import 'package:gainer_mobile/data/services/native/training_live_activity_coordinator.dart';
import 'package:gainer_mobile/data/services/platform/generated/mobile_platform_api.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';
import 'package:gainer_mobile/domain/models/body/body_tracking.dart';
import 'package:gainer_mobile/domain/models/nutrition/nutrition.dart';
import 'package:gainer_mobile/domain/models/training/exercise_catalog_model.dart';
import 'package:gainer_mobile/domain/models/training/training_plan_model.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/ui/core/shell/mobile_shell.dart';
import 'package:gainer_mobile/ui/features/body/body_view_model.dart';
import 'package:gainer_mobile/ui/features/body/health/health_review_view_model.dart';
import 'package:gainer_mobile/ui/features/coach/coach_view_model.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_view_model.dart';
import 'package:gainer_mobile/ui/features/progress/progress_view_model.dart';
import 'package:gainer_mobile/ui/features/training/active_workout_controller.dart';

const _accountId = '00000000-0000-4000-8000-000000000003';

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

  final trainingLog = TrainingLogRepository(
    store: store,
    catalog: _FixtureExerciseCatalog(),
  );
  final plan = await trainingLog.createPlan(
    TrainingPlanModel(
      planId: '00000000-0000-4000-8000-000000000006',
      name: 'Ganzkörper A',
      previousValueSource: PreviousValueSource.exercise,
      entries: [
        PlanEntry(
          entryId: 'plan-entry-1',
          exerciseId: '00000000-0000-4000-8000-000000000004',
          workingSets: 3,
        ),
      ],
    ),
  );
  await trainingLog.saveRotation([plan.planId]);
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
  final nutrition = NutritionViewModel(
    repository: nutritionRepository,
    localDate: today,
  );
  final progress = ProgressViewModel(InsightsRepository(api, store: store));
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
  final activeWorkout = ActiveWorkoutController(trainingLog);
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
    training: trainingLog,
    activeWorkout: activeWorkout,
    nutritionViewModel: nutrition,
    healthViewModel: health,
    progressViewModel: progress,
    coachViewModel: CoachViewModel(CoachRepository(api)),
    trainingLiveActivity: TrainingLiveActivityCoordinator(
      activeWorkout: activeWorkout,
      platform: native,
      preferences: trainingLog.preferences,
      isSessionActive: isActive,
    ),
    nativeLifecycle: NativeFeatureLifecycleCoordinator(
      installationDatabase: database,
      body: body,
      nutrition: nutrition,
      snapshots: native,
      haptics: native,
      isSessionActive: isActive,
    ),
  );
  await account.syncStatusLoaded;
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
      volumeAlgorithmVersion: 'training-volume-v2',
      estimatedOneRepMaxAlgorithmVersion: 'e1rm-epley-v2',
      volumeUnit: 'kg-repetitions',
      bestSet: null,
      bodyweightMissing: false,
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
          bodyweightMissing: false,
          maxWeightKg: 90 + (index * 2),
          maxRepetitions: 8,
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
      volumeAlgorithmVersion: 'training-volume-v2',
      estimatedOneRepMaxAlgorithmVersion: 'e1rm-epley-v2',
      records: const ApiExerciseRecords(
        maxWeightKg: null,
        estimatedOneRepMaxKg: null,
        volumeKgRepetitions: null,
        maxRepetitions: null,
        repetitionRecords: [],
      ),
      bestSet: ApiBestSetInsight(
        workoutId: last.workoutId,
        exerciseId: exerciseId,
        completedAtUtc: last.completedAtUtc,
        effectiveWeightKg: last.maxWeightKg!,
        repetitions: last.maxRepetitions,
        estimatedOneRepMaxKg: last.estimatedOneRepMaxKg!,
      ),
    );
  }
}

class _FixtureExerciseCatalog implements ExerciseCatalogProvider {
  @override
  bool get lastLoadWasStale => false;

  @override
  Future<BaseCatalog> loadBaseCatalog() async => const BaseCatalog(
    exercises: [
      CatalogExercise(
        id: '00000000-0000-4000-8000-000000000004',
        name: 'Kniebeuge',
        exerciseType: ExerciseKind.strength,
        isBase: true,
      ),
      CatalogExercise(
        id: '00000000-0000-4000-8000-000000000005',
        name: 'Rudern',
        exerciseType: ExerciseKind.strength,
        isBase: true,
      ),
    ],
    categories: [],
  );
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
    required String soundId,
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
  requestCheckInAuthorization() async =>
      PlatformAuthorizationRequestResult.requestCompleted;

  @override
  Future<int?> readStepCount({
    required DateTime fromUtc,
    required DateTime toUtc,
  }) async => null;

  @override
  Future<HealthSleepWindow?> readSleep({
    required DateTime fromUtc,
    required DateTime toUtc,
  }) async => null;

  @override
  Future<HealthWriteStatus> writeBodyMass({
    required double kilograms,
    required DateTime measuredAtUtc,
    required String syncIdentifier,
  }) async => HealthWriteStatus.notAuthorized;

  @override
  Future<HealthWriteStatus> writeSleep({
    required DateTime bedtimeUtc,
    required DateTime wakeUtc,
    required String syncIdentifier,
  }) async => HealthWriteStatus.notAuthorized;

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

  @override
  Future<bool> isEnabled() async => true;

  @override
  Future<void> openSettings() async {}
}
