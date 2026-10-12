import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';
import 'package:gainer_mobile/data/services/api/api_session_service.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';

void main() {
  group('ApiClient', () {
    test(
      'runs login, session restore, protected mutation, and logout with CSRF',
      () async {
        final requests = <String>[];
        var antiforgeryRequest = 0;
        final server = await _TestApiServer.start((request) async {
          requests.add('${request.method} ${request.uri.path}');
          expect(request.headers.value('origin'), 'https://app.gainer.example');

          if (request.uri.path == '/api/v1/auth/antiforgery') {
            antiforgeryRequest++;
            request.response.headers.add(
              HttpHeaders.setCookieHeader,
              'gainer.csrf=$antiforgeryRequest; Path=/; HttpOnly; SameSite=Lax',
            );
            return _json(request, {
              'requestToken': 'request-token-$antiforgeryRequest',
            });
          }

          if (request.uri.path == '/api/v1/auth/login') {
            expect(request.headers.value('x-csrf-token'), 'request-token-1');
            expect(request.headers.value('cookie'), contains('gainer.csrf=1'));
            final body = jsonDecode(
              await utf8.decoder.bind(request).join(),
            ) as Map<String, dynamic>;
            expect(body, {
              'email': 'member@example.test',
              'password': 'secret-never-store',
            });
            request.response.headers.add(
              HttpHeaders.setCookieHeader,
              'gainer.session=opaque-session; Path=/; HttpOnly; SameSite=Lax',
            );
            request.response.statusCode = HttpStatus.noContent;
            return request.response.close();
          }

          if (request.uri.path == '/api/v1/auth/session') {
            expect(
              request.headers.value('cookie'),
              contains('gainer.session=opaque-session'),
            );
            return _json(request, {
              'userId': '11111111-1111-4111-8111-111111111111',
              'email': 'member@example.test',
              'isAccountOperator': false,
            });
          }

          if (request.uri.path.endsWith('/status') && request.method == 'PUT') {
            expect(request.headers.value('x-csrf-token'), 'request-token-2');
            expect(request.headers.value('cookie'), contains('gainer.csrf=2'));
            expect(
              request.headers.value('cookie'),
              contains('gainer.session=opaque-session'),
            );
            expect(jsonDecode(await utf8.decoder.bind(request).join()), {
              'isActive': false,
            });
            request.response.statusCode = HttpStatus.noContent;
            return request.response.close();
          }

          if (request.uri.path == '/api/v1/auth/logout') {
            expect(request.headers.value('x-csrf-token'), 'request-token-3');
            expect(
              request.headers.value('cookie'),
              contains('gainer.session=opaque-session'),
            );
            request.response.headers.add(
              HttpHeaders.setCookieHeader,
              'gainer.session=; Path=/; Max-Age=0; HttpOnly',
            );
            request.response.statusCode = HttpStatus.noContent;
            return request.response.close();
          }

          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        });
        final secureStorage = _MemorySecureSession();
        final api = ApiClient(
          configuration: ApiConfiguration(
            apiOrigin: server.origin,
            trustedFrontendOrigin: Uri.parse('https://app.gainer.example'),
            allowInsecureLoopbackForDevelopment: true,
          ),
        );
        final sessions = ApiSessionService(
          api: api,
          secureStorage: secureStorage,
        );

        try {
          final signedIn = await sessions.login(
            'member@example.test',
            'secret-never-store',
          );
          expect(signedIn.email, 'member@example.test');
          expect(secureStorage.checkpoint, isNotNull);
          final checkpointText = utf8.decode(secureStorage.checkpoint!);
          expect(checkpointText, isNot(contains('secret-never-store')));
          expect(checkpointText, isNot(contains('request-token-')));

          await api.clearCookies();
          final restored = await sessions.restore();
          expect(restored?.userId, signedIn.userId);
          await api.setAccountStatus(
            '22222222-2222-4222-8222-222222222222',
            false,
          );
          await sessions.logout();

          expect(secureStorage.checkpoint, isNull);
          expect(requests, [
            'GET /api/v1/auth/antiforgery',
            'POST /api/v1/auth/login',
            'GET /api/v1/auth/session',
            'GET /api/v1/auth/session',
            'GET /api/v1/auth/antiforgery',
            'PUT /api/v1/account-operator/accounts/22222222-2222-4222-8222-222222222222/status',
            'GET /api/v1/auth/antiforgery',
            'POST /api/v1/auth/logout',
          ]);
        } finally {
          api.close();
          await server.close();
        }
      },
    );

    test(
      'blocks redirects and rejects non-API or cross-origin paths',
      () async {
        var requests = 0;
        final server = await _TestApiServer.start((request) async {
          requests++;
          request.response.statusCode = HttpStatus.found;
          request.response.headers.set(
            HttpHeaders.locationHeader,
            'https://other.example/api/v1/auth/session',
          );
          await request.response.close();
        });
        final api = ApiClient(
          configuration: ApiConfiguration(
            apiOrigin: server.origin,
            trustedFrontendOrigin: Uri.parse('https://app.gainer.example'),
            allowInsecureLoopbackForDevelopment: true,
          ),
        );
        try {
          await expectLater(
            api.getSession(),
            throwsA(
              isA<ApiException>().having(
                (error) => error.code,
                'code',
                'unsafe_redirect',
              ),
            ),
          );
          expect(requests, 1);
        } finally {
          api.close();
          await server.close();
        }
      },
    );

    test(
      'secure session checkpoints are bound to the configured API origin',
      () async {
        final server = await _TestApiServer.start((request) async {
          await request.response.close();
        });
        final api = ApiClient(
          configuration: ApiConfiguration(
            apiOrigin: server.origin,
            trustedFrontendOrigin: Uri.parse('https://app.gainer.example'),
            allowInsecureLoopbackForDevelopment: true,
          ),
        );
        final bytes = Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'schemaVersion': 1,
              'apiOrigin': 'https://different.example',
              'userId': '11111111-1111-4111-8111-111111111111',
              'email': 'member@example.test',
              'cookies': [],
            }),
          ),
        );
        try {
          await expectLater(
            api.restoreSecureCheckpoint(bytes),
            throwsA(isA<FormatException>()),
          );
        } finally {
          api.close();
          await server.close();
        }
      },
    );

    test('only HTTPS origins or loopback HTTP origins are accepted', () {
      expect(
        () => ApiConfiguration(
          apiOrigin: Uri.parse('http://api.example.test'),
          trustedFrontendOrigin: Uri.parse('https://app.example.test'),
        ),
        throwsArgumentError,
      );
      expect(
        () => ApiConfiguration(
          apiOrigin: Uri.parse('https://user:password@api.example.test'),
          trustedFrontendOrigin: Uri.parse('https://app.example.test'),
        ),
        throwsArgumentError,
      );
    });
  });
}

Future<void> _json(HttpRequest request, Map<String, Object?> body) async {
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(body));
  await request.response.close();
}

class _TestApiServer {
  _TestApiServer(this.server, this.subscription);

  final HttpServer server;
  final StreamSubscription<HttpRequest> subscription;

  Uri get origin =>
      Uri(scheme: 'http', host: server.address.address, port: server.port);

  static Future<_TestApiServer> start(
    Future<void> Function(HttpRequest request) handle,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) {
      unawaited(handle(request));
    });
    return _TestApiServer(server, subscription);
  }

  Future<void> close() async {
    await subscription.cancel();
    await server.close(force: true);
  }
}

class _MemorySecureSession implements SecureSessionPlatform {
  Uint8List? checkpoint;

  @override
  Future<void> clearCheckpoint(String apiOrigin) async => checkpoint = null;

  @override
  Future<Uint8List?> readCheckpoint(String apiOrigin) async => checkpoint;

  @override
  Future<void> writeCheckpoint(String apiOrigin, Uint8List checkpoint) async {
    this.checkpoint = Uint8List.fromList(checkpoint);
  }
}
