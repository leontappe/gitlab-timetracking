//
//  AppSettings.swift
//  My GitLab Timetracking
//

import Foundation
import Combine

struct GitLabConfiguration {
    let baseURL: URL
    let personalAccessToken: String
}

final class AppSettings: ObservableObject {
    private enum Keys {
        static let gitLabBaseURL = "gitlab.baseURL"
        static let personalAccessToken = "gitlab.personalAccessToken"
    }

    @Published var gitLabBaseURL: String
    @Published var personalAccessToken: String

    init(defaults: UserDefaults = .standard) {
        gitLabBaseURL = defaults.string(forKey: Keys.gitLabBaseURL) ?? ""
        personalAccessToken = defaults.string(forKey: Keys.personalAccessToken) ?? ""
    }

    var isConfigured: Bool {
        !normalizedBaseURLString.isEmpty && !personalAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            personalAccessToken: personalAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(normalizedBaseURLString, forKey: Keys.gitLabBaseURL)
        defaults.set(personalAccessToken.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.personalAccessToken)
    }
}
