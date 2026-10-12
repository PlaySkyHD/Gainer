import CryptoKit
import Foundation
import Security

enum SessionKeychainAccessibility: Equatable {
  case whenUnlockedThisDeviceOnly
}

protocol SessionKeychainStore {
  func read(service: String, account: String) throws -> Data?
  func write(
    _ data: Data,
    service: String,
    account: String,
    accessibility: SessionKeychainAccessibility
  ) throws
  func delete(service: String, account: String) throws
  func deleteAll(service: String) throws
}

protocol InstallMarkerStore {
  var hasSeenCurrentInstall: Bool { get }
  func markCurrentInstall()
}

enum SecureSessionKeychainError: Error, LocalizedError {
  case invalidAPIOrigin
  case invalidAccountBinding
  case invalidPendingHandoverRecord
  case keychainStatus(OSStatus)

  var errorDescription: String? {
    switch self {
    case .invalidAPIOrigin:
      return "The API origin is not a valid secure origin."
    case .invalidAccountBinding:
      return "The secure record is missing an account binding."
    case .invalidPendingHandoverRecord:
      return "The secure handover record is empty or too large."
    case .keychainStatus:
      return "The secure session could not be accessed."
    }
  }
}

final class SecureSessionKeychain {
  private static let service = "com.gainer.mobile.secure-session.v1"
  private static let pendingHandoverService = "com.gainer.mobile.pending-handover.v1"
  private static let maximumPendingHandoverBytes = 64 * 1024
  fileprivate static let installMarker = "com.gainer.mobile.install-marker.v1"

  private let store: SessionKeychainStore
  private let installMarkerStore: InstallMarkerStore
  private let installLock = NSLock()
  private var hasPreparedInstall = false

  init(
    store: SessionKeychainStore = AppleSessionKeychainStore(),
    installMarkerStore: InstallMarkerStore = UserDefaultsInstallMarkerStore()
  ) {
    self.store = store
    self.installMarkerStore = installMarkerStore
  }

  func readCheckpoint(apiOrigin: String) throws -> Data? {
    try prepareInstallIfNeeded()
    return try store.read(service: Self.service, account: account(for: apiOrigin))
  }

  func writeCheckpoint(_ checkpoint: Data, apiOrigin: String) throws {
    try prepareInstallIfNeeded()
    try store.write(
      checkpoint,
      service: Self.service,
      account: account(for: apiOrigin),
      accessibility: .whenUnlockedThisDeviceOnly
    )
  }

  func clearCheckpoint(apiOrigin: String) throws {
    try prepareInstallIfNeeded()
    try store.delete(service: Self.service, account: account(for: apiOrigin))
  }

  func readPendingHandover(apiOrigin: String, accountId: String) throws -> Data? {
    try prepareInstallIfNeeded()
    return try store.read(
      service: Self.pendingHandoverService,
      account: pendingHandoverAccount(for: apiOrigin, accountId: accountId)
    )
  }

  func writePendingHandover(_ record: Data, apiOrigin: String, accountId: String) throws {
    guard !record.isEmpty, record.count <= Self.maximumPendingHandoverBytes else {
      throw SecureSessionKeychainError.invalidPendingHandoverRecord
    }
    try prepareInstallIfNeeded()
    try store.write(
      record,
      service: Self.pendingHandoverService,
      account: pendingHandoverAccount(for: apiOrigin, accountId: accountId),
      accessibility: .whenUnlockedThisDeviceOnly
    )
  }

  func clearPendingHandover(apiOrigin: String, accountId: String) throws {
    try prepareInstallIfNeeded()
    try store.delete(
      service: Self.pendingHandoverService,
      account: pendingHandoverAccount(for: apiOrigin, accountId: accountId)
    )
  }

  private func prepareInstallIfNeeded() throws {
    installLock.lock()
    defer { installLock.unlock() }
    guard !hasPreparedInstall else { return }

    if !installMarkerStore.hasSeenCurrentInstall {
      // Keychain items can outlive app deletion. A missing app-local marker
      // identifies a fresh install, so discard this app's old secure records once.
      try store.deleteAll(service: Self.service)
      try store.deleteAll(service: Self.pendingHandoverService)
      installMarkerStore.markCurrentInstall()
    }
    hasPreparedInstall = true
  }

  private func account(for apiOrigin: String) throws -> String {
    let canonicalOrigin = try canonicalOrigin(for: apiOrigin)
    return "checkpoint.\(fingerprint(for: canonicalOrigin))"
  }

  private func pendingHandoverAccount(for apiOrigin: String, accountId: String) throws -> String {
    let normalizedAccountId = accountId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      normalizedAccountId.range(
        of: "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$",
        options: .regularExpression
      ) != nil,
      let accountUUID = UUID(uuidString: normalizedAccountId)
    else {
      throw SecureSessionKeychainError.invalidAccountBinding
    }
    let origin = try canonicalOrigin(for: apiOrigin)
    return "handover.\(fingerprint(for: "\(origin)\n\(accountUUID.uuidString.lowercased())"))"
  }

  private func fingerprint(for value: String) -> String {
    let digest = SHA256.hash(data: Data(value.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  private func canonicalOrigin(for apiOrigin: String) throws -> String {
    guard
      let components = URLComponents(string: apiOrigin),
      let scheme = components.scheme?.lowercased(),
      let host = components.host?.lowercased(),
      !host.isEmpty,
      components.user == nil,
      components.password == nil,
      components.path.isEmpty || components.path == "/",
      components.query == nil,
      components.fragment == nil
    else {
      throw SecureSessionKeychainError.invalidAPIOrigin
    }

    let isLoopback = host == "localhost" || host == "127.0.0.1" || host == "::1"
    guard scheme == "https" || (scheme == "http" && isLoopback) else {
      throw SecureSessionKeychainError.invalidAPIOrigin
    }

    let defaultPort = scheme == "https" ? 443 : 80
    let port = components.port.flatMap { $0 == defaultPort ? nil : $0 }
    let canonicalHost = host.contains(":") ? "[\(host)]" : host
    return "\(scheme)://\(canonicalHost)\(port.map { ":\($0)" } ?? "")"
  }
}

private final class UserDefaultsInstallMarkerStore: InstallMarkerStore {
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  var hasSeenCurrentInstall: Bool {
    defaults.bool(forKey: SecureSessionKeychain.installMarker)
  }

  func markCurrentInstall() {
    defaults.set(true, forKey: SecureSessionKeychain.installMarker)
  }
}

private final class AppleSessionKeychainStore: SessionKeychainStore {
  func read(service: String, account: String) throws -> Data? {
    var query = baseQuery(service: service, account: account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else {
      throw SecureSessionKeychainError.keychainStatus(status)
    }
    return data
  }

  func write(
    _ data: Data,
    service: String,
    account: String,
    accessibility: SessionKeychainAccessibility
  ) throws {
    let query = baseQuery(service: service, account: account)
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: accessibilityValue(accessibility),
    ]
    let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if updateStatus == errSecSuccess { return }
    guard updateStatus == errSecItemNotFound else {
      throw SecureSessionKeychainError.keychainStatus(updateStatus)
    }

    var insertion = query
    for (key, value) in attributes { insertion[key] = value }
    let addStatus = SecItemAdd(insertion as CFDictionary, nil)
    guard addStatus == errSecSuccess else {
      throw SecureSessionKeychainError.keychainStatus(addStatus)
    }
  }

  func delete(service: String, account: String) throws {
    let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw SecureSessionKeychainError.keychainStatus(status)
    }
  }

  func deleteAll(service: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrSynchronizable as String: false,
    ]
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw SecureSessionKeychainError.keychainStatus(status)
    }
  }

  private func baseQuery(service: String, account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: false,
    ]
  }

  private func accessibilityValue(_ accessibility: SessionKeychainAccessibility) -> CFString {
    switch accessibility {
    case .whenUnlockedThisDeviceOnly:
      return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    }
  }
}
