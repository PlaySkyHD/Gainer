import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/data/services/platform/generated/mobile_platform_api.dart',
    swiftOut: 'ios/Runner/MobilePlatformApi.g.swift',
    dartPackageName: 'gainer_mobile',
  ),
)
class PlatformHealthCheck {
  const PlatformHealthCheck({required this.available});

  final bool available;
}

@HostApi()
abstract class MobilePlatformApi {
  @async
  PlatformHealthCheck getPlatformHealth();
}
