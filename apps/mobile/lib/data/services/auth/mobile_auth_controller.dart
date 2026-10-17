import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../ui/core/view_models/mobile_shell_view_model.dart';
import '../../../ui/features/body/body_view_model.dart';
import '../../../ui/features/body/health/health_review_view_model.dart';
import '../../../ui/features/coach/coach_view_model.dart';
import '../../../ui/features/nutrition/nutrition_view_model.dart';
import '../../../ui/features/progress/progress_view_model.dart';
import '../../../ui/features/training/active_workout_controller.dart';
import '../../../ui/features/training/rest_timer_controller.dart';
import '../../models/api/api_models.dart';
import '../../models/local/local_mutation.dart';
import '../../repositories/body/body_repository.dart';
import '../../repositories/health/health_review_coordinator.dart';
import '../../repositories/insights/insights_repository.dart';
import '../../repositories/nutrition/api_nutrition_online_provider.dart';
import '../../repositories/nutrition/nutrition_repository.dart';
import '../../repositories/sync/local_sync_store.dart';
import '../../repositories/sync/sync_repository.dart';
import '../../repositories/timer/rest_timer_store.dart';
import '../../repositories/training/api_exercise_catalog_provider.dart';
import '../../repositories/training/training_log_repository.dart';
import '../../services/api/api_client.dart';
import '../../services/api/api_session_service.dart';
import '../../services/local/local_database.dart';
import '../../services/local/pending_handover_secret_store.dart';
import '../../services/native/native_feature_lifecycle_coordinator.dart';
import '../../services/native/rest_timer_alert_port.dart';
import '../../services/native/training_live_activity_coordinator.dart';
import '../../services/platform/pigeon_native_features_platform.dart';
import '../../services/platform/platform_ports.dart';
import '../platform/pigeon_pending_handover_secret_store.dart';
import '../platform/pigeon_secure_session_platform.dart';
import 'sync_foreground_scheduler.dart';

const _operatorAccessRequiredMessage = 'Operator access is required.';
const _operatorOnlineRequiredMessage =
    'Operatoraktionen erfordern eine Online-Sitzung.';

class MobileAppConfiguration {
  const MobileAppConfiguration({
    required this.api,
    required this.trustedOrigin,
  });
  final Uri api;
  final Uri trustedOrigin;

  static MobileAppConfiguration? fromEnvironment({bool debug = kDebugMode}) {
    const rawApi = String.fromEnvironment('GAINER_API_ORIGIN');
    const rawTrustedOrigin = String.fromEnvironment(
      'GAINER_TRUSTED_FRONTEND_ORIGIN',
    );
    const loopbackOptIn = bool.fromEnvironment('GAINER_ALLOW_LOOPBACK_HTTP');
    if (rawApi.isEmpty) return null;
    final api = Uri.tryParse(rawApi);
    final trusted = rawTrustedOrigin.isEmpty
        ? api
        : Uri.tryParse(rawTrustedOrigin);
    if (api == null || trusted == null) return null;
    final allowLoopback =
        debug && loopbackOptIn && _isLoopback(api) && _isLoopback(trusted);
    try {
      ApiConfiguration(
        apiOrigin: api,
        trustedFrontendOrigin: trusted,
        allowInsecureLoopbackForDevelopment: allowLoopback,
      );
    } on ArgumentError {
      return null;
    }
    return MobileAppConfiguration(api: api, trustedOrigin: trusted);
  }

  static bool _isLoopback(Uri value) =>
      const {'localhost', '127.0.0.1', '::1'}.contains(value.host);
}

enum MobileAuthState { starting, signedOut, signedIn, offlineKnownUser }

ApiClient _createDefaultApi(ApiConfiguration configuration) =>
    ApiClient(configuration: configuration);

/// Owns the active account scope. A profile becomes available only after the
/// API confirms its identity or after a valid secure checkpoint identifies a
/// previously authenticated local profile.
class MobileAuthController extends ChangeNotifier
    implements NativeRouteConsumer {
  MobileAuthController({
    required this.configuration,
    ApiClient Function(ApiConfiguration configuration)? apiFactory,
    SecureSessionPlatform? secureSessions,
    PendingHandoverSecretStore? handoverSecrets,
    PigeonNativeFeaturesPlatform? nativeFeatures,
    CapturePlatform? capture,
    HealthPlatform? health,
    ExtensionSnapshotPlatform? snapshots,
    HapticsPlatform? haptics,
    Future<LocalDatabase> Function(String accountId)? accountDatabaseFactory,
    Future<LocalDatabase> Function()? installationDatabaseFactory,
  }) : apiFactory = apiFactory ?? _createDefaultApi,
       secureSessions = secureSessions ?? PigeonSecureSessionPlatform(),
       handoverSecrets = handoverSecrets ?? PigeonPendingHandoverSecretStore(),
       nativeFeatures = nativeFeatures ?? PigeonNativeFeaturesPlatform(),
       capture = capture ?? nativeFeatures ?? PigeonNativeFeaturesPlatform(),
       health = health ?? nativeFeatures ?? PigeonNativeFeaturesPlatform(),
       snapshots =
           snapshots ?? nativeFeatures ?? PigeonNativeFeaturesPlatform(),
       haptics = haptics ?? nativeFeatures ?? PigeonNativeFeaturesPlatform(),
       accountDatabaseFactory =
           accountDatabaseFactory ?? LocalDatabase.openForAccount,
       installationDatabaseFactory =
           installationDatabaseFactory ?? LocalDatabase.openInstallationStore;

  final MobileAppConfiguration configuration;
  final ApiClient Function(ApiConfiguration configuration) apiFactory;
  final SecureSessionPlatform secureSessions;
  final PendingHandoverSecretStore handoverSecrets;
  final PigeonNativeFeaturesPlatform nativeFeatures;
  final CapturePlatform capture;
  final HealthPlatform health;
  final ExtensionSnapshotPlatform snapshots;
  final HapticsPlatform haptics;
  final Future<LocalDatabase> Function(String accountId) accountDatabaseFactory;
  final Future<LocalDatabase> Function() installationDatabaseFactory;
  final MobileShellViewModel shell = MobileShellViewModel();
  MobileAuthState state = MobileAuthState.starting;
  AccountScope? account;
  String? errorMessage;
  String? statusMessage;
  ApiClient? _api;
  LocalDatabase? _installationDatabase;
  bool _disposed = false;
  int _sessionGeneration = 0;

  @override
  Future<bool> hasActiveAccountSession() async =>
      account != null &&
      (state == MobileAuthState.signedIn ||
          state == MobileAuthState.offlineKnownUser);

  Future<void> initialize() async {
    try {
      _installationDatabase = await installationDatabaseFactory();
      final api = _newApi();
      _api = api;
      final sessions = ApiSessionService(
        api: api,
        secureStorage: secureSessions,
      );
      try {
        final session = await sessions.restore();
        if (session != null) {
          await _openAccount(session, online: true);
          if (!_disposed) notifyListeners();
          return;
        }
      } on ApiException catch (error) {
        if (error.code != 'network_error') rethrow;
        final bytes = await secureSessions.readCheckpoint(
          api.configuration.canonicalApiOrigin,
        );
        if (bytes == null || bytes.isEmpty) rethrow;
        final checkpoint = await api.restoreSecureCheckpoint(bytes);
        await _openAccount(
          ApiSession(
            userId: checkpoint.userId,
            email: checkpoint.email,
            isAccountOperator: false,
          ),
          online: false,
        );
        if (!_disposed) notifyListeners();
        return;
      }
      api.close();
      _api = null;
      state = MobileAuthState.signedOut;
    } catch (_) {
      state = MobileAuthState.signedOut;
      errorMessage = 'Die gespeicherte Sitzung konnte nicht wiederhergestellt werden. Melde dich erneut an.';
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> login(String email, String password) async {
    errorMessage = null;
    statusMessage = null;
    await _closeCurrentAccount();
    final api = _newApi();
    _api = api;
    try {
      final sessions = ApiSessionService(
        api: api,
        secureStorage: secureSessions,
      );
      final session = await sessions.login(email.trim(), password);
      await _openAccount(session, online: true);
    } on ApiException catch (error) {
      api.close();
      _api = null;
      errorMessage = error.statusCode == 401
          ? 'E-Mail-Adresse oder Passwort stimmen nicht.'
          : 'Anmeldung derzeit nicht möglich. Prüfe die Verbindung und versuche es erneut.';
    } catch (_) {
      api.close();
      _api = null;
      errorMessage =
          'Anmeldung fehlgeschlagen. Deine lokalen Profile bleiben erhalten.';
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> acceptInvitation(String token, String password) async {
    final api = _api ?? _newApi();
    _api = api;
    errorMessage = null;
    statusMessage = null;
    try {
      await ApiSessionService(
        api: api,
        secureStorage: secureSessions,
      ).acceptInvitation(token, password);
      statusMessage =
          'Einladung angenommen. Melde dich jetzt mit deinem neuen Konto an.';
    } catch (_) {
      errorMessage = 'Die Einladung konnte nicht bestätigt werden. Prüfe den Link und versuche es erneut.';
    }
    if (!_disposed) notifyListeners();
  }

  Future<List<ApiAccountSummary>> listOperatorAccounts() async {
    final scope = account;
    if (scope == null || !scope.session.isAccountOperator) {
      throw StateError(_operatorAccessRequiredMessage);
    }
    if (!scope.online) {
      throw const ApiException(
        statusCode: null,
        code: 'network_error',
        message: _operatorOnlineRequiredMessage,
      );
    }
    return scope.api.listAccounts();
  }

  Future<ApiInvitation> createOperatorInvitation(String email) async {
    final scope = account;
    if (scope == null || !scope.session.isAccountOperator) {
      throw StateError(_operatorAccessRequiredMessage);
    }
    if (!scope.online) {
      throw const ApiException(
        statusCode: null,
        code: 'network_error',
        message: _operatorOnlineRequiredMessage,
      );
    }
    return scope.api.createInvitation(email.trim());
  }

  Future<void> setOperatorAccountStatus(String accountId, bool isActive) async {
    final scope = account;
    if (scope == null || !scope.session.isAccountOperator) {
      throw StateError(_operatorAccessRequiredMessage);
    }
    if (!scope.online) {
      throw const ApiException(
        statusCode: null,
        code: 'network_error',
        message: _operatorOnlineRequiredMessage,
      );
    }
    await scope.api.setAccountStatus(accountId, isActive);
  }

  Future<void> logout() async {
    final api = _api;
    await _closeCurrentAccount(closeApi: false);
    if (api != null) {
      try {
        await ApiSessionService(
          api: api,
          secureStorage: secureSessions,
        ).logout();
      } catch (_) {
        // Local session and account scope are cleared in the service finally path.
      } finally {
        api.close();
      }
    }
    _api = null;
    state = MobileAuthState.signedOut;
    errorMessage = null;
    if (!_disposed) notifyListeners();
  }

  @override
  Future<void> onRouteRequested(NativeAppRouteRequest request) async {
    final routeScope = account;
    final generation = _sessionGeneration;
    if (routeScope == null || !await hasActiveAccountSession()) {
      throw StateError('An active account is required for native routes.');
    }
    if (_disposed ||
        !identical(account, routeScope) ||
        generation != _sessionGeneration ||
        !routeScope.isSessionActive()) {
      throw StateError('The account changed before the native route opened.');
    }
    final index = switch (request.destination) {
      NativeAppRoute.training => MobileArea.training.index,
      NativeAppRoute.checkIn => MobileArea.body.index,
      NativeAppRoute.nutrition => MobileArea.nutrition.index,
    };
    if (_disposed ||
        !identical(account, routeScope) ||
        generation != _sessionGeneration) {
      throw StateError('The account changed before the native route opened.');
    }
    shell.selectTab(index);
    // Die Live Activity öffnet das aktive Training; sonst bleibt es beim Tab.
    final active = routeScope.activeWorkout.active;
    if (request.source == NativeRouteSource.liveActivity &&
        request.destination == NativeAppRoute.training &&
        active != null) {
      shell.requestOpenWorkout(active.workoutId);
    }
  }

  Future<void> _openAccount(ApiSession session, {required bool online}) async {
    final api = _api;
    final installDb = _installationDatabase;
    if (api == null || installDb == null) {
      throw StateError('App storage is not ready.');
    }
    final db = await accountDatabaseFactory(session.userId);
    final store = LocalSyncStore(database: db, accountId: session.userId);
    await store.ensureAccountBound();
    final generation = ++_sessionGeneration;
    final identity = InstallationIdentityStore(installDb);
    final sync = SyncRepository(
      store: store,
      api: api,
      installationIdentity: identity,
      displayName: 'Gainer iPhone',
      handoverSecrets: handoverSecrets,
    );
    final body = BodyRepository(store: store);
    final training = TrainingLogRepository(
      store: store,
      catalog: ApiExerciseCatalogProvider(api, store: store),
    );
    final restTimerStore = RestTimerStore(store: store);
    final activeWorkout = ActiveWorkoutController(
      training,
      restTimerFactory: (workoutId) => RestTimerController(
        workoutId: workoutId,
        store: restTimerStore,
        notifications: nativeFeatures,
        haptics: haptics,
        alerts: const SystemRestTimerAlertPort(),
      ),
    );
    final nutrition = NutritionRepository(
      store: store,
      online: online ? ApiNutritionOnlineProvider(api) : null,
      capture: capture,
    );
    final bodyViewModel = BodyViewModel(body);
    final nutritionViewModel = NutritionViewModel(
      repository: nutrition,
      localDate: DateTime.now().toIso8601String().substring(0, 10),
    );
    late final AccountScope nextScope;
    final syncScheduler = SyncForegroundScheduler(
      synchronize: () => nextScope.synchronize(),
      isActive: () =>
          identical(account, nextScope) && _sessionGeneration == generation,
    );
    final healthViewModel = HealthReviewViewModel(
      HealthReviewCoordinator(
        store: store,
        bodyRepository: body,
        platform: health,
        accountId: session.userId,
        currentSessionIdentity: () {
          if (!identical(account, nextScope) ||
              _sessionGeneration != generation) {
            return null;
          }
          return HealthSessionIdentity(
            accountId: session.userId,
            generation: generation,
          );
        },
      ),
    );
    final progressViewModel = ProgressViewModel(
      InsightsRepository(api, store: store),
      training: training,
    );
    final coachViewModel = CoachViewModel(CoachRepository(api));
    nextScope = AccountScope(
      session: session,
      generation: generation,
      api: api,
      database: db,
      store: store,
      sync: sync,
      syncScheduler: syncScheduler,
      isSessionActive: () =>
          identical(account, nextScope) && _sessionGeneration == generation,
      online: online,
      bodyViewModel: bodyViewModel,
      training: training,
      activeWorkout: activeWorkout,
      nutritionViewModel: nutritionViewModel,
      healthViewModel: healthViewModel,
      progressViewModel: progressViewModel,
      coachViewModel: coachViewModel,
      trainingLiveActivity: TrainingLiveActivityCoordinator(
        activeWorkout: activeWorkout,
        platform: nativeFeatures,
        preferences: training.preferences,
        isSessionActive: () =>
            identical(account, nextScope) && _sessionGeneration == generation,
      ),
      nativeLifecycle: NativeFeatureLifecycleCoordinator(
        installationDatabase: installDb,
        body: bodyViewModel,
        nutrition: nutritionViewModel,
        snapshots: snapshots,
        haptics: haptics,
        isSessionActive: () =>
            identical(account, nextScope) && _sessionGeneration == generation,
      ),
    );
    account = nextScope;
    nextScope.nativeLifecycle.activate();
    unawaited(nextScope.syncScheduler.start());
    unawaited(
      nextScope.activeWorkout.load().whenComplete(
        nextScope.trainingLiveActivity.activate,
      ),
    );
    state = online
        ? MobileAuthState.signedIn
        : MobileAuthState.offlineKnownUser;
    unawaited(_retryPendingNativeRoute(nextScope, generation));
  }

  Future<void> _retryPendingNativeRoute(
    AccountScope scope,
    int generation,
  ) async {
    try {
      final route = await nativeFeatures.readPendingRoute();
      if (route == null ||
          _disposed ||
          !identical(account, scope) ||
          _sessionGeneration != generation ||
          !scope.isSessionActive()) {
        return;
      }
      final nowUtc = DateTime.now().toUtc();
      final createdAtUtc = DateTime.fromMillisecondsSinceEpoch(
        route.createdAtUtcEpochMilliseconds,
        isUtc: true,
      );
      final age = nowUtc.difference(createdAtUtc);
      if (age.isNegative || age > const Duration(minutes: 10)) {
        // Ask Swift to validate the current stored value; a new route may have
        // replaced this one since readPendingRoute completed.
        await nativeFeatures.retryPendingRoute();
        return;
      }
      if (_disposed ||
          !identical(account, scope) ||
          _sessionGeneration != generation ||
          !scope.isSessionActive()) {
        return;
      }
      await nativeFeatures.retryPendingRoute();
    } catch (_) {
      // Keep a valid route queued when the native bridge is temporarily unavailable.
    }
  }

  ApiClient _newApi() => apiFactory(
    ApiConfiguration(
      apiOrigin: configuration.api,
      trustedFrontendOrigin: configuration.trustedOrigin,
      allowInsecureLoopbackForDevelopment:
          configuration.api.scheme == 'http' && kDebugMode,
    ),
  );

  Future<void> _closeCurrentAccount({bool closeApi = true}) async {
    final current = account;
    account = null;
    _sessionGeneration++;
    if (current != null) await current.dispose(closeApi: closeApi);
  }

  @override
  void dispose() {
    _disposed = true;
    final current = account;
    account = null;
    final api = _api;
    _api = null;
    final installationDatabase = _installationDatabase;
    _installationDatabase = null;
    if (current == null) {
      api?.close();
      installationDatabase?.close();
    } else {
      unawaited(
        current
            .dispose(closeApi: false)
            .whenComplete(() async {
              api?.close();
              await installationDatabase?.close();
            })
            .catchError((Object _) async {
              api?.close();
              await installationDatabase?.close();
            }),
      );
    }
    shell.dispose();
    super.dispose();
  }
}

class AccountScope {
  AccountScope({
    required this.session,
    required this.generation,
    required this.api,
    required this.database,
    required this.store,
    required this.sync,
    required this.syncScheduler,
    required this.isSessionActive,
    required this.online,
    required this.bodyViewModel,
    required this.training,
    required this.activeWorkout,
    required this.nutritionViewModel,
    required this.healthViewModel,
    required this.progressViewModel,
    required this.coachViewModel,
    required this.nativeLifecycle,
    required this.trainingLiveActivity,
  }) {
    _localCommitSubscription = store.committedMutations.listen((mutation) {
      if (mutation.accountId == session.userId && isSessionActive()) {
        unawaited(syncScheduler.onLocalCommit());
      }
    });
  }
  final ApiSession session;
  final int generation;
  final ApiClient api;
  final LocalDatabase database;
  final LocalSyncStore store;
  final SyncRepository sync;
  final SyncForegroundScheduler syncScheduler;
  final bool Function() isSessionActive;
  final bool online;
  final BodyViewModel bodyViewModel;
  final TrainingLogRepository training;
  final ActiveWorkoutController activeWorkout;
  final NutritionViewModel nutritionViewModel;
  final HealthReviewViewModel healthViewModel;
  final ProgressViewModel progressViewModel;
  final CoachViewModel coachViewModel;
  final NativeFeatureLifecycleCoordinator nativeLifecycle;
  final TrainingLiveActivityCoordinator trainingLiveActivity;
  Future<SyncRunReport>? _syncInFlight;
  late final StreamSubscription<LocalMutation> _localCommitSubscription;

  Future<SyncRunReport> synchronize() {
    if (!isSessionActive()) {
      throw StateError('This account scope is no longer active.');
    }
    return _synchronizeIfWritable();
  }

  Future<SyncRunReport> _synchronizeIfWritable() async {
    final frozen = await store.readSyncMetadata('local-writes-frozen');
    if (!isSessionActive()) {
      throw StateError('This account scope is no longer active.');
    }
    if (frozen == true) {
      syncScheduler.pause();
      return const SyncRunReport(
        state: SyncRunState.busy,
        pushed: 0,
        pulledBatches: 0,
      );
    }
    syncScheduler.allow();
    final active = _syncInFlight;
    if (active != null) return active;
    final run = _synchronizeAndRefresh();
    _syncInFlight = run;
    return run.whenComplete(() {
      if (identical(_syncInFlight, run)) _syncInFlight = null;
    });
  }

  Future<void> onForeground() => syncScheduler.onForeground();

  Future<SyncRunReport> _synchronizeAndRefresh() async {
    final report = await sync.synchronize();
    if (!isSessionActive()) return report;
    if ({
      SyncRunState.idle,
      SyncRunState.synced,
      SyncRunState.retryPending,
      SyncRunState.inactiveClient,
    }.contains(report.state)) {
      await Future.wait([
        bodyViewModel.load(),
        nutritionViewModel.load(),
        activeWorkout.load(),
      ]);
    }
    return report;
  }

  Future<void> dispose({bool closeApi = true}) async {
    await _localCommitSubscription.cancel();
    await trainingLiveActivity.dispose();
    activeWorkout.dispose();
    await syncScheduler.dispose();
    final syncRun = _syncInFlight;
    if (syncRun != null) {
      try {
        await syncRun;
      } catch (_) {
        // Network failures do not prevent an old account scope from closing.
      }
    }
    await nativeLifecycle.disposeForSessionEnd();
    bodyViewModel.dispose();
    nutritionViewModel.dispose();
    healthViewModel.dispose();
    progressViewModel.dispose();
    coachViewModel.dispose();
    if (closeApi) api.close();
    await store.close();
  }
}
