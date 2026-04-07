//
//  GitLabAuthManager.swift
//  My GitLab Timetracking
//

import Foundation
import AppKit
import CryptoKit

struct GitLabOAuthToken: Codable {
    let accessToken: String
    let tokenType: String
    let refreshToken: String
    let expiresIn: Int
    let createdAt: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case createdAt = "created_at"
    }

    var expirationDate: Date {
        Date(timeIntervalSince1970: TimeInterval(createdAt + expiresIn))
    }

    var needsRefresh: Bool {
        expirationDate.timeIntervalSinceNow < 60
    }
}

enum GitLabAuthError: LocalizedError {
    case callbackStateMismatch
    case missingAuthorizationCode

    var errorDescription: String? {
        switch self {
        case .callbackStateMismatch:
            return "GitLab OAuth state validation failed."
        case .missingAuthorizationCode:
            return "GitLab did not return an authorization code."
        }
    }
}

@MainActor
@Observable
final class GitLabAuthManager {
    static let redirectURI = URL(string: "http://127.0.0.1:45873/oauth/callback")!
    static let redirectPort: UInt16 = 45873

    private(set) var currentUser: GitLabUser?
    private(set) var isAuthenticating = false
    private(set) var authError: String?

    let settings: AppSettings

    private let api = GitLabAPI()
    private let keychain = KeychainStore()
    private var token: GitLabOAuthToken?

    init(settings: AppSettings) {
        self.settings = settings
        token = loadToken()

        if token != nil {
            Task {
                await refreshCurrentUser()
            }
        }
    }

    var isAuthenticated: Bool {
        token != nil
    }

    func signIn() async {
        guard let configuration = settings.configuration else {
            authError = GitLabAPIError.missingConfiguration.localizedDescription
            return
        }

        isAuthenticating = true
        authError = nil

        do {
            let state = Self.randomURLSafeString(length: 32)
            let codeVerifier = Self.randomCodeVerifier()
            let codeChallenge = Self.codeChallenge(for: codeVerifier)

            let callbackServer = OAuthCallbackServer(port: Self.redirectPort)
            let callbackTask = Task {
                try await callbackServer.waitForCallback()
            }

            let authURL = try makeAuthorizationURL(
                configuration: configuration,
                state: state,
                codeChallenge: codeChallenge
            )

            NSWorkspace.shared.open(authURL)

            let callbackURL = try await callbackTask.value
            let queryItems = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let returnedState = queryItems.first(where: { $0.name == "state" })?.value
            let code = queryItems.first(where: { $0.name == "code" })?.value

            guard returnedState == state else {
                throw GitLabAuthError.callbackStateMismatch
            }

            guard let code, !code.isEmpty else {
                throw GitLabAuthError.missingAuthorizationCode
            }

            let token = try await exchangeCodeForToken(
                configuration: configuration,
                code: code,
                codeVerifier: codeVerifier
            )

            try saveToken(token)
            self.token = token
            try await refreshCurrentUser()
        } catch {
            authError = error.localizedDescription
        }

        isAuthenticating = false
    }

    func signOut() {
        token = nil
        currentUser = nil
        authError = nil
        keychain.delete(account: settings.normalizedBaseURLString)
    }

    func currentAuthorization() async throws -> AuthorizedGitLabConfiguration {
        guard let configuration = settings.configuration else {
            throw GitLabAPIError.missingConfiguration
        }

        guard let token = try await validToken(configuration: configuration) else {
            throw GitLabAPIError.notAuthenticated
        }

        return AuthorizedGitLabConfiguration(
            baseURL: configuration.baseURL,
            accessToken: token.accessToken
        )
    }

    func refreshCurrentUser() async {
        do {
            guard let authorization = try? await currentAuthorization() else {
                currentUser = nil
                return
            }

            currentUser = try await api.fetchCurrentUser(configuration: authorization)
            authError = nil
        } catch {
            authError = error.localizedDescription
        }
    }

    private func validToken(configuration: GitLabConfiguration) async throws -> GitLabOAuthToken? {
        guard let token else {
            return nil
        }

        guard token.needsRefresh else {
            return token
        }

        let refreshed = try await refreshToken(configuration: configuration, refreshToken: token.refreshToken)
        try saveToken(refreshed)
        self.token = refreshed
        return refreshed
    }

    private func makeAuthorizationURL(
        configuration: GitLabConfiguration,
        state: String,
        codeChallenge: String
    ) throws -> URL {
        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)
        components?.path = configuration.baseURL.path + "/oauth/authorize"
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: "api"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        guard let url = components?.url else {
            throw GitLabAPIError.missingConfiguration
        }

        return url
    }

    private func exchangeCodeForToken(
        configuration: GitLabConfiguration,
        code: String,
        codeVerifier: String
    ) async throws -> GitLabOAuthToken {
        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)
        components?.path = configuration.baseURL.path + "/oauth/token"

        guard let url = components?.url else {
            throw GitLabAPIError.missingConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncodedData([
            "client_id": configuration.clientID,
            "code": code,
            "grant_type": "authorization_code",
            "redirect_uri": Self.redirectURI.absoluteString,
            "code_verifier": codeVerifier
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateOAuthResponse(response: response, data: data)
        return try JSONDecoder().decode(GitLabOAuthToken.self, from: data)
    }

    private func refreshToken(
        configuration: GitLabConfiguration,
        refreshToken: String
    ) async throws -> GitLabOAuthToken {
        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)
        components?.path = configuration.baseURL.path + "/oauth/token"

        guard let url = components?.url else {
            throw GitLabAPIError.missingConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncodedData([
            "client_id": configuration.clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
            "redirect_uri": Self.redirectURI.absoluteString
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateOAuthResponse(response: response, data: data)
        return try JSONDecoder().decode(GitLabOAuthToken.self, from: data)
    }

    private func loadToken() -> GitLabOAuthToken? {
        guard !settings.normalizedBaseURLString.isEmpty else {
            return nil
        }

        guard let data = keychain.load(account: settings.normalizedBaseURLString) else {
            return nil
        }

        return try? JSONDecoder().decode(GitLabOAuthToken.self, from: data)
    }

    private func saveToken(_ token: GitLabOAuthToken) throws {
        let data = try JSONEncoder().encode(token)
        try keychain.save(data, account: settings.normalizedBaseURLString)
    }

    private func validateOAuthResponse(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitLabAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GitLabAPIError.serverError(statusCode: httpResponse.statusCode, message: message)
        }
    }

    private static func randomCodeVerifier() -> String {
        randomURLSafeString(length: 64)
    }

    private static func randomURLSafeString(length: Int) -> String {
        let bytes = (0..<length).map { _ in UInt8.random(in: 0...255) }
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formEncodedData(_ fields: [String: String]) -> Data? {
        let value = fields
            .map { key, value in
                "\(percentEncode(key))=\(percentEncode(value))"
            }
            .sorted()
            .joined(separator: "&")

        return value.data(using: .utf8)
    }

    private static func percentEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&="))) ?? value
    }
}
