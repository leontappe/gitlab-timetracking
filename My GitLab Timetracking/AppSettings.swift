//
//  AppSettings.swift
//  My GitLab Timetracking
//

import Foundation
import Combine

struct GitLabConfiguration {
    let baseURL: URL
    let clientID: String
}

final class AppSettings: ObservableObject {
    private enum Keys {
        static let gitLabBaseURL = "gitlab.baseURL"
        static let oauthClientID = "gitlab.oauthClientID"
    }

    @Published var gitLabBaseURL: String
    @Published var oauthClientID: String

    init(defaults: UserDefaults = .standard) {
        gitLabBaseURL = defaults.string(forKey: Keys.gitLabBaseURL) ?? ""
        oauthClientID = defaults.string(forKey: Keys.oauthClientID) ?? ""
    }

    var isConfigured: Bool {
        !normalizedBaseURLString.isEmpty && !oauthClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var normalizedBaseURLString: String {
        gitLabBaseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    var normalizedBaseURL: URL? {
        URL(string: normalizedBaseURLString)
    }

    var configuration: GitLabConfiguration? {
        guard
            isConfigured,
            let baseURL = normalizedBaseURL
        else {
            return nil
        }

        return GitLabConfiguration(
            baseURL: baseURL,
            clientID: oauthClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(normalizedBaseURLString, forKey: Keys.gitLabBaseURL)
        defaults.set(oauthClientID.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.oauthClientID)
    }
}
