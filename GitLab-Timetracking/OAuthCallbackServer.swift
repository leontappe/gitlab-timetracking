//
//  OAuthCallbackServer.swift
//  My GitLab Timetracking
//

import Foundation
import Network

final class OAuthCallbackServer {
    private let port: UInt16

    init(port: UInt16) {
        self.port = port
    }

    func waitForCallback() async throws -> URL {
        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        let queue = DispatchQueue(label: "OAuthCallbackServer")

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false

            func finish(_ result: Result<URL, Error>) {
                guard !hasResumed else { return }
                hasResumed = true
                listener.cancel()
                continuation.resume(with: result)
            }

            listener.stateUpdateHandler = { state in
                if case let .failed(error) = state {
                    finish(.failure(error))
                }
            }

            listener.newConnectionHandler = { connection in
                connection.start(queue: queue)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, error in
                    defer {
                        connection.cancel()
                    }

                    if let error {
                        finish(.failure(error))
                        return
                    }

                    guard
                        let data,
                        let request = String(data: data, encoding: .utf8),
                        let requestLine = request.split(separator: "\r\n").first,
                        let target = requestLine.split(separator: " ").dropFirst().first,
                        let callbackURL = URL(string: "http://127.0.0.1:\(self.port)\(target)")
                    else {
                        finish(.failure(GitLabAPIError.invalidResponse))
                        return
                    }

                    let body = "<html><body><h1>You can return to the app.</h1></body></html>"
                    let response = """
                    HTTP/1.1 200 OK\r
                    Content-Type: text/html; charset=utf-8\r
                    Content-Length: \(body.utf8.count)\r
                    Connection: close\r
                    \r
                    \(body)
                    """
                    connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                        finish(.success(callbackURL))
                    })
                }
            }

            listener.start(queue: queue)
        }
    }
}
