import Darwin
import Foundation

enum OAuthLoopbackServerError: LocalizedError {
  case alreadyRunning
  case systemCall(name: String, code: Int32)

  var errorDescription: String? {
    switch self {
    case .alreadyRunning:
      return "The OAuth callback listener is already running."
    case .systemCall(let name, let code):
      return "\(name) failed (\(code)): \(String(cString: strerror(code)))"
    }
  }
}

final class OAuthLoopbackServer {
  static let host = "127.0.0.1"
  static let port: UInt16 = 8765
  static let path = "/oauth/callback"
  static let redirectURI = "http://\(host):\(port)\(path)"

  private let queue = DispatchQueue(label: "io.github.joshankana.vela.oauth-loopback")
  private var source: DispatchSourceRead?
  private var socketFD: Int32 = -1
  private var callback: ((Result<String, Error>) -> Void)?

  deinit {
    stop()
  }

  func start(callback: @escaping (Result<String, Error>) -> Void) throws {
    guard source == nil else {
      throw OAuthLoopbackServerError.alreadyRunning
    }

    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else {
      throw systemCallError("socket")
    }

    var reuseAddress: Int32 = 1
    guard
      setsockopt(
        fd,
        SOL_SOCKET,
        SO_REUSEADDR,
        &reuseAddress,
        socklen_t(MemoryLayout.size(ofValue: reuseAddress))
      ) == 0
    else {
      let error = systemCallError("setsockopt")
      close(fd)
      throw error
    }

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = Self.port.bigEndian
    address.sin_addr = in_addr(s_addr: inet_addr(Self.host))

    let bindStatus = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
        Darwin.bind(
          fd,
          socketAddress,
          socklen_t(MemoryLayout<sockaddr_in>.size)
        )
      }
    }

    guard bindStatus == 0 else {
      let error = systemCallError("bind")
      close(fd)
      throw error
    }

    guard listen(fd, 4) == 0 else {
      let error = systemCallError("listen")
      close(fd)
      throw error
    }

    self.callback = callback
    socketFD = fd

    let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
    source.setEventHandler { [weak self] in
      self?.acceptConnection()
    }
    source.setCancelHandler {
      close(fd)
    }

    self.source = source
    source.resume()
  }

  func stop() {
    callback = nil

    guard let source else {
      return
    }

    self.source = nil
    socketFD = -1
    source.cancel()
  }

  private func acceptConnection() {
    let clientFD = Darwin.accept(socketFD, nil, nil)
    guard clientFD >= 0 else {
      if errno != EAGAIN && errno != EINTR {
        finish(.failure(systemCallError("accept")))
      }
      return
    }

    defer {
      close(clientFD)
    }

    var buffer = [UInt8](repeating: 0, count: 16_384)
    let count = recv(clientFD, &buffer, buffer.count - 1, 0)
    guard count > 0 else {
      sendResponse(
        status: "400 Bad Request",
        body: "Vela could not read the OAuth callback.",
        to: clientFD
      )
      return
    }

    let request = String(decoding: buffer[..<count], as: UTF8.self)
    guard
      let requestLine = request.split(separator: "\r\n", maxSplits: 1).first,
      let target = requestLine.split(separator: " ").dropFirst().first,
      let components = URLComponents(
        string: "http://\(Self.host):\(Self.port)\(target)"
      ),
      components.path == Self.path
    else {
      sendResponse(
        status: "404 Not Found",
        body: "This local endpoint is only used for Vela OAuth callbacks.",
        to: clientFD
      )
      return
    }

    let callbackURL = components.string ?? Self.redirectURI
    sendResponse(
      status: "200 OK",
      body: "Authentication complete. You can close this tab and return to Vela.",
      to: clientFD
    )
    finish(.success(callbackURL))
  }

  private func sendResponse(status: String, body: String, to clientFD: Int32) {
    let html = """
      <!doctype html>
      <html>
        <head><meta charset="utf-8"><title>Vela</title></head>
        <body><p>\(body)</p></body>
      </html>
      """
    let response = """
      HTTP/1.1 \(status)\r
      Content-Type: text/html; charset=utf-8\r
      Content-Length: \(html.utf8.count)\r
      Connection: close\r
      Cache-Control: no-store\r
      \r
      \(html)
      """

    response.withCString { pointer in
      _ = Darwin.send(clientFD, pointer, strlen(pointer), 0)
    }
  }

  private func finish(_ result: Result<String, Error>) {
    guard let callback else {
      return
    }

    stop()
    DispatchQueue.main.async {
      callback(result)
    }
  }

  private func systemCallError(_ name: String) -> OAuthLoopbackServerError {
    OAuthLoopbackServerError.systemCall(name: name, code: errno)
  }
}
