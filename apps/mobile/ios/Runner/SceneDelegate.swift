import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
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

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    for context in URLContexts {
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

  private func receive(_ url: URL) {
    NativeRouteDispatcher.shared.receive(url: url, source: "widget")
  }
}
