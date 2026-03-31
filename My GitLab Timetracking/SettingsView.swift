//
//  SettingsView.swift
//  My GitLab Timetracking
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var authManager: GitLabAuthManager
    @ObservedObject var projectManager: ProjectManager
    @ObservedObject var tracker: TrackingManager

    @State private var saveMessage: String?
    @State private var isSaving = false
    @State private var pendingGroupPath = ""

    private var availableGroupPaths: [String] {
        let projectGroups: [String] = projectManager.projects.compactMap { project in
            let components = project.pathWithNamespace.split(separator: "/").dropLast()
            guard !components.isEmpty else { return nil }
            return components.joined(separator: "/")
        }

        let mergedGroups = Set(projectGroups).union(settings.gitLabGroupPaths)
        return mergedGroups.sorted()
    }

    private var selectableGroupPaths: [String] {
        availableGroupPaths.filter { !settings.gitLabGroupPaths.contains($0) }
    }

    var body: some View {
        Form {
            Section("GitLab") {
                TextField("https://gitlab.example.com", text: $settings.gitLabBaseURL)
                    .textFieldStyle(.roundedBorder)

                TextField("OAuth application ID", text: $settings.oauthClientID)
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Picker("Add Group", selection: $pendingGroupPath) {
                            Text("Select a group")
                                .tag("")

                            ForEach(selectableGroupPaths, id: \.self) { groupPath in
                                Text(groupPath)
                                    .tag(groupPath)
                            }
                        }

                        Button("Add") {
                            guard !pendingGroupPath.isEmpty else { return }
                            settings.addSelectedGroup(path: pendingGroupPath)
                            pendingGroupPath = ""
                        }
                        .disabled(pendingGroupPath.isEmpty)
                    }

                    if settings.gitLabGroupPaths.isEmpty {
                        Text("All visible projects are currently included.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(settings.gitLabGroupPaths, id: \.self) { groupPath in
                                HStack {
                                    Text(groupPath)
                                        .textSelection(.enabled)
                                    Spacer()
                                    Button("Remove") {
                                        settings.removeSelectedGroup(path: groupPath)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }

                        Button("Use All Visible Projects") {
                            settings.clearSelectedGroups()
                            pendingGroupPath = ""
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Text("Register a GitLab OAuth application for a public client with redirect URI `\(GitLabAuthManager.redirectURI.absoluteString)` and scope `api`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Selected groups limit the create-issue project picker to projects inside those namespaces.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Account") {
                if let currentUser = authManager.currentUser {
                    Text("\(currentUser.name) (@\(currentUser.username))")
                        .font(.body)
                    Button("Disconnect Account") {
                        authManager.signOut()
                        projectManager.clearProjectState()
                        tracker.clearIssues()
                    }
                } else {
                    Button("Connect GitLab Account") {
                        Task {
                            await tracker.saveSettings()
                            await authManager.signIn()
                            await projectManager.refreshProjects()
                            await tracker.refreshIssues()
                        }
                    }
                    .disabled(isSaving || !settings.isConfigured || authManager.isAuthenticating)

                    if authManager.isAuthenticating {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let authError = authManager.authError {
                    Text(authError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Time Tracking") {
                Toggle("Show worked time in menu bar", isOn: $settings.showTrackedTimeInMenuBar)
                Text("Selecting an issue starts local tracking immediately. Every 20 minutes the app books 20 minutes to the issue in GitLab and asks whether to continue.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Save and Refresh") {
                        Task {
                            isSaving = true
                            await tracker.saveSettings()
                            await authManager.refreshCurrentUser()
                            projectManager.handleSettingsSaved()
                            isSaving = false
                            saveMessage = tracker.errorMessage == nil ? "Settings saved." : nil
                        }
                    }
                    .disabled(isSaving)

                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Spacer()

                    if let saveMessage {
                        Text(saveMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
