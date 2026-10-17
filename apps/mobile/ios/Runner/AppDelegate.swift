import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // UNUserNotificationCenter hält seinen Delegate nur schwach.
  private var timerNotificationDelegate: TimerNotificationDelegate?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let center = UNUserNotificationCenter.current()
    let delegate = TimerNotificationDelegate(previousDelegate: center.delegate)
    timerNotificationDelegate = delegate
    center.delegate = delegate
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
