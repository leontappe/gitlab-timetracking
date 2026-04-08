//
//  TrackingManager.swift
//  My GitLab Timetracking
//

import Foundation

@MainActor
@Observable
final class TrackingManager {
    struct Session {
        let issue: GitLabIssue
        var startedAt: Date
        var lastCheckpointAt: Date
        var awaitingContinuation: Bool
    }

    var checkpointMinutes: Int { settings.checkpointMinutes }

    private let authManager: GitLabAuthManager
    private let settings: AppSettings
    private let api = GitLabAPI()
    private let sessionStore = SessionStore()
    private var checkpointTask: Task<Void, Never>?
    private(set) var lastRefreshAt: Date?

    var issues: [GitLabIssue] = []
    var activeSession: Session?
    var isLoading = false
    var errorMessage: String?
    var infoMessage = "Configure GitLab to start."

    init(authManager: GitLabAuthManager) {
        self.authManager = authManager
        self.settings = authManager.settings

        NotificationCoordinator.shared.onContinue = { [weak self] in
            self?.continueAfterCheckpoint()
        }
        NotificationCoordinator.shared.onStop = { [weak self] in
            self?.finishAwaitingSession()
        }

        Task {
            await restorePersistedSessionIfNeeded()
        }
    }

    var isTracking: Bool {
        guard let activeSession else { return false }
        return !activeSession.awaitingContinuation
    }

    var activeIssue: GitLabIssue? {
        activeSession?.issue
    }

    func currentCycleElapsed(for session: Session) -> TimeInterval {
        if session.awaitingContinuation {
            return max(0, session.lastCheckpointAt.timeIntervalSince(session.startedAt))
        }

        return max(0, Date().timeIntervalSince(session.startedAt))
    }

    func displayedTotalTrackedSeconds(for issue: GitLabIssue) -> Int {
        let baseSeconds = issue.timeStats.totalTimeSpent
        guard let activeSession, activeSession.issue.id == issue.id, !activeSession.awaitingContinuation else {
            return baseSeconds
        }

        return baseSeconds + Int(currentCycleElapsed(for: activeSession))
    }

    func formattedDuration(seconds: Int) -> String {
        let clampedSeconds = max(0, seconds)
        if clampedSeconds < 600 {
            let minutes = clampedSeconds / 60
            let remainingSeconds = clampedSeconds % 60
            return "\(minutes)m \(remainingSeconds)s"
        }

        let totalMinutes = clampedSeconds / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        return "\(minutes)m"
    }

    var orderedIssues: [GitLabIssue] {
        let recentIDs = settings.recentIssueIDs
        let recentIssues = recentIDs.compactMap { id in
            issues.first(where: { $0.id == id })
        }

        let remainingIssues = issues.filter { issue in
            !recentIDs.contains(issue.id)
        }
        .sorted { left, right in
            left.updatedAt > right.updatedAt
        }

        return recentIssues + remainingIssues
    }

    func refreshIssues() async {
        guard authManager.settings.isConfigured else {
            issues = []
            errorMessage = nil
            infoMessage = "Configure your GitLab instance and OAuth application in Settings."
            return
        }

        guard authManager.isAuthenticated else {
            issues = []
            errorMessage = nil
            infoMessage = "Connect your GitLab account in Settings."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let configuration = try await authManager.currentAuthorization()
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
        infoMessage = ""
        settings.rememberUsedIssue(id: issue.id)
        scheduleCheckpoint()
        persistActiveSession()
    }

    func stopTracking() {
        checkpointTask?.cancel()
        checkpointTask = nil
        NotificationCoordinator.shared.clearCheckpointNotification()

        guard let session = activeSession else { return }
        let pendingMinutes = session.awaitingContinuation ? 0 : minutesSinceLastCheckpoint(session: session)
        activeSession = nil
        sessionStore.clear()

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
        persistActiveSession()
    }

    func finishAwaitingSession() {
        checkpointTask?.cancel()
        checkpointTask = nil
        NotificationCoordinator.shared.clearCheckpointNotification()

        if let session = activeSession {
            infoMessage = "Tracked \(checkpointMinutes) minutes on \(session.issue.references.short)."
        }
        activeSession = nil
        sessionStore.clear()
    }

    func saveSettings() async {
        authManager.settings.save()
        await refreshIssues()
    }

    func clearIssues() {
        checkpointTask?.cancel()
        checkpointTask = nil
        issues = []
        errorMessage = nil
        activeSession = nil
        sessionStore.clear()
        infoMessage = "Connect your GitLab account in Settings."
    }

    func closeIssue(_ issue: GitLabIssue) async {
        if activeIssue?.id == issue.id {
            stopTracking()
        }

        do {
            let configuration = try await authManager.currentAuthorization()
            try await api.closeIssue(issue: issue, configuration: configuration)
            errorMessage = nil
            infoMessage = "Closed \(issue.references.short)."
            await refreshIssues()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteIssue(_ issue: GitLabIssue) async {
        if activeIssue?.id == issue.id {
            stopTracking()
        }

        do {
            let configuration = try await authManager.currentAuthorization()
            try await api.deleteIssue(issue: issue, configuration: configuration)
            errorMessage = nil
            infoMessage = "Deleted \(issue.references.short)."
            await refreshIssues()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleCheckpoint(after interval: TimeInterval? = nil) {
        checkpointTask?.cancel()

        checkpointTask = Task { [weak self] in
            guard let self else { return }
            let seconds = interval ?? TimeInterval(checkpointMinutes * 60)

            do {
                try await Task.sleep(for: .seconds(max(seconds, 1)))
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
        persistActiveSession()

        await book(issue: session.issue, minutes: checkpointMinutes, followUp: "\(checkpointMinutes) minutes added to \(session.issue.references.short).")

        guard activeSession != nil else { return }
        NotificationCoordinator.shared.sendCheckpointNotification(for: session.issue, checkpointMinutes: checkpointMinutes)
        NotificationCoordinator.shared.beginCheckpointReminderLoop(for: session.issue, checkpointMinutes: checkpointMinutes)
        infoMessage = "Waiting for confirmation on \(session.issue.references.short)."
    }

    private func book(issue: GitLabIssue, minutes: Int, followUp: String) async {
        do {
            let configuration = try await authManager.currentAuthorization()
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

    private func restorePersistedSessionIfNeeded() async {
        guard let persisted = sessionStore.load() else {
            return
        }

        var session = Session(
            issue: persisted.issue,
            startedAt: persisted.startedAt,
            lastCheckpointAt: persisted.lastCheckpointAt,
            awaitingContinuation: persisted.awaitingContinuation
        )

        activeSession = session

        if session.awaitingContinuation {
            infoMessage = "Awaiting confirmation on \(session.issue.references.short)."
            NotificationCoordinator.shared.sendCheckpointNotification(for: session.issue, checkpointMinutes: checkpointMinutes)
            NotificationCoordinator.shared.beginCheckpointReminderLoop(for: session.issue, checkpointMinutes: checkpointMinutes)
            return
        }

        guard authManager.isAuthenticated else {
            infoMessage = "Restore paused. Connect your GitLab account to continue \(session.issue.references.short)."
            return
        }

        let elapsed = Date().timeIntervalSince(session.lastCheckpointAt)
        let checkpointInterval = TimeInterval(checkpointMinutes * 60)

        if elapsed >= checkpointInterval {
            session.awaitingContinuation = true
            activeSession = session
            persistActiveSession()
            await book(issue: session.issue, minutes: checkpointMinutes, followUp: "\(checkpointMinutes) minutes added to \(session.issue.references.short).")

            guard activeSession != nil else { return }
            NotificationCoordinator.shared.sendCheckpointNotification(for: session.issue, checkpointMinutes: checkpointMinutes)
            NotificationCoordinator.shared.beginCheckpointReminderLoop(for: session.issue, checkpointMinutes: checkpointMinutes)
            infoMessage = "Waiting for confirmation on \(session.issue.references.short)."
            return
        }

        infoMessage = "Restored tracking for \(session.issue.references.short)."
        scheduleCheckpoint(after: checkpointInterval - elapsed)
    }

    private func persistActiveSession() {
        guard let activeSession else {
            sessionStore.clear()
            return
        }

        sessionStore.save(
            PersistedSession(
                issue: activeSession.issue,
                startedAt: activeSession.startedAt,
                lastCheckpointAt: activeSession.lastCheckpointAt,
                awaitingContinuation: activeSession.awaitingContinuation
            )
        )
    }
}
