import 'generated/mobile_platform_api.dart';
import 'platform_ports.dart';

class PigeonWebAuthenticationPlatform implements WebAuthenticationPlatform {
  PigeonWebAuthenticationPlatform({MobilePlatformApi? api})
    : _api = api ?? MobilePlatformApi();

  final MobilePlatformApi _api;

  @override
  Future<Uri?> authenticate(Uri url, {required String callbackScheme}) async {
    final callback = await _api.authenticateWebSession(
      url.toString(),
      callbackScheme,
    );
    return callback == null ? null : Uri.tryParse(callback);
  }
}
