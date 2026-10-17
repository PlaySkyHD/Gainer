import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import '../../models/api/api_models.dart';
import '../../models/api/sync_api_models.dart';

const csrfHeaderName = 'X-CSRF-TOKEN';
const accountIdentityHeaderName = 'X-Gainer-Account-Id';
const syncProtocolVersion = 3;

class ApiConfiguration {
  ApiConfiguration({
    required this.apiOrigin,
    required this.trustedFrontendOrigin,
    this.allowInsecureLoopbackForDevelopment = false,
  }) {
    _validateOrigin(
      apiOrigin,
      allowLoopbackHttp: allowInsecureLoopbackForDevelopment,
    );
    _validateOrigin(
      trustedFrontendOrigin,
      allowLoopbackHttp: allowInsecureLoopbackForDevelopment,
    );
  }

  final Uri apiOrigin;
  final Uri trustedFrontendOrigin;
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

/// Cookie/Origin/Antiforgery transport for the existing Gainer API.
/// Redirects are rejected so cookies and request data cannot follow another host.
class ApiClient {
  ApiClient({required this.configuration, CookieJar? cookieJar})
    : cookieJar = cookieJar ?? CookieJar(),
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
    _dio.interceptors
      ..add(_ApiOriginGuard(configuration))
      ..add(CookieManager(this.cookieJar));
  }

  final ApiConfiguration configuration;
  final Dio _dio;
  final CookieJar cookieJar;
  bool _closed = false;

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

  Future<ApiFoodProduct> lookupFoodByBarcode(String barcode) async {
    if (!RegExp(r'^\d{4,32}$').hasMatch(barcode)) {
      throw ArgumentError.value(barcode, 'barcode', 'Expected 4 to 32 digits.');
    }
    final response = await _request('GET', '/api/v1/foods/barcode/$barcode');
    return ApiFoodProduct.fromJson(_asObject(response.data));
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
    );
    return ApiMealEstimateResponse.fromJson(_asObject(response.data));
  }

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

  Future<void> login(ApiLoginRequest request) async {
    await _mutate('POST', '/api/v1/auth/login', body: request.toJson());
  }

  Future<void> logout() async {
    await _mutate('POST', '/api/v1/auth/logout');
  }

  Future<void> acceptInvitation(ApiAcceptInvitationRequest request) async {
    await _mutate(
      'POST',
      '/api/v1/auth/invitations/accept',
      body: request.toJson(),
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

  Future<Uint8List> createSecureCheckpoint(ApiSession session) async {
    final cookies = await cookieJar.loadForRequest(configuration.apiOrigin);
    if (cookies.isEmpty) {
      throw StateError('No API session cookie is available.');
    }
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'schemaVersion': 1,
          'apiOrigin': configuration.canonicalApiOrigin,
          'userId': session.userId,
          'email': session.email,
          'cookies': cookies
              .map(_serializeSessionCookie)
              .toList(growable: false),
        }),
      ),
    );
  }

  Future<ApiSessionCheckpoint> restoreSecureCheckpoint(Uint8List bytes) async {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic> || decoded['schemaVersion'] != 1) {
      throw const FormatException('Unsupported secure session checkpoint.');
    }
    if (decoded['apiOrigin'] != configuration.canonicalApiOrigin) {
      throw const FormatException(
        'Session checkpoint belongs to another API host.',
      );
    }
    final userId = decoded['userId'];
    final email = decoded['email'];
    final serializedCookies = decoded['cookies'];
    if (userId is! String || email is! String || serializedCookies is! List) {
      throw const FormatException('Invalid secure session checkpoint.');
    }
    final cookies = serializedCookies.map(_restoreSessionCookie).toList();
    if (cookies.isEmpty ||
        (configuration.apiOrigin.scheme == 'https' &&
            cookies.any((cookie) => !cookie.secure))) {
      throw const FormatException('Checkpoint contains an invalid API cookie.');
    }
    await clearCookies();
    await cookieJar.saveFromResponse(configuration.apiOrigin, cookies);
    return ApiSessionCheckpoint(userId: userId, email: email);
  }

  Future<void> clearCookies() => cookieJar.deleteAll();

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
  }) async {
    if (expectedAccountId != null) {
      _validateIdentifier(expectedAccountId, 'expectedAccountId');
    }
    final token = await _fetchAntiforgeryToken(
      expectedAccountId: expectedAccountId,
    );
    final headers = <String, String>{csrfHeaderName: token};
    if (expectedAccountId case final accountId?) {
      headers[accountIdentityHeaderName] = accountId;
    }
    return _request(method, path, body: body, headers: headers);
  }

  Future<String> _fetchAntiforgeryToken({String? expectedAccountId}) async {
    final response = await _request('GET', '/api/v1/auth/antiforgery');
    final token = ApiAntiforgeryToken.fromJson(_asObject(response.data));
    if (expectedAccountId != null && token.authenticatedUserId == null) {
      throw const ApiException(
        statusCode: 426,
        code: 'api_upgrade_required',
        message: 'Die Kontoidentität der API-Sitzung konnte nicht bestätigt werden. Bitte aktualisiere die App und melde dich erneut an.',
      );
    }
    if (expectedAccountId != null &&
        token.authenticatedUserId!.toLowerCase() !=
            expectedAccountId.toLowerCase()) {
      throw const ApiException(
        statusCode: 409,
        code: 'account_changed',
        message: 'Das angemeldete Konto hat sich geändert. Deine lokalen Änderungen bleiben erhalten; melde dich mit dem passenden Konto an.',
      );
    }
    return token.requestToken;
  }

  Future<Response<dynamic>> _request(
    String method,
    String path, {
    Object? body,
    Map<String, Object?>? queryParameters,
    Map<String, String>? headers,
    bool allow401 = false,
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
          headers: {
            'Origin': configuration.trustedFrontendOrigin.origin,
            'Cache-Control': 'no-store',
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
      if (status >= 400 && !(allow401 && status == 401)) {
        final problem = _problemFromResponse(response.data);
        throw ApiException(
          statusCode: status,
          code: problem.code ?? 'http_$status',
          message: problem.message,
          errors: problem.errors,
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

  Map<String, dynamic> _serializeSessionCookie(Cookie cookie) {
    final domain = cookie.domain;
    if (domain != null &&
        !_domainMatches(domain, configuration.apiOrigin.host)) {
      throw StateError('Refusing to checkpoint a cookie for another host.');
    }
    return {
      'name': cookie.name,
      'value': cookie.value,
      'path': cookie.path,
      'secure': cookie.secure,
      'httpOnly': cookie.httpOnly,
      if (cookie.expires != null)
        'expiresAtUtc': cookie.expires!.toUtc().toIso8601String(),
      if (cookie.maxAge != null) 'maxAge': cookie.maxAge,
    };
  }

  Cookie _restoreSessionCookie(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['name'] is! String ||
        value['value'] is! String ||
        value['path'] is! String ||
        value['secure'] is! bool ||
        value['httpOnly'] is! bool) {
      throw const FormatException('Invalid cookie in secure checkpoint.');
    }
    final cookie = Cookie(value['name'] as String, value['value'] as String)
      ..path = value['path'] as String
      ..secure = value['secure'] as bool
      ..httpOnly = value['httpOnly'] as bool
      ..domain = configuration.apiOrigin.host;
    final expires = value['expiresAtUtc'];
    if (expires is String) cookie.expires = DateTime.parse(expires).toUtc();
    final maxAge = value['maxAge'];
    if (maxAge is int) cookie.maxAge = maxAge;
    return cookie;
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

bool _domainMatches(String cookieDomain, String host) {
  final normalized = cookieDomain.toLowerCase().replaceFirst(
    RegExp(r'^\.'),
    '',
  );
  return host.toLowerCase() == normalized ||
      host.toLowerCase().endsWith('.$normalized');
}

String _dateOnly(DateTime value) {
  final date = value.toUtc();
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}
