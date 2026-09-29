import Foundation
import Security

struct StoredAccount: Codable, Equatable {
  let id: String
  let serviceURL: String
  let authKind: String

  private enum CodingKeys: String, CodingKey {
    case id
    case serviceURL = "service_url"
    case authKind = "auth_kind"
  }
}

private struct AccountSecret: Codable {
  let serviceURL: String
  let bearerToken: String
  let authKind: String

  private enum CodingKeys: String, CodingKey {
    case serviceURL = "service_url"
    case bearerToken = "bearer_token"
    case authKind = "auth_kind"
  }
}

enum SecureAccountStoreError: LocalizedError {
  case invalidStoredValue
  case keychain(OSStatus)

  var errorDescription: String? {
    switch self {
    case .invalidStoredValue:
      "Stored YouTrack credentials are invalid."
    case .keychain(let status):
      SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)."
    }
  }
}

enum SecureAccountStore {
  private static let service = "io.github.joshankana.vela.youtrack"
  private static let permanentToken = "permanent_token"

  static func accounts() throws -> [StoredAccount] {
    try entries().map { entry in
      StoredAccount(
        id: entry.id,
        serviceURL: entry.secret.serviceURL,
        authKind: entry.secret.authKind
      )
    }
    .sorted { $0.serviceURL.localizedCaseInsensitiveCompare($1.serviceURL) == .orderedAscending }
  }

  static func savePermanentToken(serviceURL: String, bearerToken: String) throws -> StoredAccount {
    let normalizedURL = serviceURL.trimmingCharacters(in: .whitespacesAndNewlines)
    let existing = try entries().first { $0.secret.serviceURL == normalizedURL }
    let id = existing?.id ?? UUID().uuidString.lowercased()
    let secret = AccountSecret(
      serviceURL: normalizedURL,
      bearerToken: bearerToken,
      authKind: permanentToken
    )
    let data = try JSONEncoder().encode(secret)

    let match: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: id,
    ]

    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    ]

    let status = SecItemUpdate(match as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      var add = match
      for (key, value) in attributes {
        add[key] = value
      }
      let addStatus = SecItemAdd(add as CFDictionary, nil)
      guard addStatus == errSecSuccess else {
        throw SecureAccountStoreError.keychain(addStatus)
      }
    } else if status != errSecSuccess {
      throw SecureAccountStoreError.keychain(status)
    }

    return StoredAccount(id: id, serviceURL: normalizedURL, authKind: permanentToken)
  }

  static func bearerToken(for accountID: String) throws -> String {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: accountID,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess else {
      throw SecureAccountStoreError.keychain(status)
    }
    guard
      let data = result as? Data,
      let secret = try? JSONDecoder().decode(AccountSecret.self, from: data),
      secret.authKind == permanentToken
    else {
      throw SecureAccountStoreError.invalidStoredValue
    }

    return secret.bearerToken
  }

  static func delete(accountID: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: accountID,
    ]

    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw SecureAccountStoreError.keychain(status)
    }
  }

  private static func entries() throws -> [(id: String, secret: AccountSecret)] {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecReturnAttributes as String: true,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitAll,
    ]

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound {
      return []
    }
    guard status == errSecSuccess else {
      throw SecureAccountStoreError.keychain(status)
    }

    let rawItems: [[String: Any]]
    if let items = result as? [[String: Any]] {
      rawItems = items
    } else if let item = result as? [String: Any] {
      rawItems = [item]
    } else {
      throw SecureAccountStoreError.invalidStoredValue
    }

    return try rawItems.compactMap { item in
      guard
        let id = item[kSecAttrAccount as String] as? String,
        let data = item[kSecValueData as String] as? Data
      else {
        throw SecureAccountStoreError.invalidStoredValue
      }

      let secret = try JSONDecoder().decode(AccountSecret.self, from: data)
      return (id, secret)
    }
  }
}
