import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  /// Covers health data in the snapshot iOS takes for the app switcher. Added on entering the
  /// background rather than on resign-active, so Face ID and system sheets do not blur the app.
  private var privacyCover: UIView?

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    for context in connectionOptions.urlContexts {
      receive(context.url)
    }
    Task { await NativeRouteDispatcher.shared.dispatchPendingRoute() }
  }

  override func scene(_ scene: UIScene, openURLContexts urlContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: urlContexts)
    for context in urlContexts {
      receive(context.url)
    }
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    Task {
      await NativeRouteDispatcher.shared.dispatchPendingRoute()
      if #available(iOS 17.0, *) {
        await NativeLiveActivities().reconcileStaleActivities()
      }
    }
  }

  override func sceneDidEnterBackground(_ scene: UIScene) {
    super.sceneDidEnterBackground(scene)
    guard privacyCover == nil, let window else { return }
    let cover = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    cover.frame = window.bounds
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    window.addSubview(cover)
    privacyCover = cover
  }

  override func sceneWillEnterForeground(_ scene: UIScene) {
    super.sceneWillEnterForeground(scene)
    privacyCover?.removeFromSuperview()
    privacyCover = nil
  }

  private func receive(_ url: URL) {
    NativeRouteDispatcher.shared.receive(url: url, source: "widget")
  }
}
