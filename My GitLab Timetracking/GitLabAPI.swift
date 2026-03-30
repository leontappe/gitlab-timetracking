//
//  GitLabAPI.swift
//  My GitLab Timetracking
//

import Foundation

struct AuthorizedGitLabConfiguration {
    let baseURL: URL
    let accessToken: String
}

struct GitLabIssue: Codable, Identifiable, Hashable {
    struct References: Codable, Hashable {
        let short: String
    }

    let id: Int
    let iid: Int
    let projectID: Int
    let title: String
    let webURL: URL
    let references: References

    enum CodingKeys: String, CodingKey {
        case id
        case iid
        case title
        case references
        case projectID = "project_id"
        case webURL = "web_url"
    }
}

struct GitLabUser: Codable, Hashable {
    let id: Int
    let username: String
    let name: String
    let webURL: URL

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case name
        case webURL = "web_url"
    }
}

enum GitLabAPIError: LocalizedError {
    case missingConfiguration
    case notAuthenticated
    case invalidResponse
    case serverError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Configure the GitLab base URL and OAuth application ID first."
        case .notAuthenticated:
            return "Connect your GitLab account first."
        case .invalidResponse:
            return "GitLab returned an unexpected response."
        case let .serverError(statusCode, message):
            return "GitLab request failed (\(statusCode)): \(message)"
        }
    }
}

actor GitLabAPI {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchAssignedIssues(configuration: AuthorizedGitLabConfiguration) async throws -> [GitLabIssue] {
        let request = try makeRequest(
            configuration: configuration,
            path: "/api/v4/issues",
            queryItems: [
                URLQueryItem(name: "scope", value: "assigned_to_me"),
                URLQueryItem(name: "state", value: "opened"),
                URLQueryItem(name: "per_page", value: "100")
            ]
        )

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode([GitLabIssue].self, from: data)
    }

    func fetchCurrentUser(configuration: AuthorizedGitLabConfiguration) async throws -> GitLabUser {
        let request = try makeRequest(
            configuration: configuration,
            path: "/api/v4/user"
        )

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(GitLabUser.self, from: data)
    }

    func addSpentTime(issue: GitLabIssue, duration: String, configuration: AuthorizedGitLabConfiguration) async throws {
        let path = "/api/v4/projects/\(issue.projectID)/issues/\(issue.iid)/add_spent_time"
        let request = try makeRequest(
            configuration: configuration,
            path: path,
            method: "POST",
            queryItems: [URLQueryItem(name: "duration", value: duration)]
        )

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
    }

    private func makeRequest(
        configuration: AuthorizedGitLabConfiguration,
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = []
    ) throws -> URLRequest {
        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        components?.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components?.url else {
            throw GitLabAPIError.missingConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(configuration.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitLabAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GitLabAPIError.serverError(statusCode: httpResponse.statusCode, message: message)
        }
    }
}
