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
    @ObservedObject var issueStatusManager: IssueStatusManager
    @ObservedObject var tracker: TrackingManager
    @State private var newIssueTitle = ""
    @State private var newIssueDescription = ""
    @State private var assignIssueToMe = true
    @State private var selectedIssueStatus = "doing"
    @State private var isCreateExpanded = false
    @State private var isProjectListExpanded = false
    @State private var projectSearch = ""
    @State private var highlightedProjectID: Int?
    @FocusState private var isProjectSearchFocused: Bool
    private var issueStatuses: [String] {
        availableIssueStatuses + ["none"]
    }

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
            issueStatusManager.loadStatusesIfNeeded(forceRefresh: false)
        }
        .onChange(of: issueStatusManager.statuses) { _, statuses in
            guard !statuses.isEmpty else { return }
            let preferredStatus = statuses.first { $0.caseInsensitiveCompare("doing") == .orderedSame }
            if selectedIssueStatus == "doing" || !statuses.contains(selectedIssueStatus) {
                selectedIssueStatus = preferredStatus ?? statuses.first ?? "none"
            }
        }
        .onChange(of: projectManager.selectedProjectID) { _, _ in
            syncSelectedStatus()
        }
        .onChange(of: settings.gitLabGroupPath) { _, _ in
            syncSelectedStatus()
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
        } else if scopedProjects.isEmpty && !projectManager.isLoadingProjects {
            Text(noProjectsMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            projectSelectionView

            TextField("Issue title", text: $newIssueTitle)
                .textFieldStyle(.roundedBorder)

            TextField("Description (optional)", text: $newIssueDescription, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)

            HStack(alignment: .center, spacing: 12) {
                Toggle("Assign to me", isOn: $assignIssueToMe)

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Text("Status")
                        .foregroundStyle(.secondary)

                    Picker("", selection: $selectedIssueStatus) {
                        ForEach(issueStatuses, id: \.self) { status in
                            Text(status == "none" ? "No status" : status.capitalized)
                                .tag(status)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
            }

            if let errorMessage = issueStatusManager.errorMessage {
                Text("Status list fallback in use: \(errorMessage)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !settings.normalizedGroupPath.isEmpty {
                Text("Projects are scoped to `\(settings.normalizedGroupPath)` for status selection.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var projectSelectionView: some View {
        ZStack(alignment: .topLeading) {
            projectSelectorField

            if isProjectListExpanded {
                projectResultsView
                    .padding(.top, 50)
                    .zIndex(1)
            }
        }
        .zIndex(10)
        .onChange(of: projectSearch) { _, _ in
            highlightedProjectID = displayedProjects.first?.id
        }
    }

    private var projectSelectorField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            if isProjectListExpanded {
                TextField("Search projects", text: $projectSearch)
                    .textFieldStyle(.plain)
                    .focused($isProjectSearchFocused)
                    .onSubmit {
                        selectHighlightedProject()
                    }
                    .onKeyPress(.downArrow) {
                        moveProjectHighlight(delta: 1)
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        moveProjectHighlight(delta: -1)
                        return .handled
                    }
                    .onKeyPress(.tab) {
                        moveProjectHighlight(delta: 1)
                        return .handled
                    }
                    .onKeyPress(.return) {
                        selectHighlightedProject()
                        return .handled
                    }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Project")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(selectedProjectLabel)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            Spacer()

            if projectManager.isLoadingProjects {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                if isProjectListExpanded {
                    closeProjectSelector()
                } else {
                    openProjectSelector()
                }
            } label: {
                Image(systemName: isProjectListExpanded ? "chevron.up" : "chevron.down")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color(isProjectListExpanded ? NSColor.textBackgroundColor : NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture {
            if !isProjectListExpanded {
                openProjectSelector()
            }
        }
        .onExitCommand {
            closeProjectSelector()
        }
    }

    @ViewBuilder
    private var projectResultsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()

            if let projectErrorMessage = projectManager.projectErrorMessage, projectManager.projects.isEmpty, !projectManager.isLoadingProjects {
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
            } else if filteredProjects.isEmpty, !projectManager.isLoadingProjects {
                Text(projectSearch.isEmpty ? "No projects available." : "No matching projects.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(displayedProjects), id: \.id) { project in
                                projectRow(project, isHighlighted: project.id == highlightedProjectID)
                                    .id(project.id)
                                if project.id != displayedProjects.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: highlightedProjectID) { _, newValue in
                        guard let newValue else { return }
                        withAnimation(.easeInOut(duration: 0.1)) {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                    .scrollIndicators(.never)
                }
                .frame(height: min(CGFloat(displayedProjects.count) * 44, 220))
            }
        }
        .background(Color(NSColor.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Color.black.opacity(0.08), radius: 8, y: 4)
    }

    private func projectRow(_ project: GitLabProject, isHighlighted: Bool) -> some View {
        Button {
            chooseProject(project.id)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .foregroundStyle(.primary)
                    Text(project.nameWithNamespace)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
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
            .background(isHighlighted ? Color.accentColor.opacity(0.12) : Color.clear)
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
                createIssue()
            }
            .keyboardShortcut(.return, modifiers: [.command])
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
        let baseProjects = scopedProjects
        let query = projectSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return baseProjects
        }

        return baseProjects.filter { project in
            project.name.localizedCaseInsensitiveContains(query)
                || project.nameWithNamespace.localizedCaseInsensitiveContains(query)
                || project.pathWithNamespace.localizedCaseInsensitiveContains(query)
        }
    }

    private var displayedProjects: [GitLabProject] {
        Array(filteredProjects.prefix(25))
    }

    private func openProjectSelector() {
        isProjectListExpanded = true
        projectManager.loadProjectsOnDemand()
        highlightedProjectID = projectManager.selectedProjectID ?? displayedProjects.first?.id
        isProjectSearchFocused = true
    }

    private func closeProjectSelector() {
        isProjectListExpanded = false
        projectSearch = ""
        highlightedProjectID = nil
        isProjectSearchFocused = false
    }

    private func chooseProject(_ id: Int) {
        projectManager.selectProject(id: id)
        closeProjectSelector()
    }

    private func selectHighlightedProject() {
        guard let highlightedProjectID else { return }
        chooseProject(highlightedProjectID)
    }

    private func moveProjectHighlight(delta: Int) {
        guard !displayedProjects.isEmpty else { return }

        let ids = displayedProjects.map(\.id)
        let currentIndex = highlightedProjectID.flatMap { ids.firstIndex(of: $0) } ?? -1
        let nextIndex = min(max(currentIndex + delta, 0), ids.count - 1)
        highlightedProjectID = ids[nextIndex]
    }

    private func createIssue() {
        Task {
            let createdIssue = await projectManager.createIssue(
                title: newIssueTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                description: newIssueDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                assignToCurrentUser: assignIssueToMe,
                statusLabel: selectedIssueStatus == "none" ? nil : selectedIssueStatus
            )
            guard let createdIssue else { return }
            newIssueTitle = ""
            newIssueDescription = ""
            closeProjectSelector()
            isCreateExpanded = false
            await tracker.refreshIssues()
            NSWorkspace.shared.open(createdIssue.webURL)
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

    private var availableIssueStatuses: [String] {
        guard
            let selectedProject,
            matchesConfiguredGroup(project: selectedProject)
        else {
            return settings.normalizedGroupPath.isEmpty ? issueStatusManager.statuses : []
        }

        return issueStatusManager.statuses
    }

    private var selectedProject: GitLabProject? {
        guard let selectedProjectID = projectManager.selectedProjectID else {
            return nil
        }

        return projectManager.projects.first(where: { $0.id == selectedProjectID })
    }

    private var scopedProjects: [GitLabProject] {
        let groupPath = settings.normalizedGroupPath
        guard !groupPath.isEmpty else {
            return projectManager.orderedProjects
        }

        return projectManager.orderedProjects.filter(matchesConfiguredGroup)
    }

    private var noProjectsMessage: String {
        guard !settings.normalizedGroupPath.isEmpty else {
            return "No cached projects yet. Refresh the project list."
        }

        return "No cached projects found in `\(settings.normalizedGroupPath)`. Refresh the project list or update the group path in Settings."
    }

    private func matchesConfiguredGroup(project: GitLabProject) -> Bool {
        let configuredGroupPath = settings.normalizedGroupPath.lowercased()
        guard !configuredGroupPath.isEmpty else {
            return true
        }

        let projectPath = project.pathWithNamespace.lowercased()
        return projectPath == configuredGroupPath || projectPath.hasPrefix(configuredGroupPath + "/")
    }

    private func syncSelectedStatus() {
        let statuses = issueStatuses
        guard !statuses.contains(selectedIssueStatus) else { return }
        selectedIssueStatus = statuses.first(where: { $0.caseInsensitiveCompare("doing") == .orderedSame }) ?? statuses.first ?? "none"
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
                .scrollIndicators(.never)
            }
        }
    }
}
