import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/api/api_models.dart';
import 'package:gainer_mobile/data/repositories/coach/coach_memory_repository.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';

void main() {
  const id = '11111111-2222-4333-8444-555555555555';
  Map<String, Object?> memoryJson(String category, String text) => {
    'id': id,
    'category': category,
    'text': text,
    'createdAtUtc': '2026-10-24T12:00:00Z',
    'updatedAtUtc': '2026-10-24T12:30:00Z',
    'version': 2,
  };

  test('repository drives every memory endpoint of the server', () async {
    final requests = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      requests.add('${request.method} ${request.uri.path} $body'.trim());
      final response = request.response;
      if (request.method == 'DELETE') {
        response.statusCode = HttpStatus.noContent;
        await response.close();
        return;
      }
      response.headers.contentType = ContentType.json;
      if (request.method == 'GET') {
        response.write(
          jsonEncode({
            'items': [memoryJson('goal', 'Halbmarathon im Mai')],
            'maxEntries': 50,
          }),
        );
      } else {
        final payload = jsonDecode(body) as Map<String, dynamic>;
        response.statusCode = request.method == 'POST' ? 201 : 200;
        response.write(
          jsonEncode(
            memoryJson(
              payload['category'] as String,
              payload['text'] as String,
            ),
          ),
        );
      }
      await response.close();
    });
    final api = ApiClient(
      configuration: ApiConfiguration(
        apiOrigin: Uri(
          scheme: 'http',
          host: server.address.address,
          port: server.port,
        ),
        allowInsecureLoopbackForDevelopment: true,
      ),
    );
    final repository = ApiCoachMemoryRepository(api);
    try {
      final list = await repository.list();
      expect(list.maxEntries, 50);
      expect(list.items.single.category, CoachMemoryCategory.goal);
      expect(
        list.items.single.updatedAtUtc,
        DateTime.utc(2026, 10, 24, 12, 30),
      );
      expect(list.items.single.version, 2);

      final created = await repository.create(
        CoachMemoryCategory.intolerance,
        '  Laktoseintoleranz ',
      );
      expect(created.text, 'Laktoseintoleranz');
      final updated = await repository.update(
        id,
        CoachMemoryCategory.injury,
        'Knie schonen',
      );
      expect(updated.category, CoachMemoryCategory.injury);
      await repository.delete(id);
      await repository.deleteAll();

      expect(requests, [
        'GET /api/v1/coach/memories',
        'POST /api/v1/coach/memories {"category":"intolerance","text":"Laktoseintoleranz"}',
        'PUT /api/v1/coach/memories/$id {"category":"injury","text":"Knie schonen"}',
        'DELETE /api/v1/coach/memories/$id',
        'DELETE /api/v1/coach/memories',
      ]);

      expect(
        () => repository.create(CoachMemoryCategory.goal, '   '),
        throwsArgumentError,
      );
      expect(
        () => repository.create(CoachMemoryCategory.goal, 'a' * 201),
        throwsArgumentError,
      );
      expect(
        () => repository.update('../x', CoachMemoryCategory.goal, 'x'),
        throwsArgumentError,
      );
      expect(() => repository.delete('nope'), throwsArgumentError);
    } finally {
      api.close();
      await subscription.cancel();
      await server.close(force: true);
    }
  });

  test('coach response reads memory suggestions leniently', () {
    final base = {
      'summary': 'S',
      'observations': [
        {'text': 'O', 'factIds': <String>[]},
      ],
      'dataGaps': <String>[],
      'suggestions': <String>[],
      'asOfRevision': 1,
    };
    expect(ApiCoachResponse.fromJson(base).memorySuggestions, isEmpty);

    final response = ApiCoachResponse.fromJson({
      ...base,
      'memorySuggestions': [
        {'category': 'goal', 'text': ' Halbmarathon im Mai '},
        {'category': 'diagnosis', 'text': 'unbekannt'},
        {'category': 'other', 'text': '   '},
        {'category': 'other'},
        'kaputt',
      ],
    });
    final suggestion = response.memorySuggestions.single;
    expect(suggestion.category, CoachMemoryCategory.goal);
    expect(suggestion.text, 'Halbmarathon im Mai');
  });

  test('memory models reject incomplete entries', () {
    expect(
      () => ApiCoachMemory.fromJson({'id': id, 'category': 'goal'}),
      throwsFormatException,
    );
    expect(
      () => ApiCoachMemory.fromJson({
        ...memoryJson('goal', 'x'),
        'category': 'unknown',
      }),
      throwsFormatException,
    );
    expect(
      () => ApiCoachMemoryList.fromJson({'items': 'x'}),
      throwsFormatException,
    );
    final defaults = ApiCoachMemoryList.fromJson({
      'items': [
        {...memoryJson('other', 'x')}..remove('version'),
      ],
    });
    expect(defaults.maxEntries, 50);
    expect(defaults.items.single.version, 1);
    expect(CoachMemoryCategory.fromWire('injury'), CoachMemoryCategory.injury);
    expect(CoachMemoryCategory.fromWire(null), isNull);
  });

  test('error messages name the reason', () {
    ApiException problem(String code) =>
        ApiException(statusCode: 409, code: code, message: code);
    expect(
      coachMemoryErrorMessage(problem('memory_limit_reached')),
      contains('voll'),
    );
    expect(
      coachMemoryErrorMessage(problem('memory_duplicate')),
      'Diese Notiz gibt es schon.',
    );
    expect(
      coachMemoryErrorMessage(problem('memory_not_found')),
      contains('nicht mehr'),
    );
    expect(
      coachMemoryErrorMessage(problem('network_error')),
      contains('Keine Verbindung'),
    );
    expect(coachMemoryErrorMessage(StateError('x')), contains('Versuche'));
    expect(isCoachMemoryOfflineError(problem('network_error')), isTrue);
    expect(isCoachMemoryOfflineError(problem('memory_duplicate')), isFalse);
  });
}
