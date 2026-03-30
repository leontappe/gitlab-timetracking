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

    private let defaults: UserDefaults
    private let cloudStore: NSUbiquitousKeyValueStore
    private var cancellables = Set<AnyCancellable>()

    @Published var gitLabBaseURL: String
    @Published var oauthClientID: String

    init(
        defaults: UserDefaults = .standard,
        cloudStore: NSUbiquitousKeyValueStore = .default
    ) {
        self.defaults = defaults
        self.cloudStore = cloudStore

        let localBaseURL = defaults.string(forKey: Keys.gitLabBaseURL) ?? ""
        let localClientID = defaults.string(forKey: Keys.oauthClientID) ?? ""
        let remoteBaseURL = cloudStore.string(forKey: Keys.gitLabBaseURL) ?? ""
        let remoteClientID = cloudStore.string(forKey: Keys.oauthClientID) ?? ""

        gitLabBaseURL = remoteBaseURL.isEmpty ? localBaseURL : remoteBaseURL
        oauthClientID = remoteClientID.isEmpty ? localClientID : remoteClientID

        if !gitLabBaseURL.isEmpty || !oauthClientID.isEmpty {
            save()
        }

        NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)
            .sink { [weak self] notification in
                self?.handleCloudStoreChange(notification)
            }
            .store(in: &cancellables)

        cloudStore.synchronize()
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

    func save() {
        let normalizedClientID = oauthClientID.trimmingCharacters(in: .whitespacesAndNewlines)

        defaults.set(normalizedBaseURLString, forKey: Keys.gitLabBaseURL)
        defaults.set(normalizedClientID, forKey: Keys.oauthClientID)

        cloudStore.set(normalizedBaseURLString, forKey: Keys.gitLabBaseURL)
        cloudStore.set(normalizedClientID, forKey: Keys.oauthClientID)
        cloudStore.synchronize()
    }

    private func handleCloudStoreChange(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
        else {
            applyCloudValues()
            return
        }

        if changedKeys.contains(Keys.gitLabBaseURL) || changedKeys.contains(Keys.oauthClientID) {
            applyCloudValues()
        }
    }

    private func applyCloudValues() {
        let remoteBaseURL = cloudStore.string(forKey: Keys.gitLabBaseURL) ?? ""
        let remoteClientID = cloudStore.string(forKey: Keys.oauthClientID) ?? ""

        if gitLabBaseURL != remoteBaseURL {
            gitLabBaseURL = remoteBaseURL
        }

        if oauthClientID != remoteClientID {
            oauthClientID = remoteClientID
        }

        defaults.set(remoteBaseURL, forKey: Keys.gitLabBaseURL)
        defaults.set(remoteClientID, forKey: Keys.oauthClientID)
    }
}
