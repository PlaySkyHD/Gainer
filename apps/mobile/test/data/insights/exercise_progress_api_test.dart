import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';

const _exerciseId = '00000000-0000-4000-8000-000000000004';

void main() {
  test(
    'requests the established exercise progress endpoint and parses e1RM',
    () async {
      late Uri requestUri;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        requestUri = request.uri;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'asOfRevision': 7,
            'exerciseId': _exerciseId,
            'windowDays': 7,
            'fromUtc': '2026-10-07T00:00:00Z',
            'throughUtc': '2026-10-14T00:00:00Z',
            'volumeAlgorithmVersion': 'training-volume-v2',
            'estimatedOneRepMaxAlgorithmVersion': 'e1rm-epley-v2',
            'points': [
              {
                'workoutId': '00000000-0000-4000-8000-000000000010',
                'completedAtUtc': '2026-10-12T08:00:00Z',
                'volumeKgRepetitions': 840,
                'maxWeightKg': 80,
                'maxRepetitions': 5,
                'estimatedOneRepMaxKg': 93.3,
                'bodyweightMissing': false,
              },
            ],
            'bestSet': {
              'workoutId': '00000000-0000-4000-8000-000000000010',
              'exerciseId': _exerciseId,
              'completedAtUtc': '2026-10-12T08:00:00Z',
              'effectiveWeightKg': 80,
              'repetitions': 5,
              'estimatedOneRepMaxKg': 93.3,
            },
            'records': {
              'maxWeightKg': {
                'workoutId': '00000000-0000-4000-8000-000000000010',
                'value': 80,
              },
              'estimatedOneRepMaxKg': {
                'workoutId': '00000000-0000-4000-8000-000000000010',
                'value': 93.3,
              },
              'volumeKgRepetitions': {
                'workoutId': '00000000-0000-4000-8000-000000000010',
                'value': 840,
              },
              'maxRepetitions': null,
              'repetitionRecords': [
                {'repetitions': 5, 'maxWeightKg': 80},
              ],
            },
          }),
        );
        await request.response.close();
      });
      final api = ApiClient(
        configuration: ApiConfiguration(
          apiOrigin: Uri(
            scheme: 'http',
            host: server.address.address,
            port: server.port,
          ),
          trustedFrontendOrigin: Uri.parse('https://app.gainer.example'),
          allowInsecureLoopbackForDevelopment: true,
        ),
      );
      try {
        final result = await api.getExerciseProgress(
          exerciseId: _exerciseId,
          window: '7',
          timeZone: 'Europe/Berlin',
        );
        expect(
          requestUri.path,
          '/api/v1/insights/exercises/$_exerciseId/progress',
        );
        expect(requestUri.queryParameters, {
          'window': '7',
          'timeZone': 'Europe/Berlin',
        });
        expect(result.points.single.estimatedOneRepMaxKg, 93.3);
        expect(result.bestSet?.repetitions, 5);
        expect(result.bestSet?.effectiveWeightKg, 80);
        expect(result.points.single.maxWeightKg, 80);
        expect(result.points.single.maxRepetitions, 5);
        expect(result.records.maxWeightKg?.value, 80);
        expect(result.records.maxRepetitions, isNull);
        expect(result.windowDays, 7);
      } finally {
        api.close();
        await subscription.cancel();
        await server.close(force: true);
      }
    },
  );
}
