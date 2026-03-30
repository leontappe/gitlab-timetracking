//
//  TrackingManager.swift
//  My GitLab Timetracking
//

import Foundation
import Combine

@MainActor
final class TrackingManager: ObservableObject {
    struct Session {
        let issue: GitLabIssue
        var startedAt: Date
        var lastCheckpointAt: Date
        var awaitingContinuation: Bool
    }

    let checkpointMinutes = 20

    private let settings: AppSettings
    private let api = GitLabAPI()
    private var checkpointTask: Task<Void, Never>?
    @Published private(set) var lastRefreshAt: Date?

    @Published var issues: [GitLabIssue] = []
    @Published var activeSession: Session?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var infoMessage = "Configure GitLab to start."

    init(settings: AppSettings) {
        self.settings = settings

        NotificationCoordinator.shared.onContinue = { [weak self] in
            self?.continueAfterCheckpoint()
        }
        NotificationCoordinator.shared.onStop = { [weak self] in
            self?.finishAwaitingSession()
        }
    }

    var isTracking: Bool {
        guard let activeSession else { return false }
        return !activeSession.awaitingContinuation
    }

    var activeIssue: GitLabIssue? {
        activeSession?.issue
    }

    func refreshIssues() async {
        guard settings.isConfigured else {
            issues = []
            errorMessage = nil
            infoMessage = "Configure your GitLab base URL and personal access token in Settings."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            guard let configuration = settings.configuration else {
                throw GitLabAPIError.missingConfiguration
            }

            issues = try await api.fetchAssignedIssues(configuration: configuration)
            lastRefreshAt = Date()
            infoMessage = issues.isEmpty ? "No currently assigned open issues." : "Assigned issues updated."
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func startTracking(issue: GitLabIssue) {
        checkpointTask?.cancel()
        NotificationCoordinator.shared.clearCheckpointNotification()

        let now = Date()
        activeSession = Session(
            issue: issue,
            startedAt: now,
            lastCheckpointAt: now,
            awaitingContinuation: false
        )
        errorMessage = nil
        infoMessage = "Tracking \(issue.references.short)."
        scheduleCheckpoint()
    }

    func stopTracking() {
        checkpointTask?.cancel()
        checkpointTask = nil
        NotificationCoordinator.shared.clearCheckpointNotification()

        guard let session = activeSession else { return }
        let pendingMinutes = session.awaitingContinuation ? 0 : minutesSinceLastCheckpoint(session: session)
        activeSession = nil

        guard pendingMinutes > 0 else {
            infoMessage = "Stopped tracking \(session.issue.references.short)."
            return
        }

        Task {
            await book(issue: session.issue, minutes: pendingMinutes, followUp: "Stopped tracking \(session.issue.references.short).")
        }
    }

    func continueAfterCheckpoint() {
        guard var session = activeSession, session.awaitingContinuation else { return }

        NotificationCoordinator.shared.clearCheckpointNotification()
        let now = Date()
        session.awaitingContinuation = false
        session.lastCheckpointAt = now
        session.startedAt = now
        activeSession = session
        infoMessage = "Continuing \(session.issue.references.short)."
        scheduleCheckpoint()
    }

    func finishAwaitingSession() {
        checkpointTask?.cancel()
        checkpointTask = nil
        NotificationCoordinator.shared.clearCheckpointNotification()

        if let session = activeSession {
            infoMessage = "Tracked 20 minutes on \(session.issue.references.short)."
        }
        activeSession = nil
    }

    func saveSettings() async {
        settings.save()
        await refreshIssues()
    }

    private func scheduleCheckpoint() {
        checkpointTask?.cancel()

        checkpointTask = Task { [weak self] in
            guard let self else { return }
            let interval = UInt64(checkpointMinutes * 60) * 1_000_000_000

            do {
                try await Task.sleep(nanoseconds: interval)
            } catch {
                return
            }

            await self.handleCheckpoint()
        }
    }

    private func handleCheckpoint() async {
        guard var session = activeSession, !session.awaitingContinuation else { return }

        checkpointTask = nil
        session.awaitingContinuation = true
        activeSession = session

        await book(issue: session.issue, minutes: checkpointMinutes, followUp: "20 minutes added to \(session.issue.references.short).")

        guard activeSession != nil else { return }
        NotificationCoordinator.shared.sendCheckpointNotification(for: session.issue)
        infoMessage = "Waiting for confirmation on \(session.issue.references.short)."
    }

    private func book(issue: GitLabIssue, minutes: Int, followUp: String) async {
        do {
            guard let configuration = settings.configuration else {
                throw GitLabAPIError.missingConfiguration
            }

            try await api.addSpentTime(issue: issue, duration: "\(minutes)m", configuration: configuration)
            errorMessage = nil
            infoMessage = followUp
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func minutesSinceLastCheckpoint(session: Session) -> Int {
        max(1, Int(Date().timeIntervalSince(session.lastCheckpointAt) / 60))
    }
}
