import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/services/platform/generated/mobile_platform_api.dart';
import 'package:gainer_mobile/data/services/platform/pigeon_web_authentication_platform.dart';

void main() {
  test('passes the URL and scheme to the sign-in sheet', () async {
    final api = _FakeApi()..callback = 'gainer://strava?result=connected';
    final platform = PigeonWebAuthenticationPlatform(api: api);

    final callback = await platform.authenticate(
      Uri.parse('https://www.strava.com/oauth/mobile/authorize?state=x'),
      callbackScheme: 'gainer',
    );

    expect(api.calls, [
      ('https://www.strava.com/oauth/mobile/authorize?state=x', 'gainer'),
    ]);
    expect(callback, Uri.parse('gainer://strava?result=connected'));
  });

  test('returns null when the user closes the sheet', () async {
    final platform = PigeonWebAuthenticationPlatform(api: _FakeApi());

    expect(
      await platform.authenticate(
        Uri.parse('https://www.strava.com/'),
        callbackScheme: 'gainer',
      ),
      isNull,
    );
  });
}

class _FakeApi extends MobilePlatformApi {
  String? callback;
  final calls = <(String, String)>[];

  @override
  Future<String?> authenticateWebSession(
    String url,
    String callbackScheme,
  ) async {
    calls.add((url, callbackScheme));
    return callback;
  }
}
