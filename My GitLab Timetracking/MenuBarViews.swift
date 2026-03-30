//
//  MenuBarViews.swift
//  My GitLab Timetracking
//

import SwiftUI
import AppKit

struct MenuBarLabelView: View {
    @ObservedObject var tracker: TrackingManager

    var body: some View {
        if let issue = tracker.activeIssue, tracker.isTracking {
            Label(issue.references.short, systemImage: "timer")
        } else if tracker.activeIssue != nil {
            Label("Paused", systemImage: "pause.circle")
        } else {
            Label("GitLab", systemImage: "list.bullet.clipboard")
        }
    }
}

struct MenuBarContentView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var authManager: GitLabAuthManager
    @ObservedObject var projectManager: ProjectManager
    @ObservedObject var tracker: TrackingManager
    @State private var newIssueTitle = ""
    @State private var newIssueDescription = ""
    @State private var isCreateExpanded = false
    @State private var isProjectListExpanded = false
    @State private var projectSearch = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let session = tracker.activeSession {
                activeSection(session: session)
            }

            if let errorMessage = tracker.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text(tracker.infoMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            createIssueSection
            issuesSection
        }
        .padding(16)
        .task {
            if tracker.issues.isEmpty {
                await tracker.refreshIssues()
            }
            await projectManager.loadProjectsIfNeeded()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Assigned GitLab Issues")
                    .font(.headline)
                if let lastRefreshAt = tracker.lastRefreshAt {
                    Text("Updated \(lastRefreshAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                Task {
                    await tracker.refreshIssues()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh issues")

            SettingsLink {
                Image(systemName: "gearshape")
            }
            .help("Settings")
        }
    }

    @ViewBuilder
    private func activeSection(session: TrackingManager.Session) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.awaitingContinuation ? "Awaiting Confirmation" : "Currently Tracking")
                .font(.subheadline.weight(.semibold))

            Button {
                NSWorkspace.shared.open(session.issue.webURL)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.issue.references.short)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(session.issue.title)
                        .font(.body)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            HStack {
                if session.awaitingContinuation {
                    Button("Continue") {
                        tracker.continueAfterCheckpoint()
                    }
                    Button("Stop") {
                        tracker.finishAwaitingSession()
                    }
                } else {
                    Button("Stop and Book Current Time") {
                        tracker.stopTracking()
                    }
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var createIssueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isCreateExpanded.toggle()
            } label: {
                HStack {
                    Text("Create New Issue")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: isCreateExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isCreateExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    createIssueContent
                    createIssueActions
                    createIssueStatus
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    @ViewBuilder
    private var createIssueContent: some View {
        if !authManager.isAuthenticated {
            Text("Connect your GitLab account to create issues.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if projectManager.projects.isEmpty && !projectManager.isLoadingProjects {
            Text("No cached projects yet. Refresh the project list.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            projectSelectionView

            TextField("Issue title", text: $newIssueTitle)
                .textFieldStyle(.roundedBorder)

            TextField("Description (optional)", text: $newIssueDescription, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var projectSelectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isProjectListExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search projects", text: $projectSearch)
                            .textFieldStyle(.plain)
                        Button {
                            isProjectListExpanded = false
                            projectSearch = ""
                        } label: {
                            Image(systemName: "chevron.up")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    projectResultsView
                }
            } else {
                Button {
                    isProjectListExpanded = true
                    projectManager.loadProjectsOnDemand()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Project")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(selectedProjectLabel)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.down")
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var projectResultsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()

            if projectManager.isLoadingProjects {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Loading projects…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
            } else if let projectErrorMessage = projectManager.projectErrorMessage, projectManager.projects.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(projectErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button("Retry Loading Projects") {
                        projectManager.loadProjectsOnDemand(forceRefresh: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            } else if filteredProjects.isEmpty {
                Text(projectSearch.isEmpty ? "No projects available." : "No matching projects.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(filteredProjects), id: \.id) { project in
                            projectRow(project)
                            if project.id != filteredProjects.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
        .background(Color(NSColor.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func projectRow(_ project: GitLabProject) -> some View {
        Button {
            projectManager.selectProject(id: project.id)
            isProjectListExpanded = false
            projectSearch = ""
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .foregroundStyle(.primary)
                    Text(project.nameWithNamespace)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if project.id == projectManager.selectedProjectID {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var createIssueActions: some View {
        HStack {
            Button {
                Task {
                    await projectManager.refreshProjects()
                }
            } label: {
                if projectManager.isLoadingProjects {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Refresh Projects")
                }
            }
            .disabled(!authManager.isAuthenticated || projectManager.isLoadingProjects)

            Button("Create Issue") {
                Task {
                    let createdIssue = await projectManager.createIssue(
                        title: newIssueTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                        description: newIssueDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    guard let createdIssue else { return }
                    newIssueTitle = ""
                    newIssueDescription = ""
                    NSWorkspace.shared.open(createdIssue.webURL)
                }
            }
            .disabled(
                !authManager.isAuthenticated
                    || projectManager.selectedProjectID == nil
                    || newIssueTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || projectManager.isCreatingIssue
            )

            Spacer()
        }
    }

    @ViewBuilder
    private var createIssueStatus: some View {
        if let lastProjectsRefreshAt = projectManager.lastProjectsRefreshAt {
            Text("Projects cached \(lastProjectsRefreshAt.formatted(date: .omitted, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        if let creationMessage = projectManager.creationMessage {
            Text(creationMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if let projectErrorMessage = projectManager.projectErrorMessage {
            Text(projectErrorMessage)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private var filteredProjects: [GitLabProject] {
        let query = projectSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return projectManager.orderedProjects
        }

        return projectManager.orderedProjects.filter { project in
            project.name.localizedCaseInsensitiveContains(query)
                || project.nameWithNamespace.localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedProjectLabel: String {
        guard
            let selectedProjectID = projectManager.selectedProjectID,
            let selectedProject = projectManager.projects.first(where: { $0.id == selectedProjectID })
        else {
            return "Choose a project"
        }

        return selectedProject.nameWithNamespace
    }

    private var issuesSection: some View {
        Group {
            if !settings.isConfigured {
                ContentUnavailableView(
                    "GitLab Not Configured",
                    systemImage: "gearshape.2",
                    description: Text("Open Settings and enter your GitLab instance URL and OAuth application ID.")
                )
            } else if !authManager.isAuthenticated {
                ContentUnavailableView(
                    "GitLab Not Connected",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text("Open Settings and connect your GitLab account.")
                )
            } else if tracker.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading assigned issues…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tracker.issues.isEmpty {
                ContentUnavailableView(
                    "No Assigned Issues",
                    systemImage: "checkmark.circle",
                    description: Text("No open issues are currently assigned to this account.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(tracker.orderedIssues) { issue in
                            Button {
                                tracker.startTracking(issue: issue)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(issue.references.short)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(issue.title)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(Color(NSColor.controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Open in Browser") {
                                    NSWorkspace.shared.open(issue.webURL)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
