import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../models/api/api_models.dart';
import '../../models/api/strava_api_models.dart';
import '../../models/api/sync_api_models.dart';

const accountIdentityHeaderName = 'X-Gainer-Account-Id';
const syncProtocolVersion = 3;

/// Keychain checkpoint format. Version 1 held cookies, version 2 a refresh token.
const secureCheckpointSchemaVersion = 2;

class ApiConfiguration {
  ApiConfiguration({
    required this.apiOrigin,
    this.allowInsecureLoopbackForDevelopment = false,
  }) {
    _validateOrigin(
      apiOrigin,
      allowLoopbackHttp: allowInsecureLoopbackForDevelopment,
    );
  }

  final Uri apiOrigin;
  final bool allowInsecureLoopbackForDevelopment;

  String get canonicalApiOrigin => _canonicalOrigin(apiOrigin);
}

class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.errors,
  });

  final int? statusCode;
  final String code;
  final String message;

  /// Feldfehler eines `validation_failed`-Problems, nach Feldschlüssel.
  final Map<String, Object?>? errors;

  @override
  String toString() => message;
}

/// Bearer-token transport for the Gainer API. Access tokens are short-lived
/// and renewed with the rotating refresh token of the device session.
/// Redirects are rejected so tokens and request data cannot follow another host.
class ApiClient {
  ApiClient({required this.configuration, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now,
      _dio = Dio() {
    _dio.options = BaseOptions(
      baseUrl: '${configuration.canonicalApiOrigin}/',
      followRedirects: false,
      maxRedirects: 0,
      validateStatus: (status) => status != null && status < 600,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
    );
    _dio.interceptors.add(_ApiOriginGuard(configuration));
  }

  /// Renew the access token this long before it expires.
  static const accessTokenRenewalMargin = Duration(seconds: 30);

  final ApiConfiguration configuration;
  final Dio _dio;
  final DateTime Function() _clock;
  bool _closed = false;
  String? _accessToken;
  DateTime? _accessTokenExpiresAt;
  String? _refreshToken;
  Future<bool>? _refreshInFlight;

  /// Called with each new refresh token so it can be stored before the old one
  /// stops working.
  Future<void> Function(String refreshToken)? onRefreshTokenRotated;

  /// Called once when the server rejects the refresh token, i.e. the device
  /// session was revoked, expired or its account deactivated.
  void Function()? onSessionRejected;

  bool get hasDeviceSession => _refreshToken != null;

  Future<ApiSession?> getSession() async {
    final response = await _request(
      'GET',
      '/api/v1/auth/session',
      allow401: true,
    );
    if (response.statusCode == 401) return null;
    return ApiSession.fromJson(_asObject(response.data));
  }

  Future<ApiExerciseCatalogResponse> getExercises({
    String? search,
    String? targetMuscle,
    String? muscleGroup,
    String? equipment,
    int offset = 0,
    int limit = 100,
  }) async {
    if (offset < 0 || limit < 1 || limit > 100) {
      throw ArgumentError(
        'Exercise catalog offset or limit is outside the API contract.',
      );
    }
    final response = await _request(
      'GET',
      '/api/v1/exercises',
      queryParameters: {
        'offset': offset,
        'limit': limit,
        'search': ?search,
        'targetMuscle': ?targetMuscle,
        'muscleGroup': ?muscleGroup,
        'equipment': ?equipment,
      },
    );
    return ApiExerciseCatalogResponse.fromJson(_asObject(response.data));
  }

  Future<ApiFoodSearchResponse> searchFoods({
    required String query,
    int page = 1,
    int pageSize = 10,
  }) async {
    if (query.trim().length < 2 ||
        page < 1 ||
        page > 100 ||
        pageSize < 1 ||
        pageSize > 20) {
      throw ArgumentError(
        'Food search parameters are outside the API contract.',
      );
    }
    final response = await _request(
      'GET',
      '/api/v1/foods/search',
      queryParameters: {'query': query, 'page': page, 'pageSize': pageSize},
    );
    return ApiFoodSearchResponse.fromJson(_asObject(response.data));
  }

  Future<ApiDashboardInsights> getDashboardInsights({
    int days = 30,
    DateTime? through,
  }) async {
    if (days < 1 || days > 365) {
      throw ArgumentError.value(days, 'days', 'Expected 1 to 365 days.');
    }
    final response = await _request(
      'GET',
      '/api/v1/insights/dashboard',
      queryParameters: {
        'days': days,
        if (through != null) 'through': _dateOnly(through),
      },
    );
    return ApiDashboardInsights.fromJson(_asObject(response.data));
  }

  Future<ApiExerciseProgress> getExerciseProgress({
    required String exerciseId,
    required String window,
    String timeZone = 'Europe/Berlin',
  }) async {
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(exerciseId)) {
      throw ArgumentError.value(exerciseId, 'exerciseId', 'Expected a UUID.');
    }
    if (!const {'7', '30', '90', 'all'}.contains(window)) {
      throw ArgumentError.value(window, 'window', 'Expected 7, 30, 90 or all.');
    }
    if (timeZone.trim().isEmpty || timeZone.length > 100) {
      throw ArgumentError.value(timeZone, 'timeZone', 'Expected an IANA zone.');
    }
    final response = await _request(
      'GET',
      '/api/v1/insights/exercises/$exerciseId/progress',
      queryParameters: {'window': window, 'timeZone': timeZone},
    );
    return ApiExerciseProgress.fromJson(_asObject(response.data));
  }

  /// Coach answers are read-only, server-grounded suggestions. They do not
  /// write mutations or accept client-supplied facts.
  Future<ApiCoachResponse> askCoach(String question) async {
    if (question.trim().isEmpty || question.length > 1000) {
      throw ArgumentError.value(
        question,
        'question',
        'Expected 1 to 1000 characters.',
      );
    }
    final response = await _mutate(
      'POST',
      '/api/v1/coach/responses',
      body: {'question': question},
    );
    return ApiCoachResponse.fromJson(_asObject(response.data));
  }

  /// Notizen des Coach-Gedächtnisses, neueste zuerst.
  Future<ApiCoachMemoryList> listCoachMemories() async {
    final response = await _request('GET', '/api/v1/coach/memories');
    return ApiCoachMemoryList.fromJson(_asObject(response.data));
  }

  /// Legt eine Notiz an, auch um einen Vorschlag zu übernehmen. Ein schon
  /// vorhandener Text liefert den bestehenden Eintrag, mit der neuen
  /// Kategorie.
  Future<ApiCoachMemory> createCoachMemory(
    CoachMemoryCategory category,
    String text,
  ) async {
    final response = await _mutate(
      'POST',
      '/api/v1/coach/memories',
      body: _coachMemoryBody(category, text),
    );
    return ApiCoachMemory.fromJson(_asObject(response.data));
  }

  /// Ändert eine Notiz. Mit [baseVersion] lehnt der Server mit
  /// `memory_conflict` ab, wenn sie inzwischen anderswo geändert wurde.
  Future<ApiCoachMemory> updateCoachMemory(
    String id,
    CoachMemoryCategory category,
    String text, {
    int? baseVersion,
  }) async {
    _validateIdentifier(id, 'id');
    final response = await _mutate(
      'PUT',
      '/api/v1/coach/memories/$id',
      body: {..._coachMemoryBody(category, text), 'baseVersion': ?baseVersion},
    );
    return ApiCoachMemory.fromJson(_asObject(response.data));
  }

  Future<void> deleteCoachMemory(String id) async {
    _validateIdentifier(id, 'id');
    await _mutate('DELETE', '/api/v1/coach/memories/$id');
  }

  /// „Alles vergessen“.
  Future<void> deleteAllCoachMemories() async {
    await _mutate('DELETE', '/api/v1/coach/memories');
  }

  Map<String, Object?> _coachMemoryBody(
    CoachMemoryCategory category,
    String text,
  ) {
    if (!isValidCoachMemoryText(text)) {
      throw ArgumentError.value(
        text,
        'text',
        'Expected 1 to 200 UTF-16 code units.',
      );
    }
    return {'category': category.wireName, 'text': text.trim()};
  }

  Future<ApiFoodProduct> lookupFoodByBarcode(String barcode) async {
    if (!RegExp(r'^\d{4,32}$').hasMatch(barcode)) {
      throw ArgumentError.value(barcode, 'barcode', 'Expected 4 to 32 digits.');
    }
    final response = await _request('GET', '/api/v1/foods/barcode/$barcode');
    return ApiFoodProduct.fromJson(_asObject(response.data));
  }

  /// Fragt die KI nach den Muskeln einer Übung. Die Antwort ist eine
  /// Rückfrage (`kind: question`) oder ein Vorschlag (`kind: suggestion`).
  Future<Map<String, dynamic>> suggestMuscles({
    required String name,
    required String exerciseType,
    String? notes,
    List<Map<String, Object?>> turns = const [],
  }) async {
    final response = await _mutate(
      'POST',
      '/api/v1/exercises/muscle-suggestions',
      body: {
        'name': name,
        'exerciseType': exerciseType,
        'notes': notes,
        'turns': turns,
      },
    );
    return _asObject(response.data);
  }

  /// Alle eigenen Daten als JSON-Objekt (`GET /api/v1/account/export`).
  Future<Map<String, Object?>> getAccountExport() async {
    final response = await _request(
      'GET',
      '/api/v1/account/export',
      // Bei vielen Trainings und Ernährungstagen ist die Antwort groß.
      receiveTimeout: const Duration(minutes: 2),
    );
    return _asObject(response.data);
  }

  Future<ApiStravaStatus> getStravaStatus() async {
    final response = await _request('GET', '/api/v1/integrations/strava');
    return ApiStravaStatus.fromJson(_asObject(response.data));
  }

  /// Strava-Zustimmungsseite mit an das Konto gebundenem `state`.
  Future<Uri> beginStravaAuthorization() async {
    final response = await _mutate(
      'POST',
      '/api/v1/integrations/strava/authorization',
    );
    final url = Uri.tryParse(
      _asObject(response.data)['authorizationUrl'] as String? ?? '',
    );
    if (url == null || url.scheme != 'https') {
      throw const FormatException('Ungültige Strava-Adresse.');
    }
    return url;
  }

  Future<ApiStravaStatus> updateStravaSettings({
    required bool exportCardio,
    required bool exportStrength,
  }) async {
    final response = await _mutate(
      'PUT',
      '/api/v1/integrations/strava/settings',
      body: {'exportCardio': exportCardio, 'exportStrength': exportStrength},
    );
    return ApiStravaStatus.fromJson(_asObject(response.data));
  }

  Future<void> disconnectStrava() async {
    await _mutate('DELETE', '/api/v1/integrations/strava');
  }

  /// Null, wenn die Einheit noch nicht an Strava ging.
  Future<ApiStravaExport?> getStravaExport(
    StravaExportKind kind,
    String resourceId,
  ) async {
    _validateIdentifier(resourceId, 'resourceId');
    try {
      final response = await _request(
        'GET',
        '/api/v1/integrations/strava/exports/${kind.wireName}/$resourceId',
      );
      return ApiStravaExport.fromJson(_asObject(response.data));
    } on ApiException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Sendet die Einheit jetzt an Strava, auch wenn die Art aus ist.
  Future<ApiStravaExport> requestStravaExport(
    StravaExportKind kind,
    String resourceId,
  ) async {
    _validateIdentifier(resourceId, 'resourceId');
    final response = await _mutate(
      'POST',
      '/api/v1/integrations/strava/exports/${kind.wireName}/$resourceId',
    );
    return ApiStravaExport.fromJson(_asObject(response.data));
  }

  /// Returns an estimate draft only. The caller must obtain explicit consent
  /// before sending an image and must require user review before creating a
  /// nutrition mutation.
  Future<ApiMealEstimateResponse> estimateMeal({
    String? text,
    Uint8List? imageBytes,
    String? imageContentType,
    bool imageConsent = false,
  }) async {
    if ((text == null || text.trim().isEmpty) && imageBytes == null) {
      throw ArgumentError('Meal estimate requires text or an image.');
    }
    if ((imageBytes == null) != (imageContentType == null)) {
      throw ArgumentError(
        'Image bytes and content type must be supplied together.',
      );
    }
    final fields = <String, Object>{'imageConsent': imageConsent.toString()};
    if (text != null && text.trim().isNotEmpty) fields['text'] = text;
    if (imageBytes != null) {
      if (!imageConsent) {
        throw ArgumentError('Image upload requires explicit consent.');
      }
      fields['image'] = _imagePart(imageBytes, imageContentType!);
    }
    final response = await _mutate(
      'POST',
      '/api/v1/nutrition/meal-estimates',
      body: FormData.fromMap(fields),
      // Mit Websuche braucht die Schätzung deutlich länger als andere Aufrufe.
      receiveTimeout: mealEstimateTimeout,
    );
    return ApiMealEstimateResponse.fromJson(_asObject(response.data));
  }

  /// Länger als das Server-Zeitlimit für OpenAI (75 s), damit der Server
  /// selbst mit einem verständlichen Fehler antworten kann.
  static const mealEstimateTimeout = Duration(seconds: 90);

  Future<ApiNutritionLabelScanResponse> scanNutritionLabel({
    required Uint8List imageBytes,
    required String imageContentType,
  }) async {
    final response = await _mutate(
      'POST',
      '/api/v1/nutrition/label-scans',
      body: FormData.fromMap({
        'image': _imagePart(imageBytes, imageContentType),
      }),
    );
    return ApiNutritionLabelScanResponse.fromJson(_asObject(response.data));
  }

  MultipartFile _imagePart(Uint8List bytes, String contentType) {
    if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024) {
      throw ArgumentError('Image must be between 1 byte and 8 MiB.');
    }
    final mediaType = switch (contentType.toLowerCase()) {
      'image/jpeg' => DioMediaType('image', 'jpeg'),
      'image/png' => DioMediaType('image', 'png'),
      'image/webp' => DioMediaType('image', 'webp'),
      _ => throw ArgumentError.value(
        contentType,
        'contentType',
        'Unsupported image media type.',
      ),
    };
    return MultipartFile.fromBytes(
      bytes,
      filename: 'upload.${mediaType.subtype}',
      contentType: mediaType,
    );
  }

  /// Starts a device session and keeps its tokens for later requests.
  Future<ApiTokenResponse> login(ApiLoginRequest request) async {
    clearTokens();
    final response = await _request(
      'POST',
      '/api/v1/auth/login',
      body: request.toJson(),
      authenticate: false,
    );
    final tokens = ApiTokenResponse.fromJson(_asObject(response.data));
    _applyTokens(tokens);
    return tokens;
  }

  Future<ApiPasskeyOptions> passkeyRequestOptions() async {
    final response = await _request(
      'POST',
      '/api/v1/auth/passkeys/request-options',
      authenticate: false,
    );
    return ApiPasskeyOptions.fromJson(_asObject(response.data));
  }

  /// Starts a device session with a passkey assertion.
  Future<ApiTokenResponse> loginWithPasskey({
    required String credentialJson,
    required String state,
    String? deviceName,
  }) async {
    clearTokens();
    final response = await _request(
      'POST',
      '/api/v1/auth/passkeys/login',
      body: {
        'credentialJson': credentialJson,
        'state': state,
        'deviceName': ?deviceName,
      },
      authenticate: false,
    );
    final tokens = ApiTokenResponse.fromJson(_asObject(response.data));
    _applyTokens(tokens);
    return tokens;
  }

  /// Without [password] this only works shortly after signing in; otherwise
  /// the server answers 403 `reauthentication_required`.
  Future<ApiPasskeyOptions> passkeyCreationOptions({String? password}) async {
    final response = await _mutate(
      'POST',
      '/api/v1/auth/passkeys/creation-options',
      body: password == null ? null : {'password': password},
    );
    return ApiPasskeyOptions.fromJson(_asObject(response.data));
  }

  Future<ApiPasskey> registerPasskey({
    required String credentialJson,
    required String state,
    String? name,
  }) async {
    final response = await _mutate(
      'POST',
      '/api/v1/auth/passkeys',
      body: {'credentialJson': credentialJson, 'state': state, 'name': ?name},
    );
    return ApiPasskey.fromJson(_asObject(response.data));
  }

  Future<List<ApiPasskey>> listPasskeys() async {
    final response = await _request('GET', '/api/v1/auth/passkeys');
    final value = response.data;
    if (value is! List ||
        value.any((entry) => entry is! Map<String, dynamic>)) {
      throw const FormatException('Invalid passkey list response.');
    }
    return value
        .cast<Map<String, dynamic>>()
        .map(ApiPasskey.fromJson)
        .toList(growable: false);
  }

  Future<void> deletePasskey(String id) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,1400}$').hasMatch(id)) {
      throw ArgumentError.value(
        id,
        'id',
        'Expected a Base64Url credential id.',
      );
    }
    await _mutate('DELETE', '/api/v1/auth/passkeys/$id');
  }

  /// Revokes the device session on the server and forgets its tokens.
  Future<void> logout() async {
    try {
      if (_refreshToken != null) await _mutate('POST', '/api/v1/auth/logout');
    } finally {
      clearTokens();
    }
  }

  /// Revokes every device session of the account, then forgets the tokens.
  /// Unlike [logout], a failure is reported, because other devices would stay
  /// signed in.
  Future<void> logoutAll() async {
    await _mutate('POST', '/api/v1/auth/logout-all');
    clearTokens();
  }

  Future<void> acceptInvitation(ApiAcceptInvitationRequest request) async {
    await _request(
      'POST',
      '/api/v1/auth/invitations/accept',
      body: request.toJson(),
      authenticate: false,
    );
  }

  Future<List<ApiAccountSummary>> listAccounts() async {
    final response = await _request('GET', '/api/v1/account-operator/accounts');
    final value = response.data;
    if (value is! List ||
        value.any((entry) => entry is! Map<String, dynamic>)) {
      throw const FormatException('Invalid account list response.');
    }
    return value
        .cast<Map<String, dynamic>>()
        .map(ApiAccountSummary.fromJson)
        .toList(growable: false);
  }

  Future<ApiInvitation> createInvitation(String email) async {
    final response = await _mutate(
      'POST',
      '/api/v1/account-operator/invitations',
      body: {'email': email},
    );
    return ApiInvitation.fromJson(_asObject(response.data));
  }

  Future<void> setAccountStatus(String accountId, bool isActive) async {
    _validateIdentifier(accountId, 'accountId');
    await _mutate(
      'PUT',
      '/api/v1/account-operator/accounts/$accountId/status',
      body: {'isActive': isActive},
    );
  }

  Future<SyncClientRegistrationResponse> registerSyncClient(
    SyncClientRegistrationRequest request, {
    required String expectedAccountId,
  }) async {
    _validateIdentifier(request.clientId, 'clientId');
    final response = await _mutate(
      'PUT',
      '/api/v1/sync/clients/${request.clientId}',
      body: request.toJson(),
      expectedAccountId: expectedAccountId,
    );
    return SyncClientRegistrationResponse.fromJson(_asObject(response.data));
  }

  Future<SyncMutationResponse> pushMutation({
    required String mutationId,
    required SyncMutationRequest mutation,
    required String expectedAccountId,
  }) async {
    _validateIdentifier(mutationId, 'mutationId');
    final response = await _mutate(
      'PUT',
      '/api/v1/sync/mutations/$mutationId',
      body: mutation.toJson(),
      expectedAccountId: expectedAccountId,
    );
    return SyncMutationResponse.fromJson(_asObject(response.data));
  }

  Future<SyncPullResponse> pullChanges({
    required int after,
    required String expectedAccountId,
    int limit = 200,
  }) async {
    _validateIdentifier(expectedAccountId, 'expectedAccountId');
    if (after < 0 || limit < 1 || limit > 200) {
      throw ArgumentError(
        'Sync cursor and limit are outside the API contract.',
      );
    }
    final response = await _request(
      'GET',
      '/api/v1/sync/changes',
      queryParameters: {'after': after, 'limit': limit},
      headers: {accountIdentityHeaderName: expectedAccountId},
    );
    return SyncPullResponse.fromJson(_asObject(response.data));
  }

  /// Calls the planned handover endpoint. The server contract is not deployed yet.
  Future<BeginSyncHandoverResponse> beginSyncHandover(
    BeginSyncHandoverRequest request, {
    required String expectedAccountId,
  }) async {
    final response = await _mutate(
      'POST',
      '/api/v1/sync/handovers',
      body: request.toJson(),
      expectedAccountId: expectedAccountId,
    );
    return BeginSyncHandoverResponse.fromJson(_asObject(response.data));
  }

  /// Calls the planned handover endpoint. The server contract is not deployed yet.
  Future<CompleteSyncHandoverResponse> completeSyncHandover({
    required String handoverId,
    required CompleteSyncHandoverRequest request,
    required String expectedAccountId,
  }) async {
    _validateIdentifier(handoverId, 'handoverId');
    final response = await _mutate(
      'POST',
      '/api/v1/sync/handovers/$handoverId/complete',
      body: request.toJson(),
      expectedAccountId: expectedAccountId,
    );
    return CompleteSyncHandoverResponse.fromJson(_asObject(response.data));
  }

  /// Calls the planned handover endpoint. The server contract is not deployed yet.
  Future<void> cancelSyncHandover({
    required String handoverId,
    required CancelSyncHandoverRequest request,
    required String expectedAccountId,
  }) async {
    _validateIdentifier(handoverId, 'handoverId');
    await _mutate(
      'POST',
      '/api/v1/sync/handovers/$handoverId/cancel',
      body: request.toJson(),
      expectedAccountId: expectedAccountId,
    );
  }

  /// Serializes the device session for the keychain. Only the refresh token
  /// is stored; access tokens are renewed after a restart.
  Uint8List createSecureCheckpoint(ApiSession session) {
    final refreshToken = _refreshToken;
    if (refreshToken == null) {
      throw StateError('No API device session is available.');
    }
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'schemaVersion': secureCheckpointSchemaVersion,
          'apiOrigin': configuration.canonicalApiOrigin,
          'userId': session.userId,
          'email': session.email,
          'refreshToken': refreshToken,
        }),
      ),
    );
  }

  /// Restores a device session written by [createSecureCheckpoint]. Older
  /// cookie checkpoints are rejected with a [FormatException], which signs the
  /// user out once.
  ApiSessionCheckpoint restoreSecureCheckpoint(Uint8List bytes) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic> ||
        decoded['schemaVersion'] != secureCheckpointSchemaVersion) {
      throw const FormatException('Unsupported secure session checkpoint.');
    }
    if (decoded['apiOrigin'] != configuration.canonicalApiOrigin) {
      throw const FormatException(
        'Session checkpoint belongs to another API host.',
      );
    }
    final userId = decoded['userId'];
    final email = decoded['email'];
    final refreshToken = decoded['refreshToken'];
    if (userId is! String ||
        email is! String ||
        refreshToken is! String ||
        refreshToken.isEmpty) {
      throw const FormatException('Invalid secure session checkpoint.');
    }
    clearTokens();
    _refreshToken = refreshToken;
    return ApiSessionCheckpoint(userId: userId, email: email);
  }

  void clearTokens() {
    _accessToken = null;
    _accessTokenExpiresAt = null;
    _refreshToken = null;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _dio.close(force: true);
  }

  Future<Response<dynamic>> _mutate(
    String method,
    String path, {
    Object? body,
    String? expectedAccountId,
    Duration? receiveTimeout,
  }) {
    if (expectedAccountId != null) {
      _validateIdentifier(expectedAccountId, 'expectedAccountId');
    }
    return _request(
      method,
      path,
      body: body,
      headers: {accountIdentityHeaderName: ?expectedAccountId},
      receiveTimeout: receiveTimeout,
    );
  }

  /// Exchanges the refresh token for a new pair. Concurrent callers share one
  /// request, because a refresh token is valid for a single rotation. Returns
  /// false when the server rejected the session.
  Future<bool> _refreshTokens() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;
    final run = _performRefresh();
    _refreshInFlight = run;
    return run.whenComplete(() {
      if (identical(_refreshInFlight, run)) _refreshInFlight = null;
    });
  }

  Future<bool> _performRefresh() async {
    final refreshToken = _refreshToken;
    if (refreshToken == null) return false;
    final response = await _send(
      'POST',
      '/api/v1/auth/refresh',
      body: {'refreshToken': refreshToken},
    );
    if (response.statusCode == 401) {
      if (_refreshToken == refreshToken) {
        clearTokens();
        onSessionRejected?.call();
      }
      return false;
    }
    _throwForStatus(response);
    // A logout or new login during the request owns the token state now.
    if (_refreshToken != refreshToken) return _refreshToken != null;
    final tokens = ApiTokenResponse.fromJson(_asObject(response.data));
    _applyTokens(tokens);
    await onRefreshTokenRotated?.call(tokens.refreshToken);
    return true;
  }

  void _applyTokens(ApiTokenResponse tokens) {
    _accessToken = tokens.accessToken;
    _accessTokenExpiresAt = _clock().add(Duration(seconds: tokens.expiresIn));
    _refreshToken = tokens.refreshToken;
  }

  bool get _accessTokenUsable {
    final expiresAt = _accessTokenExpiresAt;
    return _accessToken != null &&
        expiresAt != null &&
        _clock().isBefore(expiresAt.subtract(accessTokenRenewalMargin));
  }

  Future<Response<dynamic>> _request(
    String method,
    String path, {
    Object? body,
    Map<String, Object?>? queryParameters,
    Map<String, String>? headers,
    bool allow401 = false,
    bool authenticate = true,
    Duration? receiveTimeout,
  }) async {
    if (!authenticate) {
      final response = await _send(
        method,
        path,
        body: body,
        queryParameters: queryParameters,
        headers: headers,
        receiveTimeout: receiveTimeout,
      );
      _throwForStatus(response, allow401: allow401);
      return response;
    }
    if (!_accessTokenUsable && _refreshToken != null) {
      await _refreshTokens();
    }
    var response = await _send(
      method,
      path,
      body: body,
      queryParameters: queryParameters,
      headers: headers,
      accessToken: _accessToken,
      receiveTimeout: receiveTimeout,
    );
    // The token may have been revoked or expired early; retry once with a
    // fresh one. Multipart bodies cannot be resent and surface the 401.
    if (response.statusCode == 401 &&
        body is! FormData &&
        _refreshToken != null &&
        await _refreshTokens()) {
      response = await _send(
        method,
        path,
        body: body,
        queryParameters: queryParameters,
        headers: headers,
        accessToken: _accessToken,
        receiveTimeout: receiveTimeout,
      );
    }
    _throwForStatus(response, allow401: allow401);
    return response;
  }

  Future<Response<dynamic>> _send(
    String method,
    String path, {
    Object? body,
    Map<String, Object?>? queryParameters,
    Map<String, String>? headers,
    String? accessToken,
    Duration? receiveTimeout,
  }) async {
    if (_closed) throw StateError('ApiClient is closed.');
    final isMultipart = body is FormData;
    _validateApiPath(path);
    final requestUri = Uri.parse('${configuration.canonicalApiOrigin}/')
        .resolve(path);
    if (!_sameOrigin(requestUri, Uri.parse(configuration.canonicalApiOrigin))) {
      throw ArgumentError.value(
        path,
        'path',
        'API request must remain on the configured origin.',
      );
    }
    try {
      final response = await _dio.request<dynamic>(
        path,
        data: body,
        queryParameters: queryParameters,
        options: Options(
          method: method,
          receiveTimeout: receiveTimeout,
          headers: {
            'Cache-Control': 'no-store',
            if (accessToken != null) 'Authorization': 'Bearer $accessToken',
            if (body != null && !isMultipart)
              'Content-Type': 'application/json',
            ...?headers,
          },
          contentType: body == null || isMultipart
              ? null
              : Headers.jsonContentType,
          followRedirects: false,
          maxRedirects: 0,
        ),
      );
      final status = response.statusCode ?? 0;
      if (status >= 300 && status < 400) {
        throw const ApiException(
          statusCode: null,
          code: 'unsafe_redirect',
          message: 'Die API hat eine Weiterleitung zurückgegeben; sie wurde blockiert.',
        );
      }
      return response;
    } on DioException catch (error) {
      throw ApiException(
        statusCode: error.response?.statusCode,
        code: 'network_error',
        message: 'Die API ist derzeit nicht erreichbar.',
      );
    }
  }

  void _throwForStatus(Response<dynamic> response, {bool allow401 = false}) {
    final status = response.statusCode ?? 0;
    if (status >= 400 && !(allow401 && status == 401)) {
      final problem = _problemFromResponse(response.data);
      throw ApiException(
        statusCode: status,
        code: problem.code ?? 'http_$status',
        message: problem.message,
        errors: problem.errors,
      );
    }
  }
}

class ApiSessionCheckpoint {
  const ApiSessionCheckpoint({required this.userId, required this.email});

  final String userId;
  final String email;
}

Map<String, dynamic> _asObject(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is String) return decodeJsonObject(value);
  throw const FormatException('Expected a JSON object from the API.');
}

ApiProblem _problemFromResponse(Object? value) {
  try {
    return ApiProblem.fromJson(_asObject(value));
  } on FormatException {
    return const ApiProblem();
  }
}

void _validateApiPath(String path) {
  final uri = Uri.tryParse(path);
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      !path.startsWith('/api/v1/') ||
      path.startsWith('//') ||
      uri.fragment.isNotEmpty) {
    throw ArgumentError.value(
      path,
      'path',
      'Only relative versioned API routes are allowed.',
    );
  }
}

void _validateIdentifier(String value, String name) {
  if (!RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value)) {
    throw ArgumentError.value(value, name, 'Expected a UUID.');
  }
}

void _validateOrigin(Uri origin, {required bool allowLoopbackHttp}) {
  if (!origin.isAbsolute ||
      origin.userInfo.isNotEmpty ||
      origin.host.isEmpty ||
      (origin.path.isNotEmpty && origin.path != '/') ||
      origin.hasQuery ||
      origin.hasFragment) {
    throw ArgumentError.value(
      origin,
      'origin',
      'Expected an origin without credentials or path.',
    );
  }
  if (origin.scheme == 'https') return;
  final loopback =
      origin.scheme == 'http' &&
      allowLoopbackHttp &&
      (origin.host == 'localhost' ||
          origin.host == '127.0.0.1' ||
          origin.host == '::1');
  if (!loopback) {
    throw ArgumentError.value(
      origin,
      'origin',
      'The API requires HTTPS outside loopback development.',
    );
  }
}

String _canonicalOrigin(Uri origin) => Uri(
  scheme: origin.scheme.toLowerCase(),
  host: origin.host.toLowerCase(),
  port: origin.hasPort ? origin.port : null,
).origin;

bool _sameOrigin(Uri first, Uri second) =>
    first.scheme.toLowerCase() == second.scheme.toLowerCase() &&
    first.host.toLowerCase() == second.host.toLowerCase() &&
    first.port == second.port;

class _ApiOriginGuard extends Interceptor {
  _ApiOriginGuard(this.configuration);

  final ApiConfiguration configuration;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!_sameOrigin(options.uri, configuration.apiOrigin) ||
        !options.uri.path.startsWith('/api/v1/') ||
        options.uri.hasFragment) {
      handler.reject(
        DioException(
          requestOptions: options,
          error: const FormatException(
            'Request escaped the configured API origin.',
          ),
        ),
      );
      return;
    }
    handler.next(options);
  }
}

String _dateOnly(DateTime value) {
  final date = value.toUtc();
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}
