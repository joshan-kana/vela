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
  let authKind: String
  let bearerToken: String?
  let hubURL: String?
  let clientID: String?
  let scope: String?
  let accessToken: String?
  let refreshToken: String?
  let expiresAtMilliseconds: Int64?

  private enum CodingKeys: String, CodingKey {
    case serviceURL = "service_url"
    case authKind = "auth_kind"
    case bearerToken = "bearer_token"
    case hubURL = "hub_url"
    case clientID = "client_id"
    case scope
    case accessToken = "access_token"
    case refreshToken = "refresh_token"
    case expiresAtMilliseconds = "expires_at_ms"
  }
}

private struct PendingOAuth: Codable {
  let serviceURL: String
  let authorization: OAuthAuthorization

  private enum CodingKeys: String, CodingKey {
    case serviceURL = "service_url"
    case authorization
  }
}

enum SecureAccountStoreError: LocalizedError {
  case invalidStoredValue
  case keychain(operation: String, status: OSStatus)
  case oauth(String)

  var errorDescription: String? {
    switch self {
    case .invalidStoredValue:
      return "Stored YouTrack credentials are invalid."
    case .keychain(let operation, let status):
      let detail = SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error"
      return "\(operation) failed (\(status)): \(detail)"
    case .oauth(let message):
      return message
    }
  }
}

enum SecureAccountStore {
  static let permanentToken = "permanent_token"
  static let oauthPKCE = "oauth_pkce"

  private static let accountService = "io.github.joshankana.vela.youtrack"
  private static let pendingOAuthService = "io.github.joshankana.vela.oauth.pending"
  private static let refreshSkewMilliseconds: Int64 = 60_000

  static func accounts() throws -> [StoredAccount] {
    try entries(service: accountService, as: AccountSecret.self).map { entry in
      StoredAccount(
        id: entry.id,
        serviceURL: entry.value.serviceURL,
        authKind: entry.value.authKind
      )
    }
    .sorted { $0.serviceURL.localizedCaseInsensitiveCompare($1.serviceURL) == .orderedAscending }
  }

  static func savePermanentToken(serviceURL: String, bearerToken: String) throws -> StoredAccount {
    let normalizedURL = serviceURL.trimmingCharacters(in: .whitespacesAndNewlines)
    let id = try existingAccountID(serviceURL: normalizedURL) ?? UUID().uuidString.lowercased()
    let secret = AccountSecret(
      serviceURL: normalizedURL,
      authKind: permanentToken,
      bearerToken: bearerToken,
      hubURL: nil,
      clientID: nil,
      scope: nil,
      accessToken: nil,
      refreshToken: nil,
      expiresAtMilliseconds: nil
    )

    try save(service: accountService, id: id, value: secret)
    return StoredAccount(id: id, serviceURL: normalizedURL, authKind: permanentToken)
  }

  static func saveOAuthAccount(
    serviceURL: String,
    authorization: OAuthAuthorization,
    tokens: OAuthTokenSet
  ) throws -> StoredAccount {
    let normalizedURL = serviceURL.trimmingCharacters(in: .whitespacesAndNewlines)
    let id = try existingAccountID(serviceURL: normalizedURL) ?? UUID().uuidString.lowercased()
    let secret = AccountSecret(
      serviceURL: normalizedURL,
      authKind: oauthPKCE,
      bearerToken: nil,
      hubURL: authorization.hubURL,
      clientID: authorization.clientID,
      scope: authorization.scope,
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      expiresAtMilliseconds: expiryMilliseconds(expiresIn: tokens.expiresIn)
    )

    try save(service: accountService, id: id, value: secret)
    return StoredAccount(id: id, serviceURL: normalizedURL, authKind: oauthPKCE)
  }

  static func bearerToken(for accountID: String) throws -> String {
    var secret: AccountSecret = try load(service: accountService, id: accountID)

    switch secret.authKind {
    case permanentToken:
      guard let bearerToken = secret.bearerToken else {
        throw SecureAccountStoreError.invalidStoredValue
      }
      return bearerToken

    case oauthPKCE:
      guard let accessToken = secret.accessToken else {
        throw SecureAccountStoreError.invalidStoredValue
      }

      if let expiresAt = secret.expiresAtMilliseconds,
        expiresAt <= currentMilliseconds() + refreshSkewMilliseconds
      {
        guard
          let hubURL = secret.hubURL,
          let clientID = secret.clientID,
          let scope = secret.scope,
          let refreshToken = secret.refreshToken
        else {
          throw SecureAccountStoreError.oauth(
            "OAuth access token expired and no refresh token is available."
          )
        }

        let tokens = try RustBridge.refreshOAuthToken(
          hubURL: hubURL,
          clientID: clientID,
          scope: scope,
          refreshToken: refreshToken
        )
        secret = AccountSecret(
          serviceURL: secret.serviceURL,
          authKind: secret.authKind,
          bearerToken: nil,
          hubURL: hubURL,
          clientID: clientID,
          scope: scope,
          accessToken: tokens.accessToken,
          refreshToken: tokens.refreshToken ?? refreshToken,
          expiresAtMilliseconds: expiryMilliseconds(expiresIn: tokens.expiresIn)
        )
        try save(service: accountService, id: accountID, value: secret)
        return tokens.accessToken
      }

      return accessToken

    default:
      throw SecureAccountStoreError.oauth("Stored YouTrack authentication method is unsupported.")
    }
  }

  static func delete(accountID: String) throws {
    try delete(service: accountService, id: accountID)
  }

  static func savePendingOAuth(
    serviceURL: String,
    authorization: OAuthAuthorization
  ) throws {
    try save(
      service: pendingOAuthService,
      id: authorization.state,
      value: PendingOAuth(serviceURL: serviceURL, authorization: authorization)
    )
  }

  static func pendingOAuth(state: String) throws -> (
    serviceURL: String, authorization: OAuthAuthorization
  ) {
    let pending: PendingOAuth = try load(service: pendingOAuthService, id: state)
    return (pending.serviceURL, pending.authorization)
  }

  static func deletePendingOAuth(state: String) throws {
    try delete(service: pendingOAuthService, id: state)
  }

  private static func existingAccountID(serviceURL: String) throws -> String? {
    try entries(service: accountService, as: AccountSecret.self)
      .first { $0.value.serviceURL == serviceURL }?
      .id
  }

  private static func expiryMilliseconds(expiresIn: Int64?) -> Int64? {
    expiresIn.map { currentMilliseconds() + ($0 * 1_000) }
  }

  private static func currentMilliseconds() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1_000)
  }

  private static func save<Value: Encodable>(
    service: String,
    id: String,
    value: Value
  ) throws {
    let data = try JSONEncoder().encode(value)
    let match: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: id,
    ]

    var add = match
    add[kSecValueData as String] = data

    let addStatus = SecItemAdd(add as CFDictionary, nil)
    if addStatus == errSecSuccess {
      return
    }

    guard addStatus == errSecDuplicateItem else {
      throw SecureAccountStoreError.keychain(
        operation: "Saving credentials",
        status: addStatus
      )
    }

    let updateStatus = SecItemUpdate(
      match as CFDictionary,
      [kSecValueData as String: data] as CFDictionary
    )
    guard updateStatus == errSecSuccess else {
      throw SecureAccountStoreError.keychain(
        operation: "Updating credentials",
        status: updateStatus
      )
    }
  }

  private static func load<Value: Decodable>(
    service: String,
    id: String
  ) throws -> Value {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: id,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data else {
      throw SecureAccountStoreError.keychain(
        operation: "Loading credentials",
        status: status
      )
    }

    return try JSONDecoder().decode(Value.self, from: data)
  }

  private static func delete(service: String, id: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: id,
    ]

    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw SecureAccountStoreError.keychain(
        operation: "Deleting credentials",
        status: status
      )
    }
  }

  private static func entries<Value: Decodable>(
    service: String,
    as _: Value.Type
  ) throws -> [(id: String, value: Value)] {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecReturnAttributes as String: true,
      kSecMatchLimit as String: kSecMatchLimitAll,
    ]

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound {
      return []
    }
    guard status == errSecSuccess else {
      throw SecureAccountStoreError.keychain(
        operation: "Listing credentials",
        status: status
      )
    }

    let rawItems: [[String: Any]]
    if let items = result as? [[String: Any]] {
      rawItems = items
    } else if let item = result as? [String: Any] {
      rawItems = [item]
    } else {
      throw SecureAccountStoreError.invalidStoredValue
    }

    return try rawItems.map { item in
      guard let id = item[kSecAttrAccount as String] as? String else {
        throw SecureAccountStoreError.invalidStoredValue
      }

      let value: Value = try load(service: service, id: id)
      return (id, value)
    }
  }
}
