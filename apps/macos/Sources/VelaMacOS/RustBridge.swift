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

    let response = try JSONDecoder().decode(BridgeResponse<MyWork>.self, from: data)

    guard response.status == "ok", let work = response.data else {
      throw RustBridgeError.requestFailed(
        response.message ?? "Unable to connect to YouTrack."
      )
    }

    return work
  }
}
