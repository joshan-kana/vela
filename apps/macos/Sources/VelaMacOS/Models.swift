import Foundation

struct ConnectedUser: Decodable {
  let id: String
  let login: String
  let fullName: String
  let email: String?
  let guest: Bool

  private enum CodingKeys: String, CodingKey {
    case id
    case login
    case fullName = "full_name"
    case email
    case guest
  }
}

struct MyWorkIssue: Decodable {
  let id: String
  let idReadable: String
  let summary: String
  let resolvedAt: Int64?

  private enum CodingKeys: String, CodingKey {
    case id
    case idReadable = "id_readable"
    case summary
    case resolvedAt = "resolved_at"
  }
}

struct MyWork: Decodable {
  let user: ConnectedUser
  let issues: [MyWorkIssue]
}

struct BridgeResponse<Value: Decodable>: Decodable {
  let status: String
  let data: Value?
  let message: String?
}
