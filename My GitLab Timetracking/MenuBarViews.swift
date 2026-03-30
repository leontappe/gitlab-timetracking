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
    @ObservedObject var tracker: TrackingManager

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

            issuesSection
        }
        .padding(16)
        .task {
            if tracker.issues.isEmpty {
                await tracker.refreshIssues()
            }
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
                        ForEach(tracker.issues) { issue in
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
