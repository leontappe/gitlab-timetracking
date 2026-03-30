//
//  SettingsView.swift
//  My GitLab Timetracking
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var tracker: TrackingManager

    @State private var saveMessage: String?
    @State private var isSaving = false

    var body: some View {
        Form {
            Section("GitLab") {
                TextField("https://gitlab.example.com", text: $settings.gitLabBaseURL)
                    .textFieldStyle(.roundedBorder)

                SecureField("Personal access token", text: $settings.personalAccessToken)
                    .textFieldStyle(.roundedBorder)

                Text("The app uses the authenticated account and only shows issues assigned to that user.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
