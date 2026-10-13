import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    MobilePlatformApiSetup.setUp(
      binaryMessenger: engineBridge.applicationRegistrar.messenger(),
      api: GainerMobilePlatform()
    )
    NativeRouteDispatcher.shared.attach(
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
  }
}
