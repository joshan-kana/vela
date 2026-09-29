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
