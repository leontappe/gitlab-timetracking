//
//  MenuBarViews.swift
//  My GitLab Timetracking
//

import SwiftUI
import AppKit

extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
}

enum AppColors {
    static let trackingGreen = Color(red: 0.18, green: 0.62, blue: 0.33)
    static let checkpointOrange = Color.orange
}

struct MenuBarLabelView: View {
    @Environment(\.openSettings) private var openSettings
    var settings: AppSettings
    var tracker: TrackingManager
    @State private var tick = 0

    var body: some View {
        let _ = tick
        HStack {
            Image(systemName: statusSymbolName)
                .symbolRenderingMode(.palette)
                .foregroundStyle(statusColor, statusColor.opacity(1.0))
                .font(.system(size: 20, weight: .bold))
            Text(statusLabel)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                tick &+= 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            openSettings()
            NSApp.activate()
        }
    }

    private var statusSymbolName: String {
        if tracker.isTracking {
            return "play.circle.fill"
        }

        if tracker.activeIssue != nil {
            return "bell.badge.fill"
        }

        return "circle.fill"
    }

    private var statusLabel: String {
        if let session = tracker.activeSession {
            var components: [String] = []

            if settings.showIssueReferenceInMenuBar {
                components.append(session.issue.references.short)
            }

            if settings.showTrackedTimeInMenuBar {
                let current = tracker.formattedDuration(seconds: Int(tracker.currentCycleElapsed(for: session)))
                components.append(current)
            }

            return components.joined(separator: " ")
        }

        return ""
    }

    private var statusColor: Color {
        if tracker.isTracking {
            return AppColors.trackingGreen
        }

        if tracker.activeIssue != nil {
            return AppColors.checkpointOrange
        }

        return .secondary
    }
}

struct MenuBarContentView: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openURL) private var openURL
    var settings: AppSettings
    var authManager: GitLabAuthManager
    var projectManager: ProjectManager
    var tracker: TrackingManager
    @State private var newIssueTitle = ""
    @State private var newIssueDescription = ""
    @State private var assignIssueToMe = true
    @State private var isCreateExpanded = false
    @State private var isProjectListExpanded = false
    @State private var projectSearch = ""
    @State private var highlightedProjectID: Int?
    @State private var issuePendingDeleteConfirmation: GitLabIssue?
    @FocusState private var isProjectSearchFocused: Bool

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 14) {
                header
                trackingOverviewSection

                if let errorMessage = tracker.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if !tracker.infoMessage.isEmpty {
                    Text(tracker.infoMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                createIssueSection
                issuesSection
            }
            .padding(16)

            if let issue = issuePendingDeleteConfirmation {
                deleteConfirmationOverlay(issue: issue)
            }
        }
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

            Button {
                openSettings()
                NSApp.activate()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
        }
    }

    @ViewBuilder
    private var trackingOverviewSection: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let session = tracker.activeSession {
                activeSection(session: session)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("No Active Tracking", systemImage: "pause.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text("Select an assigned issue below to start tracking time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    @ViewBuilder
    private func activeSection(session: TrackingManager.Session) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(session.awaitingContinuation ? "Awaiting Confirmation" : "Currently Tracking", systemImage: session.awaitingContinuation ? "bell.badge.fill" : "play.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(session.awaitingContinuation ? AppColors.checkpointOrange : AppColors.trackingGreen)

            Button {
                openURL(session.issue.webURL)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.issue.references.short)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(session.issue.title)
                        .font(.body)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 12) {
                        Label(currentCycleLabel(session: session), systemImage: session.awaitingContinuation ? "pause.circle" : "timer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Label(totalTrackedLabel(issue: session.issue), systemImage: "clock.badge.checkmark")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(activeSessionBackgroundColor(session: session))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(activeSessionBorderColor(session: session), lineWidth: 1)
                }
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
                .background(Color(nsColor: .controlBackgroundColor))
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

            HStack {
                Toggle("Assign to me", isOn: $assignIssueToMe)
                Spacer()
            }

            if !settings.normalizedGroupPaths.isEmpty {
                Text("Projects are scoped to \(settings.normalizedGroupPaths.count) selected \(settings.normalizedGroupPaths.count == 1 ? "group" : "groups").")
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
        .background(Color(nsColor: isProjectListExpanded ? .textBackgroundColor : .controlBackgroundColor))
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
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(displayedProjects, id: \.id) { project in
                                projectRow(project, isHighlighted: project.id == highlightedProjectID)
                                    .id(project.id)
                                Divider()
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
        .background(Color(nsColor: .textBackgroundColor))
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
        filteredProjects
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
                assignToCurrentUser: assignIssueToMe
            )
            guard let createdIssue else { return }
            newIssueTitle = ""
            newIssueDescription = ""
            closeProjectSelector()
            isCreateExpanded = false
            await tracker.refreshIssues()
            openURL(createdIssue.webURL)
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

    private var scopedProjects: [GitLabProject] {
        let groupPaths = settings.normalizedGroupPaths
        guard !groupPaths.isEmpty else {
            return projectManager.orderedProjects
        }

        return projectManager.orderedProjects.filter(matchesConfiguredGroup)
    }

    private var noProjectsMessage: String {
        guard !settings.normalizedGroupPaths.isEmpty else {
            return "No cached projects yet. Refresh the project list."
        }

        return "No cached projects found in the selected groups. Refresh the project list or update the group selection in Settings."
    }

    private func matchesConfiguredGroup(project: GitLabProject) -> Bool {
        let configuredGroupPaths = settings.normalizedGroupPaths.map { $0.lowercased() }
        guard !configuredGroupPaths.isEmpty else {
            return true
        }

        let projectPath = project.pathWithNamespace.lowercased()
        return configuredGroupPaths.contains { groupPath in
            projectPath == groupPath || projectPath.hasPrefix(groupPath + "/")
        }
    }

    private func activeSessionBackgroundColor(session: TrackingManager.Session) -> Color {
        (session.awaitingContinuation ? AppColors.checkpointOrange : AppColors.trackingGreen).opacity(0.12)
    }

    private func activeSessionBorderColor(session: TrackingManager.Session) -> Color {
        (session.awaitingContinuation ? AppColors.checkpointOrange : AppColors.trackingGreen).opacity(0.35)
    }

    private func currentCycleLabel(session: TrackingManager.Session) -> String {
        return "Current: \(tracker.formattedDuration(seconds: Int(tracker.currentCycleElapsed(for: session))))"
    }

    private func totalTrackedLabel(issue: GitLabIssue) -> String {
        "Total: \(tracker.formattedDuration(seconds: tracker.displayedTotalTrackedSeconds(for: issue)))"
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
                                .background(Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Open in GitLab") {
                                    openURL(issue.webURL)
                                }
                                Button("Close Issue") {
                                    Task {
                                        await tracker.closeIssue(issue)
                                    }
                                }
                                Button("Delete Issue") {
                                    issuePendingDeleteConfirmation = issue
                                }
                            }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
    }

    private func deleteConfirmationOverlay(issue: GitLabIssue) -> some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                Text("Delete Issue?")
                    .font(.headline)

                Text("Delete \(issue.references.short) from GitLab? This cannot be undone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    Spacer()

                    Button("Cancel") {
                        issuePendingDeleteConfirmation = nil
                    }

                    Button("Delete", role: .destructive) {
                        Task {
                            await tracker.deleteIssue(issue)
                        }
                        issuePendingDeleteConfirmation = nil
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 320, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        }
    }
}
