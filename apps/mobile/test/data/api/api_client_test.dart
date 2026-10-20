import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/api/api_models.dart';
import 'package:gainer_mobile/data/models/api/sync_api_models.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';
import 'package:gainer_mobile/data/services/api/api_session_service.dart';
import 'package:gainer_mobile/data/services/platform/generated/mobile_platform_api.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';

void main() {
  group('ApiClient', () {
    test('loads server-computed progress insights and submits read-only coach questions', () async {
      final requests = <String>[];
      final server = await _TestApiServer.start((request) async {
        requests.add('${request.method} ${request.uri.path}');
        if (request.uri.path == '/api/v1/insights/dashboard') {
          return _json(request, {
            'asOfRevision': 12,
            'from': '2026-09-12',
            'through': '2026-10-12',
            'activeGoal': null,
            'latestWeight': {'date': '2026-10-10', 'weightKg': 75.5},
            'weightSeries': [
              {'date': '2026-10-10', 'weightKg': 75.5},
            ],
            'sevenDayWeight': {
              'averageAlgorithmVersion': 'a1',
              'trendAlgorithmVersion': 't1',
              'unit': 'kg',
              'from': '2026-10-05',
              'through': '2026-10-12',
              'expectedDays': 7,
              'observedDays': 1,
              'coverage': 0.14,
              'averageKg': 75.5,
              'trendKgPerWeek': null,
            },
            'weight': {
              'averageAlgorithmVersion': 'a1',
              'trendAlgorithmVersion': 't1',
              'unit': 'kg',
              'from': '2026-09-12',
              'through': '2026-10-12',
              'expectedDays': 30,
              'observedDays': 1,
              'coverage': 0.03,
              'averageKg': 75.5,
              'trendKgPerWeek': null,
            },
            'nutrition': {
              'algorithmVersion': 'n1',
              'expectedDays': 30,
              'observedDays': 1,
              'coverage': 0.03,
              'mealDiaryDays': 1,
              'legacyCheckInDays': 0,
              'caloriesKcal': {'value': 2100, 'observedDays': 1},
              'proteinGrams': {'value': 120, 'observedDays': 1},
              'carbohydrateGrams': {'value': null, 'observedDays': 0},
              'fatGrams': {'value': null, 'observedDays': 0},
            },
            'training': {
              'volumeAlgorithmVersion': 'v1',
              'estimatedOneRepMaxAlgorithmVersion': 'e1',
              'volumeUnit': 'kg-repetitions',
              'workoutCount': 2,
              'volumeKgRepetitions': 4200,
              'bestSet': null,
              'bodyweightMissing': false,
            },
            'workoutsLast7Days': 2,
          });
        }
        if (request.uri.path == '/api/v1/coach/responses') {
          final body = jsonDecode(
            await utf8.decoder.bind(request).join(),
          ) as Map<String, dynamic>;
          expect(body, {'question': 'How consistent was my training?'});
          return _json(request, {
            'summary': 'You completed two workouts.',
            'observations': [
              {
                'text': 'Training was recorded on two days.',
                'factIds': ['workout-count'],
              },
            ],
            'facts': [],
            'dataGaps': [],
            'suggestions': ['Continue your routine.'],
            'asOfRevision': 12,
          });
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });
      final api = ApiClient(
        configuration: ApiConfiguration(
          apiOrigin: server.origin,
          allowInsecureLoopbackForDevelopment: true,
        ),
      );
      try {
        final dashboard = await api.getDashboardInsights(days: 30);
        final answer = await api.askCoach('How consistent was my training?');
        expect(dashboard.training.workoutCount, 2);
        expect(dashboard.nutrition.caloriesKcal.value, 2100);
        expect(answer.observations, ['Training was recorded on two days.']);
        expect(answer.suggestions, ['Continue your routine.']);
        expect(requests, contains('GET /api/v1/insights/dashboard'));
      } finally {
        api.close();
        await server.close();
      }
    });

    test('uses the existing exercise and food catalog contracts', () async {
      final requests = <String>[];
      final server = await _TestApiServer.start((request) async {
        requests.add(
          '${request.method} ${request.uri.path}?${request.uri.query}',
        );
        if (request.uri.path == '/api/v1/exercises') {
          return _json(request, {
            'items': [
              {
                'id': 'exercise-1',
                'name': 'Squat',
                'description': null,
                'targetMuscle': 'Quadriceps',
                'muscleGroup': 'Legs',
                'equipment': 'Barbell',
                'isCustom': false,
                'catalogVersion': '2026.08.1',
                'version': 3,
                'exerciseType': 'strength',
                'notes': null,
                'bodyweightFactor': null,
                'weightFactor': null,
                'categoryIds': [],
              },
            ],
            'offset': 0,
            'limit': 100,
            'total': 1,
            'categories': [
              {'id': 'category-1', 'name': 'Beine', 'isBase': true},
            ],
          });
        }
        if (request.uri.path == '/api/v1/foods/search') {
          return _json(request, {'products': [], 'page': 2, 'hasMore': true});
        }
        if (request.uri.path == '/api/v1/foods/barcode/12345678') {
          return _json(request, {
            'barcode': '12345678',
            'productName': 'Oats',
            'brand': null,
            'basisGrams': 100,
            'kilocaloriesPer100Grams': 372,
            'proteinGramsPer100Grams': 13,
            'carbohydrateGramsPer100Grams': 58,
            'fatGramsPer100Grams': 7,
            'qualityIndicators': [],
            'retrievedAtUtc': '2026-10-12T10:00:00Z',
            'isStale': false,
            'source': 'catalog',
          });
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });
      final api = ApiClient(
        configuration: ApiConfiguration(
          apiOrigin: server.origin,
          allowInsecureLoopbackForDevelopment: true,
        ),
      );
      try {
        final exercises = await api.getExercises(targetMuscle: 'Quadriceps');
        final foods = await api.searchFoods(query: 'oats', page: 2);
        final food = await api.lookupFoodByBarcode('12345678');
        expect(exercises.items.single.catalogVersion, '2026.08.1');
        expect(exercises.items.single.version, 3);
        expect(foods.page, 2);
        expect(foods.hasMore, isTrue);
        expect(food.productName, 'Oats');
        expect(
          requests,
          contains(
            'GET /api/v1/exercises?offset=0&limit=100&targetMuscle=Quadriceps',
          ),
        );
        expect(
          requests,
          contains('GET /api/v1/foods/search?query=oats&page=2&pageSize=10'),
        );
      } finally {
        api.close();
        await server.close();
      }
    });

    test(
      'uploads nutrition estimate and label scan as consented multipart drafts',
      () async {
        final uploadPaths = <String>[];
        final server = await _TestApiServer.start((request) async {
          if (request.uri.path.endsWith('/meal-estimates') ||
              request.uri.path.endsWith('/label-scans')) {
            final contentType = request.headers.contentType;
            expect(contentType?.mimeType, 'multipart/form-data');
            expect(contentType?.parameters['boundary'], isNotEmpty);
            final body = await utf8.decoder.bind(request).join();
            expect(body, contains('image/jpeg'));
            uploadPaths.add(request.uri.path);
            if (request.uri.path.endsWith('/meal-estimates')) {
              expect(body, contains('name="imageConsent"'));
              expect(body, contains('true'));
              return _json(request, {
                'components': [],
                'provider': 'estimate-provider',
                'schemaVersion': '1',
                'estimatedAtUtc': '2026-10-12T10:00:00Z',
              });
            }
            return _json(request, {
              'basis': 'Per100Grams',
              'servingMassGrams': null,
              'kilocalories': {
                'originalValue': 100,
                'per100Grams': 100,
                'status': 'Confirmed',
                'evidence': null,
              },
              'proteinGrams': {
                'originalValue': 5,
                'per100Grams': 5,
                'status': 'Confirmed',
                'evidence': null,
              },
              'carbohydrateGrams': {
                'originalValue': 20,
                'per100Grams': 20,
                'status': 'Confirmed',
                'evidence': null,
              },
              'fatGrams': {
                'originalValue': 2,
                'per100Grams': 2,
                'status': 'Confirmed',
                'evidence': null,
              },
              'canConfirm': true,
              'provider': 'scanner',
              'providerModelVersion': 'model-1',
              'parserVersion': 'parser-1',
              'scannedAtUtc': '2026-10-12T10:00:00Z',
            });
          }
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        });
        final api = ApiClient(
          configuration: ApiConfiguration(
            apiOrigin: server.origin,
            allowInsecureLoopbackForDevelopment: true,
          ),
        );
        try {
          final bytes = Uint8List.fromList([1, 2, 3]);
          final estimate = await api.estimateMeal(
            text: 'Oats',
            imageBytes: bytes,
            imageContentType: 'image/jpeg',
            imageConsent: true,
          );
          final scan = await api.scanNutritionLabel(
            imageBytes: bytes,
            imageContentType: 'image/jpeg',
          );
          expect(estimate.provider, 'estimate-provider');
          expect(scan.canConfirm, isTrue);
          expect(uploadPaths, [
            '/api/v1/nutrition/meal-estimates',
            '/api/v1/nutrition/label-scans',
          ]);
          await expectLater(
            api.estimateMeal(imageBytes: bytes, imageContentType: 'image/jpeg'),
            throwsArgumentError,
          );
        } finally {
          api.close();
          await server.close();
        }
      },
    );

    test('runs login, restore by refresh, protected mutation, and logout with bearer tokens', () async {
      final requests = <String>[];
      final server = await _TestApiServer.start((request) async {
        requests.add('${request.method} ${request.uri.path}');
        expect(request.headers.value('origin'), isNull);
        expect(request.headers.value('cookie'), isNull);
        expect(request.headers.value('x-csrf-token'), isNull);

        if (request.uri.path == '/api/v1/auth/login') {
          expect(request.headers.value('authorization'), isNull);
          final body = jsonDecode(
            await utf8.decoder.bind(request).join(),
          ) as Map<String, dynamic>;
          expect(body, {
            'email': 'member@example.test',
            'password': 'secret-never-store',
            'deviceName': 'Gainer iPhone',
          });
          return _json(request, _tokens(1));
        }

        if (request.uri.path == '/api/v1/auth/refresh') {
          expect(request.headers.value('authorization'), isNull);
          expect(jsonDecode(await utf8.decoder.bind(request).join()), {
            'refreshToken': 'refresh-1',
          });
          return _json(request, _tokens(2));
        }

        if (request.uri.path == '/api/v1/auth/session') {
          final authorization = request.headers.value('authorization');
          expect(authorization, anyOf('Bearer access-1', 'Bearer access-2'));
          return _json(request, {
            'userId': '11111111-1111-4111-8111-111111111111',
            'email': 'member@example.test',
            'isAccountOperator': false,
          });
        }

        if (request.uri.path.endsWith('/status') && request.method == 'PUT') {
          expect(request.headers.value('authorization'), 'Bearer access-2');
          expect(jsonDecode(await utf8.decoder.bind(request).join()), {
            'isActive': false,
          });
          request.response.statusCode = HttpStatus.noContent;
          return request.response.close();
        }

        if (request.uri.path == '/api/v1/auth/logout') {
          expect(request.headers.value('authorization'), 'Bearer access-2');
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
        final checkpointText = utf8.decode(secureStorage.checkpoint!);
        expect(checkpointText, contains('"schemaVersion":2'));
        expect(checkpointText, contains('refresh-1'));
        expect(checkpointText, isNot(contains('secret-never-store')));
        expect(checkpointText, isNot(contains('access-1')));

        // A restart keeps only the refresh token; the first request renews.
        api.clearTokens();
        final restored = await sessions.restore();
        expect(restored?.userId, signedIn.userId);
        final rotatedText = utf8.decode(secureStorage.checkpoint!);
        expect(rotatedText, contains('refresh-2'));
        expect(rotatedText, isNot(contains('refresh-1')));

        await api.setAccountStatus(
          '22222222-2222-4222-8222-222222222222',
          false,
        );
        await sessions.logout();

        expect(secureStorage.checkpoint, isNull);
        expect(api.hasDeviceSession, isFalse);
        expect(requests, [
          'POST /api/v1/auth/login',
          'GET /api/v1/auth/session',
          'POST /api/v1/auth/refresh',
          'GET /api/v1/auth/session',
          'PUT /api/v1/account-operator/accounts/22222222-2222-4222-8222-222222222222/status',
          'POST /api/v1/auth/logout',
        ]);
      } finally {
        api.close();
        await server.close();
      }
    });

    test('passkey sign-in stores the device session and a cancelled sheet sends nothing', () async {
      final requests = <String>[];
      final server = await _TestApiServer.start((request) async {
        requests.add('${request.method} ${request.uri.path}');
        expect(
          request.headers.value('authorization'),
          anyOf(isNull, 'Bearer access-1'),
        );
        if (request.uri.path == '/api/v1/auth/passkeys/request-options') {
          return _json(request, {
            'optionsJson': jsonEncode({
              'challenge': 'AQID',
              'rpId': 'gainer.markfort.xyz',
            }),
            'state': 'opaque-state',
          });
        }
        if (request.uri.path == '/api/v1/auth/passkeys/login') {
          final body = jsonDecode(
            await utf8.decoder.bind(request).join(),
          ) as Map<String, dynamic>;
          expect(body['state'], 'opaque-state');
          expect(body['deviceName'], 'Gainer iPhone');
          final credential = jsonDecode(
            body['credentialJson'] as String,
          ) as Map<String, dynamic>;
          expect(credential['type'], 'public-key');
          expect(
            (credential['response'] as Map<String, dynamic>)['signature'],
            'BA',
          );
          return _json(request, _tokens(1));
        }
        if (request.uri.path == '/api/v1/auth/session') {
          return _json(request, {
            'userId': '11111111-1111-4111-8111-111111111111',
            'email': 'member@example.test',
            'isAccountOperator': false,
          });
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });
      final secureStorage = _MemorySecureSession();
      final api = ApiClient(
        configuration: ApiConfiguration(
          apiOrigin: server.origin,
          allowInsecureLoopbackForDevelopment: true,
        ),
      );
      final sessions = ApiSessionService(
        api: api,
        secureStorage: secureStorage,
      );
      final passkeys = _ScriptedPasskeys();
      try {
        passkeys.cancel = true;
        expect(await sessions.loginWithPasskey(passkeys), isNull);
        expect(requests, ['POST /api/v1/auth/passkeys/request-options']);
        expect(secureStorage.checkpoint, isNull);

        passkeys.cancel = false;
        final session = await sessions.loginWithPasskey(passkeys);
        expect(session?.email, 'member@example.test');
        expect(passkeys.challenges.single, [1, 2, 3]);
        expect(utf8.decode(secureStorage.checkpoint!), contains('refresh-1'));
        expect(requests.skip(1), [
          'POST /api/v1/auth/passkeys/request-options',
          'POST /api/v1/auth/passkeys/login',
          'GET /api/v1/auth/session',
        ]);
      } finally {
        api.close();
        await server.close();
      }
    });

    test('manages passkeys of the signed-in account', () async {
      final requests = <String>[];
      final server = await _TestApiServer.start((request) async {
        requests.add('${request.method} ${request.uri.path}');
        if (request.uri.path == '/api/v1/auth/login') {
          return _json(request, _tokens(1));
        }
        expect(request.headers.value('authorization'), 'Bearer access-1');
        if (request.uri.path == '/api/v1/auth/passkeys/creation-options') {
          return _json(request, {'optionsJson': '{}', 'state': 'create-state'});
        }
        if (request.uri.path == '/api/v1/auth/passkeys' &&
            request.method == 'POST') {
          expect(jsonDecode(await utf8.decoder.bind(request).join()), {
            'credentialJson': '{"id":"x"}',
            'state': 'create-state',
            'name': 'Gainer iPhone',
          });
          request.response.statusCode = HttpStatus.created;
          return _json(request, {
            'id': 'AQ',
            'name': 'Gainer iPhone',
            'createdAt': '2026-10-20T12:00:00+00:00',
          });
        }
        if (request.uri.path == '/api/v1/auth/passkeys') {
          return _jsonList(request, [
            {
              'id': 'AQ',
              'name': 'Gainer iPhone',
              'createdAt': '2026-10-20T12:00:00+00:00',
            },
          ]);
        }
        if (request.method == 'DELETE') {
          request.response.statusCode = HttpStatus.noContent;
          return request.response.close();
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });
      final api = ApiClient(
        configuration: ApiConfiguration(
          apiOrigin: server.origin,
          allowInsecureLoopbackForDevelopment: true,
        ),
      );
      try {
        await api.login(
          const ApiLoginRequest(email: 'member@example.test', password: 'pw'),
        );
        final options = await api.passkeyCreationOptions();
        final created = await api.registerPasskey(
          credentialJson: '{"id":"x"}',
          state: options.state,
          name: 'Gainer iPhone',
        );
        final listed = await api.listPasskeys();
        await api.deletePasskey(created.id);

        expect(created.createdAt, DateTime.utc(2026, 10, 20, 12));
        expect(listed.single.name, 'Gainer iPhone');
        expect(() => api.deletePasskey('../x'), throwsArgumentError);
        expect(requests, [
          'POST /api/v1/auth/login',
          'POST /api/v1/auth/passkeys/creation-options',
          'POST /api/v1/auth/passkeys',
          'GET /api/v1/auth/passkeys',
          'DELETE /api/v1/auth/passkeys/AQ',
        ]);
      } finally {
        api.close();
        await server.close();
      }
    });

    test(
      'renews an expiring access token once for concurrent requests',
      () async {
        final requests = <String>[];
        final server = await _TestApiServer.start((request) async {
          requests.add('${request.method} ${request.uri.path}');
          if (request.uri.path == '/api/v1/auth/login') {
            return _json(request, _tokens(1));
          }
          if (request.uri.path == '/api/v1/auth/refresh') {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            return _json(request, _tokens(2));
          }
          expect(request.headers.value('authorization'), 'Bearer access-2');
          return _json(request, {
            'userId': '11111111-1111-4111-8111-111111111111',
            'email': 'member@example.test',
            'isAccountOperator': false,
          });
        });
        var now = DateTime.utc(2026, 10, 20, 12);
        final rotated = <String>[];
        final api = ApiClient(
          configuration: ApiConfiguration(
            apiOrigin: server.origin,
            allowInsecureLoopbackForDevelopment: true,
          ),
          clock: () => now,
        )..onRefreshTokenRotated = (token) async => rotated.add(token);
        try {
          await api.login(
            const ApiLoginRequest(email: 'member@example.test', password: 'pw'),
          );
          now = now.add(const Duration(seconds: 900 - 10));
          await Future.wait([api.getSession(), api.getSession()]);

          expect(rotated, ['refresh-2']);
          expect(requests, [
            'POST /api/v1/auth/login',
            'POST /api/v1/auth/refresh',
            'GET /api/v1/auth/session',
            'GET /api/v1/auth/session',
          ]);
        } finally {
          api.close();
          await server.close();
        }
      },
    );

    test('retries once with a renewed token after a 401', () async {
      final requests = <String>[];
      final server = await _TestApiServer.start((request) async {
        requests.add(
          '${request.method} ${request.uri.path} '
          '${request.headers.value('authorization')}',
        );
        if (request.uri.path == '/api/v1/auth/login') {
          return _json(request, _tokens(1));
        }
        if (request.uri.path == '/api/v1/auth/refresh') {
          return _json(request, _tokens(2));
        }
        if (request.headers.value('authorization') == 'Bearer access-1') {
          request.response.statusCode = HttpStatus.unauthorized;
          return request.response.close();
        }
        return _json(request, {'products': [], 'page': 1, 'hasMore': false});
      });
      final api = ApiClient(
        configuration: ApiConfiguration(
          apiOrigin: server.origin,
          allowInsecureLoopbackForDevelopment: true,
        ),
      );
      try {
        await api.login(
          const ApiLoginRequest(email: 'member@example.test', password: 'pw'),
        );
        final foods = await api.searchFoods(query: 'oats');
        expect(foods.hasMore, isFalse);
        expect(requests, [
          'POST /api/v1/auth/login null',
          'GET /api/v1/foods/search Bearer access-1',
          'POST /api/v1/auth/refresh null',
          'GET /api/v1/foods/search Bearer access-2',
        ]);
      } finally {
        api.close();
        await server.close();
      }
    });

    test(
      'a rejected refresh token ends the device session without retrying',
      () async {
        final requests = <String>[];
        final server = await _TestApiServer.start((request) async {
          requests.add('${request.method} ${request.uri.path}');
          if (request.uri.path == '/api/v1/auth/refresh') {
            request.response.statusCode = HttpStatus.unauthorized;
            return _json(request, {'code': 'invalid_refresh_token'});
          }
          request.response.statusCode = HttpStatus.unauthorized;
          await request.response.close();
        });
        final secureStorage = _MemorySecureSession()
          ..checkpoint = Uint8List.fromList(
            utf8.encode(
              jsonEncode({
                'schemaVersion': 2,
                'apiOrigin': server.origin.origin,
                'userId': '11111111-1111-4111-8111-111111111111',
                'email': 'member@example.test',
                'refreshToken': 'revoked',
              }),
            ),
          );
        var rejected = 0;
        final api = ApiClient(
          configuration: ApiConfiguration(
            apiOrigin: server.origin,
            allowInsecureLoopbackForDevelopment: true,
          ),
        )..onSessionRejected = () => rejected++;
        final sessions = ApiSessionService(
          api: api,
          secureStorage: secureStorage,
        );
        try {
          expect(await sessions.restore(), isNull);
          expect(rejected, 1);
          expect(api.hasDeviceSession, isFalse);
          expect(secureStorage.checkpoint, isNull);
          expect(requests, [
            'POST /api/v1/auth/refresh',
            'GET /api/v1/auth/session',
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

    test('surfaces the server account guard as account_changed', () async {
      final server = await _TestApiServer.start((request) async {
        expect(
          request.headers.value('x-gainer-account-id'),
          'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        );
        request.response.statusCode = HttpStatus.conflict;
        return _json(request, {
          'title':
              'The authenticated account does not match this sync profile.',
          'code': 'account_changed',
        });
      });
      final api = ApiClient(
        configuration: ApiConfiguration(
          apiOrigin: server.origin,
          allowInsecureLoopbackForDevelopment: true,
        ),
      );
      try {
        await expectLater(
          api.registerSyncClient(
            const SyncClientRegistrationRequest(
              clientId: '22222222-2222-4222-8222-222222222222',
              displayName: 'iPhone',
              protocolVersion: 2,
              takeOverWriting: false,
            ),
            expectedAccountId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          ),
          throwsA(
            isA<ApiException>().having(
              (error) => error.code,
              'code',
              'account_changed',
            ),
          ),
        );
      } finally {
        api.close();
        await server.close();
      }
    });

    test(
      'binds sync pull response to the expected account in the same request',
      () async {
        final server = await _TestApiServer.start((request) async {
          expect(request.method, 'GET');
          expect(request.uri.path, '/api/v1/sync/changes');
          expect(
            request.headers.value('x-gainer-account-id'),
            'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          );
          return _json(request, {
            'protocolVersion': 2,
            'nextCursor': 0,
            'hasMore': false,
            'batches': [],
          });
        });
        final api = ApiClient(
          configuration: ApiConfiguration(
            apiOrigin: server.origin,
            allowInsecureLoopbackForDevelopment: true,
          ),
        );
        try {
          final result = await api.pullChanges(
            after: 0,
            expectedAccountId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          );
          expect(result.batches, isEmpty);
        } finally {
          api.close();
          await server.close();
        }
      },
    );

    test('sends account identity on scoped sync writes', () async {
      final requests = <String>[];
      final server = await _TestApiServer.start((request) async {
        requests.add('${request.method} ${request.uri.path}');
        expect(
          request.headers.value('x-gainer-account-id'),
          'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        );
        return _json(request, {
          'clientId': '22222222-2222-4222-8222-222222222222',
          'displayName': 'iPhone',
          'protocolVersion': 2,
          'isActiveWriter': true,
          'registeredAtUtc': '2026-10-12T12:00:00Z',
          'lastSeenAtUtc': '2026-10-12T12:00:00Z',
        });
      });
      final api = ApiClient(
        configuration: ApiConfiguration(
          apiOrigin: server.origin,
          allowInsecureLoopbackForDevelopment: true,
        ),
      );
      try {
        await api.registerSyncClient(
          const SyncClientRegistrationRequest(
            clientId: '22222222-2222-4222-8222-222222222222',
            displayName: 'iPhone',
            protocolVersion: 2,
            takeOverWriting: false,
          ),
          expectedAccountId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        );
        expect(requests, [
          'PUT /api/v1/sync/clients/22222222-2222-4222-8222-222222222222',
        ]);
      } finally {
        api.close();
        await server.close();
      }
    });

    test(
      'secure session checkpoints are bound to the API origin and version',
      () {
        final api = ApiClient(
          configuration: ApiConfiguration(
            apiOrigin: Uri.parse('https://api.example.test'),
          ),
        );
        Uint8List checkpoint(Map<String, Object?> values) => Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'schemaVersion': 2,
              'apiOrigin': 'https://api.example.test',
              'userId': '11111111-1111-4111-8111-111111111111',
              'email': 'member@example.test',
              'refreshToken': 'refresh-token',
              ...values,
            }),
          ),
        );
        try {
          expect(
            () => api.restoreSecureCheckpoint(
              checkpoint({'apiOrigin': 'https://different.example'}),
            ),
            throwsA(isA<FormatException>()),
          );
          expect(
            () => api.restoreSecureCheckpoint(
              checkpoint({'schemaVersion': 1, 'cookies': []}),
            ),
            throwsA(isA<FormatException>()),
          );
          expect(
            () => api.restoreSecureCheckpoint(checkpoint({'refreshToken': ''})),
            throwsA(isA<FormatException>()),
          );
          final restored = api.restoreSecureCheckpoint(checkpoint({}));
          expect(restored.userId, '11111111-1111-4111-8111-111111111111');
          expect(api.hasDeviceSession, isTrue);
        } finally {
          api.close();
        }
      },
    );

    test('only HTTPS origins or loopback HTTP origins are accepted', () {
      expect(
        () => ApiConfiguration(apiOrigin: Uri.parse('http://api.example.test')),
        throwsArgumentError,
      );
      expect(
        () => ApiConfiguration(
          apiOrigin: Uri.parse('https://user:password@api.example.test'),
        ),
        throwsArgumentError,
      );
    });
  });
}

Map<String, Object?> _tokens(int generation) => {
  'accessToken': 'access-$generation',
  'expiresIn': 900,
  'refreshToken': 'refresh-$generation',
  'refreshTokenExpiresAt': '2026-12-19T12:00:00Z',
};

Future<void> _jsonList(HttpRequest request, List<Object?> body) async {
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(body));
  await request.response.close();
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

class _ScriptedPasskeys implements PasskeyPlatform {
  bool cancel = false;
  final challenges = <Uint8List>[];

  @override
  Future<PlatformPasskeyRegistration?> createPasskey({
    required String relyingPartyId,
    required Uint8List challenge,
    required Uint8List userId,
    required String userName,
  }) async => null;

  @override
  Future<PlatformPasskeyAssertion?> assertPasskey({
    required String relyingPartyId,
    required Uint8List challenge,
  }) async {
    expect(relyingPartyId, 'gainer.markfort.xyz');
    if (cancel) return null;
    challenges.add(challenge);
    return PlatformPasskeyAssertion(
      credentialId: Uint8List.fromList([1]),
      clientDataJson: Uint8List.fromList([2]),
      authenticatorData: Uint8List.fromList([3]),
      signature: Uint8List.fromList([4]),
      userHandle: Uint8List.fromList([5]),
    );
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
