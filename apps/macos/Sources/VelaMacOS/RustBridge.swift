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
