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

    private var availableGroupPaths: [String] {
        let projectGroups: [String] = projectManager.projects.compactMap { project in
            let components = project.pathWithNamespace.split(separator: "/").dropLast()
            guard !components.isEmpty else { return nil }
            return components.joined(separator: "/")
        }

        let mergedGroups = Set(projectGroups).union(settings.gitLabGroupPath.isEmpty ? [] : [settings.gitLabGroupPath])
        return mergedGroups.sorted()
    }

    var body: some View {
        Form {
            Section("GitLab") {
                TextField("https://gitlab.example.com", text: $settings.gitLabBaseURL)
                    .textFieldStyle(.roundedBorder)

                TextField("OAuth application ID", text: $settings.oauthClientID)
                    .textFieldStyle(.roundedBorder)

                Picker("Group", selection: $settings.gitLabGroupPath) {
                    Text("All visible projects")
                        .tag("")

                    ForEach(availableGroupPaths, id: \.self) { groupPath in
                        Text(groupPath)
                            .tag(groupPath)
                    }
                }

                Text("Register a GitLab OAuth application for a public client with redirect URI `\(GitLabAuthManager.redirectURI.absoluteString)` and scope `api`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("If set, the create-issue project picker is scoped to this GitLab group path.")
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
