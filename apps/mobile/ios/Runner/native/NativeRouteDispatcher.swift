import Flutter
import Foundation

@MainActor
final class NativeRouteDispatcher {
  static let shared = NativeRouteDispatcher()

  private let snapshotStore: NativeExtensionSnapshotStore
  private var flutterApi: MobileRouteFlutterApiProtocol?
  private var isDispatching = false
  private var retryRequested = false

  init(
    snapshotStore: NativeExtensionSnapshotStore = NativeExtensionSnapshotStore(),
    flutterApi: MobileRouteFlutterApiProtocol? = nil
  ) {
    self.snapshotStore = snapshotStore
    self.flutterApi = flutterApi
  }

  func attach(binaryMessenger: FlutterBinaryMessenger) {
    flutterApi = MobileRouteFlutterApi(binaryMessenger: binaryMessenger)
    Task { await dispatchPendingRoute() }
  }

  func receive(url: URL, source: String) {
    guard let route = GainerPendingRoute.parse(url: url, source: source) else { return }
    do {
      try snapshotStore.recordRoute(route)
      Task { await dispatchPendingRoute() }
    } catch {
      // Routes contain only a fixed feature name and expiry timestamp.
      // A failed App Group write is handled by letting the system open the app.
    }
  }

  func dispatchPendingRoute() async {
    guard let flutterApi else { return }
    if isDispatching {
      retryRequested = true
      return
    }
    isDispatching = true
    defer {
      isDispatching = false
      if retryRequested {
        retryRequested = false
        Task { await dispatchPendingRoute() }
      }
    }
    do {
      guard let route = try snapshotStore.readPendingRoute() else {
        try snapshotStore.clearPendingRoute()
        return
      }
      let routeMessage = PlatformRoute(
        destination: route.destination,
        source: route.source,
        createdAtUtcEpochMilliseconds: route.createdAtUtcEpochMilliseconds
      )
      try await flutterApi.dispatchRoute(route: routeMessage)
      try snapshotStore.clearPendingRoute(ifMatching: route)
    } catch {
      // Keep the route queued. The app may not have installed its Dart handler
      // yet; another active-scene callback retries it.
    }
  }
}
