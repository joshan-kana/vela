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

enum CapabilityState: String, Decodable {
  case available
  case forbidden
  case unsupported
}

struct Discovered<Value: Decodable>: Decodable {
  let capability: CapabilityState
  let items: [Value]
}

struct ProjectReference: Decodable {
  let id: String
  let shortName: String
  let name: String
  let archived: Bool?

  private enum CodingKeys: String, CodingKey {
    case id
    case shortName = "short_name"
    case name
    case archived
  }
}

struct UserReference: Decodable {
  let id: String
  let login: String
  let fullName: String

  private enum CodingKeys: String, CodingKey {
    case id
    case login
    case fullName = "full_name"
  }
}

struct AgileBoard: Decodable {
  let id: String
  let name: String
  let owner: UserReference?
}

struct SavedQuery: Decodable {
  let id: String
  let name: String
  let query: String?
  let owner: UserReference?
}

struct IssueLinkType: Decodable {
  let id: String
  let name: String
  let sourceToTarget: String
  let targetToSource: String?
  let directed: Bool
  let aggregation: Bool
  let readOnly: Bool

  private enum CodingKeys: String, CodingKey {
    case id
    case name
    case sourceToTarget = "source_to_target"
    case targetToSource = "target_to_source"
    case directed
    case aggregation
    case readOnly = "read_only"
  }
}

struct YouTrackDiscovery: Decodable {
  let projects: Discovered<ProjectReference>
  let users: CapabilityState
  let issueLinkTypes: Discovered<IssueLinkType>
  let agileBoards: CapabilityState
  let savedQueries: CapabilityState

  private enum CodingKeys: String, CodingKey {
    case projects
    case users
    case issueLinkTypes = "issue_link_types"
    case agileBoards = "agile_boards"
    case savedQueries = "saved_queries"
  }
}

struct ProjectFieldType: Decodable {
  let id: String
  let valueType: String
  let isMultiValue: Bool

  private enum CodingKeys: String, CodingKey {
    case id
    case valueType = "value_type"
    case isMultiValue = "is_multi_value"
  }
}

struct BundleValue: Decodable {
  let id: String
  let valueType: String
  let displayName: String
  let localizedName: String?
  let archived: Bool?
  let ordinal: Int64?
  let isResolved: Bool?

  private enum CodingKeys: String, CodingKey {
    case id
    case valueType = "value_type"
    case displayName = "display_name"
    case localizedName = "localized_name"
    case archived
    case ordinal
    case isResolved = "is_resolved"
  }
}

struct FieldBundle: Decodable {
  let id: String
  let bundleType: String
  let values: [BundleValue]

  private enum CodingKeys: String, CodingKey {
    case id
    case bundleType = "bundle_type"
    case values
  }
}

struct CustomFieldDefinition: Decodable {
  let id: String
  let name: String
  let localizedName: String?
  let aliases: String?
  let fieldType: ProjectFieldType

  private enum CodingKeys: String, CodingKey {
    case id
    case name
    case localizedName = "localized_name"
    case aliases
    case fieldType = "field_type"
  }
}

struct ProjectCustomField: Decodable {
  let id: String
  let projectFieldType: String
  let field: CustomFieldDefinition
  let canBeEmpty: Bool
  let isPublic: Bool
  let ordinal: Int64
  let bundle: FieldBundle?

  private enum CodingKeys: String, CodingKey {
    case id
    case projectFieldType = "project_field_type"
    case field
    case canBeEmpty = "can_be_empty"
    case isPublic = "is_public"
    case ordinal
    case bundle
  }
}

struct ProjectSchema: Decodable {
  let project: ProjectReference
  let customFields: [ProjectCustomField]

  private enum CodingKeys: String, CodingKey {
    case project
    case customFields = "custom_fields"
  }
}

enum JSONValue: Codable, Equatable {
  case null
  case bool(Bool)
  case integer(Int64)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int64.self) {
      self = .integer(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else if let value = try? container.decode([String: JSONValue].self) {
      self = .object(value)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Unsupported JSON value"
      )
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()

    switch self {
    case .null:
      try container.encodeNil()
    case .bool(let value):
      try container.encode(value)
    case .integer(let value):
      try container.encode(value)
    case .number(let value):
      try container.encode(value)
    case .string(let value):
      try container.encode(value)
    case .array(let value):
      try container.encode(value)
    case .object(let value):
      try container.encode(value)
    }
  }
}

struct FieldEvent: Decodable {
  let id: String
  let presentation: String
}

struct CustomFieldValue: Decodable {
  let id: String
  let name: String
  let fieldType: String
  let value: JSONValue
  let possibleEvents: [FieldEvent]

  private enum CodingKeys: String, CodingKey {
    case id
    case name
    case fieldType = "field_type"
    case value
    case possibleEvents = "possible_events"
  }
}

struct IssueDetails: Decodable {
  let id: String
  let idReadable: String
  let summary: String
  let description: String?
  let createdAt: Int64
  let updatedAt: Int64
  let resolvedAt: Int64?
  let project: ProjectReference
  let customFields: [CustomFieldValue]

  private enum CodingKeys: String, CodingKey {
    case id
    case idReadable = "id_readable"
    case summary
    case description
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case resolvedAt = "resolved_at"
    case project
    case customFields = "custom_fields"
  }
}

struct IssueEnrichment: Decodable {
  let schema: ProjectSchema
  let links: [IssueLink]
}

struct IssueReference: Decodable {
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

struct IssueLink: Decodable {
  let id: String
  let direction: String
  let linkType: IssueLinkType
  let issues: [IssueReference]

  private enum CodingKeys: String, CodingKey {
    case id
    case direction
    case linkType = "link_type"
    case issues
  }
}
