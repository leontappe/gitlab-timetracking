//
//  ProjectManager.swift
//  My GitLab Timetracking
//

import Foundation
import Combine

@MainActor
final class ProjectManager: ObservableObject {
    private let authManager: GitLabAuthManager
    private let settings: AppSettings
    private let api = GitLabAPI()
    private let cacheStore = ProjectCacheStore()

    @Published var projects: [GitLabProject] = []
    @Published var selectedProjectID: Int?
    @Published var isLoadingProjects = false
    @Published var isCreatingIssue = false
    @Published var projectErrorMessage: String?
    @Published var creationMessage: String?
    @Published private(set) var lastProjectsRefreshAt: Date?

    init(authManager: GitLabAuthManager) {
        self.authManager = authManager
        self.settings = authManager.settings
        loadCachedProjects()
        applyRememberedSelection()
    }

    var orderedProjects: [GitLabProject] {
        let recentIDs = settings.recentProjectIDs
        let recentProjects = recentIDs.compactMap { id in
            projects.first(where: { $0.id == id })
        }

        let remainingProjects = projects
            .filter { project in !recentIDs.contains(project.id) }
            .sorted {
                $0.nameWithNamespace.localizedCaseInsensitiveCompare($1.nameWithNamespace) == .orderedAscending
            }

        return recentProjects + remainingProjects
    }

    func loadProjectsIfNeeded() async {
        if projects.isEmpty {
            loadCachedProjects()
        }

        if projects.isEmpty && authManager.isAuthenticated {
            await refreshProjects()
        }
    }

    func loadProjectsOnDemand() {
        guard projects.isEmpty, authManager.isAuthenticated, !isLoadingProjects else {
            return
        }

        Task {
            await refreshProjects()
        }
    }

    func refreshProjects() async {
        guard authManager.settings.isConfigured else {
            projects = []
            selectedProjectID = nil
            projectErrorMessage = nil
            return
        }

        guard authManager.isAuthenticated else {
            projectErrorMessage = nil
            return
        }

        isLoadingProjects = true
        projectErrorMessage = nil

        do {
            let configuration = try await authManager.currentAuthorization()
            let projects = try await api.fetchProjects(configuration: configuration)
            self.projects = projects
            lastProjectsRefreshAt = Date()
            cacheStore.save(projects: projects, baseURL: settings.normalizedBaseURLString, updatedAt: lastProjectsRefreshAt ?? Date())
            applyRememberedSelection()
            creationMessage = "Project list refreshed."
        } catch {
            projectErrorMessage = error.localizedDescription
        }

        isLoadingProjects = false
    }

    func selectProject(id: Int?) {
        selectedProjectID = id

        guard let id else {
            return
        }

        settings.rememberSelectedProject(id: id)
    }

    func createIssue(title: String, description: String) async -> GitLabCreatedIssue? {
        guard let projectID = selectedProjectID else {
            projectErrorMessage = "Select a project first."
            return nil
        }

        isCreatingIssue = true
        projectErrorMessage = nil
        creationMessage = nil

        defer {
            isCreatingIssue = false
        }

        do {
            let configuration = try await authManager.currentAuthorization()
            let issue = try await api.createIssue(
                projectID: projectID,
                title: title,
                description: description.isEmpty ? nil : description,
                configuration: configuration
            )
            settings.rememberSelectedProject(id: projectID)
            creationMessage = "Created \(issue.reference)."
            return issue
        } catch {
            projectErrorMessage = error.localizedDescription
            return nil
        }
    }

    func handleSettingsSaved() {
        loadCachedProjects()
        applyRememberedSelection()
    }

    func clearProjectState() {
        selectedProjectID = nil
        projectErrorMessage = nil
        creationMessage = nil
    }

    private func loadCachedProjects() {
        guard !settings.normalizedBaseURLString.isEmpty else {
            projects = []
            lastProjectsRefreshAt = nil
            return
        }

        guard let cache = cacheStore.load(for: settings.normalizedBaseURLString) else {
            projects = []
            lastProjectsRefreshAt = nil
            return
        }

        projects = cache.projects
        lastProjectsRefreshAt = cache.updatedAt
    }

    private func applyRememberedSelection() {
        if
            let lastSelectedProjectID = settings.lastSelectedProjectID,
            projects.contains(where: { $0.id == lastSelectedProjectID }) {
            selectedProjectID = lastSelectedProjectID
        } else {
            selectedProjectID = orderedProjects.first?.id
        }
    }
}
