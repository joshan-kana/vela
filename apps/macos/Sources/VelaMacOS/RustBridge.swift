import Foundation

enum RustBridgeError: LocalizedError {
  case emptyResponse
  case invalidResponse
  case requestFailed(String)

  var errorDescription: String? {
    switch self {
    case .emptyResponse:
      "Rust bridge returned no response."
    case .invalidResponse:
      "Rust bridge returned an invalid response."
    case .requestFailed(let message):
      message
    }
  }
}

enum RustBridge {
  static func discover(
    serviceURL: String,
    bearerToken: String
  ) throws -> YouTrackDiscovery {
    let result: UnsafeMutablePointer<CChar>? = serviceURL.withCString { serviceURLPointer in
      if bearerToken.isEmpty {
        vela_discover_json(serviceURLPointer, nil)
      } else {
        bearerToken.withCString { tokenPointer in
          vela_discover_json(serviceURLPointer, tokenPointer)
        }
      }
    }

    return try decode(result, fallbackMessage: "Unable to discover YouTrack capabilities.")
  }

  static func loadProjectSchema(
    serviceURL: String,
    bearerToken: String,
    projectID: String
  ) throws -> ProjectSchema {
    let result: UnsafeMutablePointer<CChar>? = serviceURL.withCString { serviceURLPointer in
      projectID.withCString { projectIDPointer in
        if bearerToken.isEmpty {
          vela_project_schema_json(serviceURLPointer, nil, projectIDPointer)
        } else {
          bearerToken.withCString { tokenPointer in
            vela_project_schema_json(serviceURLPointer, tokenPointer, projectIDPointer)
          }
        }
      }
    }

    return try decode(result, fallbackMessage: "Unable to load the project schema.")
  }

  static func loadUsers(
    serviceURL: String,
    bearerToken: String,
    skip: Int = 0,
    top: Int = 42
  ) throws -> [UserReference] {
    let normalizedSkip = max(0, skip)
    let normalizedTop = max(1, top)

    let result: UnsafeMutablePointer<CChar>? = serviceURL.withCString { serviceURLPointer in
      if bearerToken.isEmpty {
        vela_users_json(serviceURLPointer, nil, normalizedSkip, normalizedTop)
      } else {
        bearerToken.withCString { tokenPointer in
          vela_users_json(serviceURLPointer, tokenPointer, normalizedSkip, normalizedTop)
        }
      }
    }

    return try decode(result, fallbackMessage: "Unable to load YouTrack users.")
  }

  static func loadAgileBoards(
    serviceURL: String,
    bearerToken: String,
    skip: Int = 0,
    top: Int = 42
  ) throws -> [AgileBoard] {
    let normalizedSkip = max(0, skip)
    let normalizedTop = max(1, top)

    let result: UnsafeMutablePointer<CChar>? = serviceURL.withCString { serviceURLPointer in
      if bearerToken.isEmpty {
        vela_agile_boards_json(serviceURLPointer, nil, normalizedSkip, normalizedTop)
      } else {
        bearerToken.withCString { tokenPointer in
          vela_agile_boards_json(serviceURLPointer, tokenPointer, normalizedSkip, normalizedTop)
        }
      }
    }

    return try decode(result, fallbackMessage: "Unable to load agile boards.")
  }

  static func loadSavedQueries(
    serviceURL: String,
    bearerToken: String,
    skip: Int = 0,
    top: Int = 42
  ) throws -> [SavedQuery] {
    let normalizedSkip = max(0, skip)
    let normalizedTop = max(1, top)

    let result: UnsafeMutablePointer<CChar>? = serviceURL.withCString { serviceURLPointer in
      if bearerToken.isEmpty {
        vela_saved_queries_json(serviceURLPointer, nil, normalizedSkip, normalizedTop)
      } else {
        bearerToken.withCString { tokenPointer in
          vela_saved_queries_json(serviceURLPointer, tokenPointer, normalizedSkip, normalizedTop)
        }
      }
    }

    return try decode(result, fallbackMessage: "Unable to load saved queries.")
  }

  static func loadIssueDetails(
    serviceURL: String,
    bearerToken: String,
    issueID: String
  ) throws -> IssueDetails {
    let result: UnsafeMutablePointer<CChar>? = serviceURL.withCString { serviceURLPointer in
      issueID.withCString { issueIDPointer in
        if bearerToken.isEmpty {
          vela_issue_details_json(serviceURLPointer, nil, issueIDPointer)
        } else {
          bearerToken.withCString { tokenPointer in
            vela_issue_details_json(serviceURLPointer, tokenPointer, issueIDPointer)
          }
        }
      }
    }

    return try decode(result, fallbackMessage: "Unable to load issue details.")
  }

  static func loadIssueLinks(
    serviceURL: String,
    bearerToken: String,
    issueID: String
  ) throws -> [IssueLink] {
    let result: UnsafeMutablePointer<CChar>? = serviceURL.withCString { serviceURLPointer in
      issueID.withCString { issueIDPointer in
        if bearerToken.isEmpty {
          vela_issue_links_json(serviceURLPointer, nil, issueIDPointer)
        } else {
          bearerToken.withCString { tokenPointer in
            vela_issue_links_json(serviceURLPointer, tokenPointer, issueIDPointer)
          }
        }
      }
    }

    return try decode(result, fallbackMessage: "Unable to load issue links.")
  }

  static func setIssueSummary(
    serviceURL: String,
    bearerToken: String,
    issueID: String,
    summary: String
  ) throws -> IssueDetails {
    let result: UnsafeMutablePointer<CChar>? = serviceURL.withCString { serviceURLPointer in
      issueID.withCString { issueIDPointer in
        summary.withCString { summaryPointer in
          if bearerToken.isEmpty {
            vela_set_issue_summary_json(serviceURLPointer, nil, issueIDPointer, summaryPointer)
          } else {
            bearerToken.withCString { tokenPointer in
              vela_set_issue_summary_json(
                serviceURLPointer,
                tokenPointer,
                issueIDPointer,
                summaryPointer
              )
            }
          }
        }
      }
    }

    return try decode(result, fallbackMessage: "Unable to update the issue summary.")
  }

  static func setIssueDescription(
    serviceURL: String,
    bearerToken: String,
    issueID: String,
    description: String?
  ) throws -> IssueDetails {
    let result: UnsafeMutablePointer<CChar>? = serviceURL.withCString { serviceURLPointer in
      issueID.withCString { issueIDPointer in
        func update(_ descriptionPointer: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
          if bearerToken.isEmpty {
            vela_set_issue_description_json(
              serviceURLPointer,
              nil,
              issueIDPointer,
              descriptionPointer
            )
          } else {
            bearerToken.withCString { tokenPointer in
              vela_set_issue_description_json(
                serviceURLPointer,
                tokenPointer,
                issueIDPointer,
                descriptionPointer
              )
            }
          }
        }

        if let description {
          return description.withCString(update)
        }

        return update(nil)
      }
    }

    return try decode(result, fallbackMessage: "Unable to update the issue description.")
  }

  static func setCustomFieldValue(
    serviceURL: String,
    bearerToken: String,
    issueID: String,
    fieldID: String,
    fieldType: String,
    value: JSONValue
  ) throws -> CustomFieldValue {
    let data = try JSONEncoder().encode(value)
    guard let valueJSON = String(data: data, encoding: .utf8) else {
      throw RustBridgeError.invalidResponse
    }

    let result: UnsafeMutablePointer<CChar>? = serviceURL.withCString { serviceURLPointer in
      issueID.withCString { issueIDPointer in
        fieldID.withCString { fieldIDPointer in
          fieldType.withCString { fieldTypePointer in
            valueJSON.withCString { valuePointer in
              if bearerToken.isEmpty {
                vela_set_custom_field_value_json(
                  serviceURLPointer,
                  nil,
                  issueIDPointer,
                  fieldIDPointer,
                  fieldTypePointer,
                  valuePointer
                )
              } else {
                bearerToken.withCString { tokenPointer in
                  vela_set_custom_field_value_json(
                    serviceURLPointer,
                    tokenPointer,
                    issueIDPointer,
                    fieldIDPointer,
                    fieldTypePointer,
                    valuePointer
                  )
                }
              }
            }
          }
        }
      }
    }

    return try decode(result, fallbackMessage: "Unable to update the custom field.")
  }

  static func applyCustomFieldEvent(
    serviceURL: String,
    bearerToken: String,
    issueID: String,
    fieldID: String,
    fieldType: String,
    eventID: String
  ) throws -> CustomFieldValue {
    let result: UnsafeMutablePointer<CChar>? = serviceURL.withCString { serviceURLPointer in
      issueID.withCString { issueIDPointer in
        fieldID.withCString { fieldIDPointer in
          fieldType.withCString { fieldTypePointer in
            eventID.withCString { eventIDPointer in
              if bearerToken.isEmpty {
                vela_apply_custom_field_event_json(
                  serviceURLPointer,
                  nil,
                  issueIDPointer,
                  fieldIDPointer,
                  fieldTypePointer,
                  eventIDPointer
                )
              } else {
                bearerToken.withCString { tokenPointer in
                  vela_apply_custom_field_event_json(
                    serviceURLPointer,
                    tokenPointer,
                    issueIDPointer,
                    fieldIDPointer,
                    fieldTypePointer,
                    eventIDPointer
                  )
                }
              }
            }
          }
        }
      }
    }

    return try decode(result, fallbackMessage: "Unable to apply the field transition.")
  }

  static func loadMyWork(
    serviceURL: String,
    bearerToken: String,
    top: Int = 50
  ) throws -> MyWork {
    let result: UnsafeMutablePointer<CChar>? = serviceURL.withCString { serviceURLPointer in
      if bearerToken.isEmpty {
        vela_load_my_work_json(serviceURLPointer, nil, top)
      } else {
        bearerToken.withCString { tokenPointer in
          vela_load_my_work_json(serviceURLPointer, tokenPointer, top)
        }
      }
    }

    return try decode(result, fallbackMessage: "Unable to connect to YouTrack.")
  }

  private static func decode<Value: Decodable>(
    _ result: UnsafeMutablePointer<CChar>?,
    fallbackMessage: String
  ) throws -> Value {
    guard let result else {
      throw RustBridgeError.emptyResponse
    }

    defer {
      vela_string_free(result)
    }

    let json = String(cString: result)
    guard let data = json.data(using: .utf8) else {
      throw RustBridgeError.invalidResponse
    }

    let response = try JSONDecoder().decode(BridgeResponse<Value>.self, from: data)

    guard response.status == "ok", let value = response.data else {
      throw RustBridgeError.requestFailed(response.message ?? fallbackMessage)
    }

    return value
  }
}
