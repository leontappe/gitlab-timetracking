//
//  IssueStatusManager.swift
//  My GitLab Timetracking
//

import Foundation
import Combine

@MainActor
final class IssueStatusManager: ObservableObject {
    @Published private(set) var statuses: [String] = ["doing", "todo", "review", "blocked", "done"]
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let authManager: GitLabAuthManager
    private let api = GitLabAPI()
    private var cancellables = Set<AnyCancellable>()

    init(authManager: GitLabAuthManager) {
        self.authManager = authManager

        authManager.$currentUser
            .sink { [weak self] currentUser in
                guard let self else { return }
                guard currentUser != nil else { return }
                self.loadStatusesIfNeeded(forceRefresh: true)
            }
            .store(in: &cancellables)

        loadStatusesIfNeeded(forceRefresh: false)
    }

    func loadStatusesIfNeeded(forceRefresh: Bool) {
        guard authManager.isAuthenticated, !isLoading else {
            return
        }

        if !forceRefresh, !statuses.isEmpty {
            return
        }

        Task {
            await refreshStatuses()
        }
    }

    func refreshStatuses() async {
        guard authManager.isAuthenticated else {
            return
        }

        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            let configuration = try await authManager.currentAuthorization()
            let fetched = try await api.fetchAllowedIssueStatuses(configuration: configuration)
            if !fetched.isEmpty {
                statuses = fetched
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
