import 'generated/mobile_platform_api.dart';
import 'platform_ports.dart';

class PigeonFileSharePlatform implements FileSharePlatform {
  PigeonFileSharePlatform({MobilePlatformApi? api})
    : _api = api ?? MobilePlatformApi();

  final MobilePlatformApi _api;

  @override
  Future<void> shareFile(String path) => _api.shareFile(path);
}
