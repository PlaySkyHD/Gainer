import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/sync/data_export_service.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('gainer-export-test');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test(
    'schreibt den Export eingerückt, teilt ihn und löscht ihn danach',
    () async {
      final share = _RecordingShare();
      final service = ApiDataExportService(
        api: _ExportApi({
          'format': 'gainer-account-export',
          'resources': [
            {'resourceType': 'Workout', 'version': 2},
          ],
        }),
        share: share,
        directory: () async => temp,
        clock: () => DateTime(2026, 10, 4, 23, 30),
      );

      await service.exportAndShare();

      expect(share.paths, hasLength(1));
      expect(share.paths.single, endsWith('gainer-export-2026-10-04.json'));
      expect(
        share.contents.single,
        contains('\n  "format": "gainer-account-export"'),
      );
      expect(
        (jsonDecode(share.contents.single) as Map)['resources'],
        hasLength(1),
      );
      expect(File(share.paths.single).existsSync(), isFalse);
    },
  );

  test('löscht die Datei auch, wenn das Teilen scheitert', () async {
    final share = _RecordingShare(fail: true);
    final service = ApiDataExportService(
      api: _ExportApi({'resources': <Object?>[]}),
      share: share,
      directory: () async => temp,
    );

    await expectLater(service.exportAndShare(), throwsStateError);

    expect(File(share.paths.single).existsSync(), isFalse);
  });

  test('legt ohne Antwort keine Datei an und teilt nichts', () async {
    final share = _RecordingShare();
    final service = ApiDataExportService(
      api: _ExportApi(null),
      share: share,
      directory: () async => temp,
    );

    await expectLater(service.exportAndShare(), throwsA(isA<ApiException>()));

    expect(share.paths, isEmpty);
  });
}

class _ExportApi extends ApiClient {
  _ExportApi(this.export)
    : super(
        configuration: ApiConfiguration(
          apiOrigin: Uri.parse('http://127.0.0.1:5099'),
          allowInsecureLoopbackForDevelopment: true,
        ),
      );

  final Map<String, Object?>? export;

  @override
  Future<Map<String, Object?>> getAccountExport() async =>
      export ??
      (throw const ApiException(
        statusCode: 429,
        code: 'http_429',
        message: 'Zu viele Anfragen.',
      ));
}

class _RecordingShare implements FileSharePlatform {
  _RecordingShare({this.fail = false});

  final bool fail;
  final paths = <String>[];
  final contents = <String>[];

  @override
  Future<void> shareFile(String path) async {
    paths.add(path);
    contents.add(await File(path).readAsString());
    if (fail) throw StateError('share failed');
  }
}
