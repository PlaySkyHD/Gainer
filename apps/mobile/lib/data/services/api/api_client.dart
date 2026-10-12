import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import '../../models/api/api_models.dart';
import '../../models/api/sync_api_models.dart';

const csrfHeaderName = 'X-CSRF-TOKEN';
const syncProtocolVersion = 2;

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
  });

  final int? statusCode;
  final String code;
  final String message;

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
    SyncClientRegistrationRequest request,
  ) async {
    _validateIdentifier(request.clientId, 'clientId');
    final response = await _mutate(
      'PUT',
      '/api/v1/sync/clients/${request.clientId}',
      body: request.toJson(),
    );
    return SyncClientRegistrationResponse.fromJson(_asObject(response.data));
  }

  Future<SyncMutationResponse> pushMutation({
    required String mutationId,
    required SyncMutationRequest mutation,
  }) async {
    _validateIdentifier(mutationId, 'mutationId');
    final response = await _mutate(
      'PUT',
      '/api/v1/sync/mutations/$mutationId',
      body: mutation.toJson(),
    );
    return SyncMutationResponse.fromJson(_asObject(response.data));
  }

  Future<SyncPullResponse> pullChanges({
    required int after,
    int limit = 200,
  }) async {
    if (after < 0 || limit < 1 || limit > 200) {
      throw ArgumentError(
        'Sync cursor and limit are outside the API contract.',
      );
    }
    final response = await _request(
      'GET',
      '/api/v1/sync/changes',
      queryParameters: {'after': after, 'limit': limit},
    );
    return SyncPullResponse.fromJson(_asObject(response.data));
  }

  /// Calls the planned handover endpoint. The server contract is not deployed yet.
  Future<BeginSyncHandoverResponse> beginSyncHandover(
    BeginSyncHandoverRequest request,
  ) async {
    final response = await _mutate(
      'POST',
      '/api/v1/sync/handovers',
      body: request.toJson(),
    );
    return BeginSyncHandoverResponse.fromJson(_asObject(response.data));
  }

  /// Calls the planned handover endpoint. The server contract is not deployed yet.
  Future<CompleteSyncHandoverResponse> completeSyncHandover({
    required String handoverId,
    required CompleteSyncHandoverRequest request,
  }) async {
    _validateIdentifier(handoverId, 'handoverId');
    final response = await _mutate(
      'POST',
      '/api/v1/sync/handovers/$handoverId/complete',
      body: request.toJson(),
    );
    return CompleteSyncHandoverResponse.fromJson(_asObject(response.data));
  }

  /// Calls the planned handover endpoint. The server contract is not deployed yet.
  Future<void> cancelSyncHandover({
    required String handoverId,
    required CancelSyncHandoverRequest request,
  }) async {
    _validateIdentifier(handoverId, 'handoverId');
    await _mutate(
      'POST',
      '/api/v1/sync/handovers/$handoverId/cancel',
      body: request.toJson(),
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
  }) async {
    final token = await _fetchAntiforgeryToken();
    return _request(method, path, body: body, headers: {csrfHeaderName: token});
  }

  Future<String> _fetchAntiforgeryToken() async {
    final response = await _request('GET', '/api/v1/auth/antiforgery');
    return ApiAntiforgeryToken.fromJson(_asObject(response.data)).requestToken;
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
            if (body != null) 'Content-Type': 'application/json',
            ...?headers,
          },
          contentType: body == null ? null : Headers.jsonContentType,
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
