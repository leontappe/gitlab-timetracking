//
//  OAuthCallbackServer.swift
//  My GitLab Timetracking
//

import Foundation
import Network

enum OAuthCallbackError: LocalizedError {
    case timeout
    case portUnavailable(port: UInt16, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .timeout:
            return "GitLab did not redirect back to the app in time. Close the browser tab and try again."
        case let .portUnavailable(port, underlying):
            return "Couldn’t listen for GitLab’s redirect on port \(port) (\(underlying.localizedDescription)). Make sure no other instance of the app is running."
        }
    }
}

final class OAuthCallbackServer {
    private let port: UInt16
    private let timeout: Duration

    init(port: UInt16, timeout: Duration = .seconds(120)) {
        self.port = port
        self.timeout = timeout
    }

    func waitForCallback() async throws -> URL {
        let listener: NWListener
        do {
            listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            throw OAuthCallbackError.portUnavailable(port: port, underlying: error)
        }
        let queue = DispatchQueue(label: "OAuthCallbackServer")

        return try await withThrowingTaskGroup(of: URL.self) { group in
            group.addTask {
                try await self.acceptConnection(listener: listener, queue: queue)
            }

            group.addTask {
                try await Task.sleep(for: self.timeout)
                throw OAuthCallbackError.timeout
            }

            defer {
                listener.cancel()
                group.cancelAll()
            }

            let result = try await group.next()!
            return result
        }
    }

    private func acceptConnection(listener: NWListener, queue: DispatchQueue) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                var hasResumed = false

                func finish(_ result: Result<URL, Error>) {
                    guard !hasResumed else { return }
                    hasResumed = true
                    continuation.resume(with: result)
                }

                listener.stateUpdateHandler = { state in
                    switch state {
                    case .failed(let error):
                        finish(.failure(error))
                    case .cancelled:
                        finish(.failure(CancellationError()))
                    default:
                        break
                    }
                }

                listener.newConnectionHandler = { connection in
                    connection.start(queue: queue)
                    self.receiveFullRequest(connection: connection) { result in
                        switch result {
                        case .success(let data):
                            guard
                                let request = String(data: data, encoding: .utf8),
                                let requestLine = request.split(separator: "\r\n").first,
                                let target = requestLine.split(separator: " ").dropFirst().first,
                                let callbackURL = URL(string: "http://127.0.0.1:\(self.port)\(target)")
                            else {
                                connection.cancel()
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
                                connection.cancel()
                                finish(.success(callbackURL))
                            })

                        case .failure(let error):
                            connection.cancel()
                            finish(.failure(error))
                        }
                    }
                }

                listener.start(queue: queue)
            }
        } onCancel: {
            listener.cancel()
        }
    }

    private func receiveFullRequest(
        connection: NWConnection,
        buffer: Data = Data(),
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, isComplete, error in
            if let error {
                completion(.failure(error))
                return
            }

            var accumulated = buffer
            if let data {
                accumulated.append(data)
            }

            if let text = String(data: accumulated, encoding: .utf8), text.contains("\r\n\r\n") {
                completion(.success(accumulated))
                return
            }

            if isComplete {
                completion(.success(accumulated))
                return
            }

            self.receiveFullRequest(connection: connection, buffer: accumulated, completion: completion)
        }
    }
}
