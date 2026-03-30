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
        static let lastSelectedProjectID = "gitlab.lastSelectedProjectID"
        static let recentProjectIDs = "gitlab.recentProjectIDs"
        static let recentIssueIDs = "gitlab.recentIssueIDs"
    }

    private let defaults: UserDefaults
    private let cloudStore: NSUbiquitousKeyValueStore
    private var cancellables = Set<AnyCancellable>()

    @Published var gitLabBaseURL: String
    @Published var oauthClientID: String
    @Published private(set) var lastSelectedProjectID: Int?
    @Published private(set) var recentProjectIDs: [Int]
    @Published private(set) var recentIssueIDs: [Int]

    init(
        defaults: UserDefaults = .standard,
        cloudStore: NSUbiquitousKeyValueStore = .default
    ) {
        self.defaults = defaults
        self.cloudStore = cloudStore

        let localBaseURL = defaults.string(forKey: Keys.gitLabBaseURL) ?? ""
        let localClientID = defaults.string(forKey: Keys.oauthClientID) ?? ""
        let localLastProjectID = defaults.object(forKey: Keys.lastSelectedProjectID) as? Int
        let localRecentProjectIDs = defaults.array(forKey: Keys.recentProjectIDs) as? [Int] ?? []
        let localRecentIssueIDs = defaults.array(forKey: Keys.recentIssueIDs) as? [Int] ?? []
        let remoteBaseURL = cloudStore.string(forKey: Keys.gitLabBaseURL) ?? ""
        let remoteClientID = cloudStore.string(forKey: Keys.oauthClientID) ?? ""
        let remoteLastProjectID = cloudStore.object(forKey: Keys.lastSelectedProjectID) as? Int
        let remoteRecentProjectIDs = cloudStore.array(forKey: Keys.recentProjectIDs) as? [Int] ?? []
        let remoteRecentIssueIDs = cloudStore.array(forKey: Keys.recentIssueIDs) as? [Int] ?? []

        gitLabBaseURL = remoteBaseURL.isEmpty ? localBaseURL : remoteBaseURL
        oauthClientID = remoteClientID.isEmpty ? localClientID : remoteClientID
        lastSelectedProjectID = remoteLastProjectID ?? localLastProjectID
        recentProjectIDs = remoteRecentProjectIDs.isEmpty ? localRecentProjectIDs : remoteRecentProjectIDs
        recentIssueIDs = remoteRecentIssueIDs.isEmpty ? localRecentIssueIDs : remoteRecentIssueIDs

        if !gitLabBaseURL.isEmpty || !oauthClientID.isEmpty || lastSelectedProjectID != nil || !recentProjectIDs.isEmpty || !recentIssueIDs.isEmpty {
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
        defaults.set(lastSelectedProjectID, forKey: Keys.lastSelectedProjectID)
        defaults.set(recentProjectIDs, forKey: Keys.recentProjectIDs)
        defaults.set(recentIssueIDs, forKey: Keys.recentIssueIDs)

        cloudStore.set(normalizedBaseURLString, forKey: Keys.gitLabBaseURL)
        cloudStore.set(normalizedClientID, forKey: Keys.oauthClientID)
        cloudStore.set(lastSelectedProjectID, forKey: Keys.lastSelectedProjectID)
        cloudStore.set(recentProjectIDs, forKey: Keys.recentProjectIDs)
        cloudStore.set(recentIssueIDs, forKey: Keys.recentIssueIDs)
        cloudStore.synchronize()
    }

    func rememberSelectedProject(id: Int) {
        lastSelectedProjectID = id
        recentProjectIDs = [id] + recentProjectIDs.filter { $0 != id }
        recentProjectIDs = Array(recentProjectIDs.prefix(5))
        save()
    }

    func rememberUsedIssue(id: Int) {
        recentIssueIDs = [id] + recentIssueIDs.filter { $0 != id }
        recentIssueIDs = Array(recentIssueIDs.prefix(5))
        save()
    }

    private func handleCloudStoreChange(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
        else {
            applyCloudValues()
            return
        }

        if changedKeys.contains(Keys.gitLabBaseURL)
            || changedKeys.contains(Keys.oauthClientID)
            || changedKeys.contains(Keys.lastSelectedProjectID)
            || changedKeys.contains(Keys.recentProjectIDs)
            || changedKeys.contains(Keys.recentIssueIDs) {
            applyCloudValues()
        }
    }

    private func applyCloudValues() {
        let remoteBaseURL = cloudStore.string(forKey: Keys.gitLabBaseURL) ?? ""
        let remoteClientID = cloudStore.string(forKey: Keys.oauthClientID) ?? ""
        let remoteLastProjectID = cloudStore.object(forKey: Keys.lastSelectedProjectID) as? Int
        let remoteRecentProjectIDs = cloudStore.array(forKey: Keys.recentProjectIDs) as? [Int] ?? []
        let remoteRecentIssueIDs = cloudStore.array(forKey: Keys.recentIssueIDs) as? [Int] ?? []

        if gitLabBaseURL != remoteBaseURL {
            gitLabBaseURL = remoteBaseURL
        }

        if oauthClientID != remoteClientID {
            oauthClientID = remoteClientID
        }

        if lastSelectedProjectID != remoteLastProjectID {
            lastSelectedProjectID = remoteLastProjectID
        }

        if recentProjectIDs != remoteRecentProjectIDs {
            recentProjectIDs = remoteRecentProjectIDs
        }

        if recentIssueIDs != remoteRecentIssueIDs {
            recentIssueIDs = remoteRecentIssueIDs
        }

        defaults.set(remoteBaseURL, forKey: Keys.gitLabBaseURL)
        defaults.set(remoteClientID, forKey: Keys.oauthClientID)
        defaults.set(remoteLastProjectID, forKey: Keys.lastSelectedProjectID)
        defaults.set(remoteRecentProjectIDs, forKey: Keys.recentProjectIDs)
        defaults.set(remoteRecentIssueIDs, forKey: Keys.recentIssueIDs)
    }
}
