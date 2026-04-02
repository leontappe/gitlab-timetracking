//
//  AppSettings.swift
//  My GitLab Timetracking
//

import Foundation
import Combine

struct GitLabConfiguration {
    let baseURL: URL
    let clientID: String
    let groupPaths: [String]
}

final class AppSettings: ObservableObject {
    private enum Keys {
        static let gitLabBaseURL = "gitlab.baseURL"
        static let oauthClientID = "gitlab.oauthClientID"
        static let gitLabGroupPath = "gitlab.groupPath"
        static let gitLabGroupPaths = "gitlab.groupPaths"
        static let showTrackedTimeInMenuBar = "ui.showTrackedTimeInMenuBar"
        static let showIssueReferenceInMenuBar = "ui.showIssueReferenceInMenuBar"
        static let lastSelectedProjectID = "gitlab.lastSelectedProjectID"
        static let recentProjectIDs = "gitlab.recentProjectIDs"
        static let recentIssueIDs = "gitlab.recentIssueIDs"
    }

    private let defaults: UserDefaults
    private let cloudStore: NSUbiquitousKeyValueStore
    private var cancellables = Set<AnyCancellable>()

    @Published var gitLabBaseURL: String
    @Published var oauthClientID: String
    @Published var showTrackedTimeInMenuBar: Bool
    @Published var showIssueReferenceInMenuBar: Bool
    @Published private(set) var gitLabGroupPaths: [String]
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
        let localGroupPath = defaults.string(forKey: Keys.gitLabGroupPath) ?? ""
        let localGroupPaths = defaults.array(forKey: Keys.gitLabGroupPaths) as? [String] ?? []
        let localShowTrackedTimeInMenuBar = defaults.object(forKey: Keys.showTrackedTimeInMenuBar) as? Bool ?? false
        let localShowIssueReferenceInMenuBar = defaults.object(forKey: Keys.showIssueReferenceInMenuBar) as? Bool ?? true
        let localLastProjectID = defaults.object(forKey: Keys.lastSelectedProjectID) as? Int
        let localRecentProjectIDs = defaults.array(forKey: Keys.recentProjectIDs) as? [Int] ?? []
        let localRecentIssueIDs = defaults.array(forKey: Keys.recentIssueIDs) as? [Int] ?? []
        let remoteBaseURL = cloudStore.string(forKey: Keys.gitLabBaseURL) ?? ""
        let remoteClientID = cloudStore.string(forKey: Keys.oauthClientID) ?? ""
        let remoteGroupPath = cloudStore.string(forKey: Keys.gitLabGroupPath) ?? ""
        let remoteGroupPaths = cloudStore.array(forKey: Keys.gitLabGroupPaths) as? [String] ?? []
        let remoteShowTrackedTimeInMenuBar = cloudStore.object(forKey: Keys.showTrackedTimeInMenuBar) as? Bool
        let remoteShowIssueReferenceInMenuBar = cloudStore.object(forKey: Keys.showIssueReferenceInMenuBar) as? Bool
        let remoteLastProjectID = cloudStore.object(forKey: Keys.lastSelectedProjectID) as? Int
        let remoteRecentProjectIDs = cloudStore.array(forKey: Keys.recentProjectIDs) as? [Int] ?? []
        let remoteRecentIssueIDs = cloudStore.array(forKey: Keys.recentIssueIDs) as? [Int] ?? []

        gitLabBaseURL = remoteBaseURL.isEmpty ? localBaseURL : remoteBaseURL
        oauthClientID = remoteClientID.isEmpty ? localClientID : remoteClientID
        showTrackedTimeInMenuBar = remoteShowTrackedTimeInMenuBar ?? localShowTrackedTimeInMenuBar
        showIssueReferenceInMenuBar = remoteShowIssueReferenceInMenuBar ?? localShowIssueReferenceInMenuBar
        gitLabGroupPaths = Self.resolveGroupPaths(
            primary: remoteGroupPaths,
            fallbackArray: localGroupPaths,
            fallbackSingle: remoteGroupPath.isEmpty ? localGroupPath : remoteGroupPath
        )
        lastSelectedProjectID = remoteLastProjectID ?? localLastProjectID
        recentProjectIDs = remoteRecentProjectIDs.isEmpty ? localRecentProjectIDs : remoteRecentProjectIDs
        recentIssueIDs = remoteRecentIssueIDs.isEmpty ? localRecentIssueIDs : remoteRecentIssueIDs

        if !gitLabBaseURL.isEmpty || !oauthClientID.isEmpty || showTrackedTimeInMenuBar || !showIssueReferenceInMenuBar || !gitLabGroupPaths.isEmpty || lastSelectedProjectID != nil || !recentProjectIDs.isEmpty || !recentIssueIDs.isEmpty {
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

    var normalizedGroupPaths: [String] {
        gitLabGroupPaths
            .map { groupPath in
                groupPath
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
            .filter { !$0.isEmpty }
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
            clientID: oauthClientID.trimmingCharacters(in: .whitespacesAndNewlines),
            groupPaths: normalizedGroupPaths
        )
    }

    func save() {
        let normalizedClientID = oauthClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedGroupPaths = normalizedGroupPaths

        defaults.set(normalizedBaseURLString, forKey: Keys.gitLabBaseURL)
        defaults.set(normalizedClientID, forKey: Keys.oauthClientID)
        defaults.set(showTrackedTimeInMenuBar, forKey: Keys.showTrackedTimeInMenuBar)
        defaults.set(showIssueReferenceInMenuBar, forKey: Keys.showIssueReferenceInMenuBar)
        defaults.set(normalizedGroupPaths, forKey: Keys.gitLabGroupPaths)
        defaults.set(normalizedGroupPaths.first ?? "", forKey: Keys.gitLabGroupPath)
        defaults.set(lastSelectedProjectID, forKey: Keys.lastSelectedProjectID)
        defaults.set(recentProjectIDs, forKey: Keys.recentProjectIDs)
        defaults.set(recentIssueIDs, forKey: Keys.recentIssueIDs)

        cloudStore.set(normalizedBaseURLString, forKey: Keys.gitLabBaseURL)
        cloudStore.set(normalizedClientID, forKey: Keys.oauthClientID)
        cloudStore.set(showTrackedTimeInMenuBar, forKey: Keys.showTrackedTimeInMenuBar)
        cloudStore.set(showIssueReferenceInMenuBar, forKey: Keys.showIssueReferenceInMenuBar)
        cloudStore.set(normalizedGroupPaths, forKey: Keys.gitLabGroupPaths)
        cloudStore.set(normalizedGroupPaths.first ?? "", forKey: Keys.gitLabGroupPath)
        cloudStore.set(lastSelectedProjectID, forKey: Keys.lastSelectedProjectID)
        cloudStore.set(recentProjectIDs, forKey: Keys.recentProjectIDs)
        cloudStore.set(recentIssueIDs, forKey: Keys.recentIssueIDs)
        cloudStore.synchronize()
    }

    func addSelectedGroup(path: String) {
        let normalizedPath = Self.normalizeGroupPath(path)
        guard !normalizedPath.isEmpty, !gitLabGroupPaths.contains(normalizedPath) else {
            return
        }

        gitLabGroupPaths = (gitLabGroupPaths + [normalizedPath]).sorted()
        save()
    }

    func removeSelectedGroup(path: String) {
        let normalizedPath = Self.normalizeGroupPath(path)
        gitLabGroupPaths.removeAll { $0 == normalizedPath }
        save()
    }

    func clearSelectedGroups() {
        gitLabGroupPaths = []
        save()
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
            || changedKeys.contains(Keys.showTrackedTimeInMenuBar)
            || changedKeys.contains(Keys.showIssueReferenceInMenuBar)
            || changedKeys.contains(Keys.gitLabGroupPath)
            || changedKeys.contains(Keys.gitLabGroupPaths)
            || changedKeys.contains(Keys.lastSelectedProjectID)
            || changedKeys.contains(Keys.recentProjectIDs)
            || changedKeys.contains(Keys.recentIssueIDs) {
            applyCloudValues()
        }
    }

    private func applyCloudValues() {
        let remoteBaseURL = cloudStore.string(forKey: Keys.gitLabBaseURL) ?? ""
        let remoteClientID = cloudStore.string(forKey: Keys.oauthClientID) ?? ""
        let remoteShowTrackedTimeInMenuBar = cloudStore.object(forKey: Keys.showTrackedTimeInMenuBar) as? Bool ?? false
        let remoteShowIssueReferenceInMenuBar = cloudStore.object(forKey: Keys.showIssueReferenceInMenuBar) as? Bool ?? true
        let remoteGroupPath = cloudStore.string(forKey: Keys.gitLabGroupPath) ?? ""
        let remoteGroupPaths = cloudStore.array(forKey: Keys.gitLabGroupPaths) as? [String] ?? []
        let remoteLastProjectID = cloudStore.object(forKey: Keys.lastSelectedProjectID) as? Int
        let remoteRecentProjectIDs = cloudStore.array(forKey: Keys.recentProjectIDs) as? [Int] ?? []
        let remoteRecentIssueIDs = cloudStore.array(forKey: Keys.recentIssueIDs) as? [Int] ?? []

        if gitLabBaseURL != remoteBaseURL {
            gitLabBaseURL = remoteBaseURL
        }

        if oauthClientID != remoteClientID {
            oauthClientID = remoteClientID
        }

        if showTrackedTimeInMenuBar != remoteShowTrackedTimeInMenuBar {
            showTrackedTimeInMenuBar = remoteShowTrackedTimeInMenuBar
        }

        if showIssueReferenceInMenuBar != remoteShowIssueReferenceInMenuBar {
            showIssueReferenceInMenuBar = remoteShowIssueReferenceInMenuBar
        }

        let resolvedRemoteGroupPaths = Self.resolveGroupPaths(
            primary: remoteGroupPaths,
            fallbackArray: [],
            fallbackSingle: remoteGroupPath
        )
        if gitLabGroupPaths != resolvedRemoteGroupPaths {
            gitLabGroupPaths = resolvedRemoteGroupPaths
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
        defaults.set(remoteShowTrackedTimeInMenuBar, forKey: Keys.showTrackedTimeInMenuBar)
        defaults.set(remoteShowIssueReferenceInMenuBar, forKey: Keys.showIssueReferenceInMenuBar)
        defaults.set(resolvedRemoteGroupPaths, forKey: Keys.gitLabGroupPaths)
        defaults.set(remoteGroupPath, forKey: Keys.gitLabGroupPath)
        defaults.set(remoteLastProjectID, forKey: Keys.lastSelectedProjectID)
        defaults.set(remoteRecentProjectIDs, forKey: Keys.recentProjectIDs)
        defaults.set(remoteRecentIssueIDs, forKey: Keys.recentIssueIDs)
    }

    nonisolated private static func resolveGroupPaths(primary: [String], fallbackArray: [String], fallbackSingle: String) -> [String] {
        let combined = !primary.isEmpty ? primary : (!fallbackArray.isEmpty ? fallbackArray : [fallbackSingle])
        return combined
            .map(normalizeGroupPath)
            .filter { !$0.isEmpty }
            .uniquedAndSorted()
    }

    nonisolated private static func normalizeGroupPath(_ path: String) -> String {
        path
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

private extension Array where Element == String {
    func uniquedAndSorted() -> [String] {
        Array(Set(self)).sorted()
    }
}
