import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/services/platform/generated/mobile_platform_api.dart';
import 'package:gainer_mobile/data/services/platform/pigeon_file_share_platform.dart';

void main() {
  test('passes the file path to the share sheet', () async {
    final api = _FakeApi();
    final platform = PigeonFileSharePlatform(api: api);

    await platform.shareFile('/tmp/export/gainer-export-2026-10-24.json');

    expect(api.paths, ['/tmp/export/gainer-export-2026-10-24.json']);
  });
}

class _FakeApi extends MobilePlatformApi {
  final paths = <String>[];

  @override
  Future<void> shareFile(String path) async => paths.add(path);
}
