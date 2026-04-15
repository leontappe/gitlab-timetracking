//
//  TrackingManager.swift
//  My GitLab Timetracking
//

import Foundation

@MainActor
@Observable
final class TrackingManager {
    struct Session {
        var issue: GitLabIssue
        var startedAt: Date
        var lastCheckpointAt: Date
        var awaitingContinuation: Bool
        var accumulatedMinutes: Int
    }

    // MARK: - Testable calculation helpers

    nonisolated static func minutesBetween(from: Date, to: Date) -> Int {
        max(1, Int(to.timeIntervalSince(from) / 60))
    }

    nonisolated static func applyCheckpoint(to session: Session, checkpointMinutes: Int, at now: Date) -> Session {
        var updated = session
        updated.accumulatedMinutes += checkpointMinutes
        updated.lastCheckpointAt = now
        updated.awaitingContinuation = true
        return updated
    }

    var checkpointMinutes: Int { settings.checkpointMinutes }

    private let authManager: GitLabAuthManager
    private let settings: AppSettings
    private let api = GitLabAPI()
    private let sessionStore = SessionStore()
    private let historyStore = BookingHistoryStore()
    private var checkpointTask: Task<Void, Never>?
    private(set) var lastRefreshAt: Date?

    var issues: [GitLabIssue] = []
    var activeSession: Session?
    var isLoading = false
    var errorMessage: String?
    var infoMessage = "Configure GitLab to start."
    var bookingHistory: [BookingHistoryEntry] = []
    var isSyncingHistory = false
    var historySyncError: String?
    private(set) var lastHistorySyncAt: Date?
    private(set) var lastSyncedCutoff: Date?
    private var hasSyncedHistoryAtLeastOnce = false

    init(authManager: GitLabAuthManager) {
        self.authManager = authManager
        self.settings = authManager.settings
        self.bookingHistory = historyStore.load()

        NotificationCoordinator.shared.onContinue = { [weak self] in
            self?.continueAfterCheckpoint()
        }
        NotificationCoordinator.shared.onStop = { [weak self] in
            self?.finishAwaitingSession()
        }
        NotificationCoordinator.shared.onStopAndBookAll = { [weak self] in
            self?.finishAwaitingSessionIncludingElapsed()
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

    func secondsSinceLastCheckpoint(for session: Session) -> Int {
        Int(max(0, Date().timeIntervalSince(session.lastCheckpointAt)))
    }

    func defaultStopSeconds(for session: Session) -> Int {
        if session.awaitingContinuation {
            return session.accumulatedMinutes * 60
        }
        return session.accumulatedMinutes * 60 + secondsSinceLastCheckpoint(for: session)
    }

    func plannedBookingMinutes(for session: Session, includingCurrentCycle: Bool) -> Int {
        if includingCurrentCycle {
            return session.accumulatedMinutes + Self.minutesBetween(from: session.lastCheckpointAt, to: Date())
        }
        return session.accumulatedMinutes
    }

    func displayedTotalTrackedSeconds(for issue: GitLabIssue) -> Int {
        let baseSeconds = issue.timeStats.totalTimeSpent
        guard let activeSession, activeSession.issue.id == issue.id else {
            return baseSeconds
        }

        return baseSeconds + defaultStopSeconds(for: activeSession)
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
            awaitingContinuation: false,
            accumulatedMinutes: 0
        )
        errorMessage = nil
        infoMessage = ""
        settings.rememberUsedIssue(id: issue.id)
        scheduleCheckpoint()
        persistActiveSession()

        Task {
            await refreshActiveIssue()
        }
    }

    private func refreshActiveIssue() async {
        guard let session = activeSession else { return }
        do {
            let configuration = try await authManager.currentAuthorization()
            let fresh = try await api.fetchIssue(projectID: session.issue.projectID, iid: session.issue.iid, configuration: configuration)
            if activeSession?.issue.id == fresh.id {
                activeSession?.issue = fresh
            }
            if let index = issues.firstIndex(where: { $0.id == fresh.id }) {
                issues[index] = fresh
            }
        } catch {
            // Non-critical — keep tracking with stale data
        }
    }

    func stopTracking() {
        checkpointTask?.cancel()
        checkpointTask = nil
        NotificationCoordinator.shared.clearCheckpointNotification()

        guard let session = activeSession else { return }
        let partialMinutes = session.awaitingContinuation ? 0 : minutesSinceLastCheckpoint(session: session)
        let totalMinutes = session.accumulatedMinutes + partialMinutes
        activeSession = nil
        sessionStore.clear()

        guard totalMinutes > 0 else {
            infoMessage = "Stopped tracking \(session.issue.references.short)."
            return
        }

        Task {
            await book(issue: session.issue, minutes: totalMinutes, followUp: "Booked \(totalMinutes) minutes to \(session.issue.references.short).")
        }
    }

    func continueAfterCheckpoint() {
        guard var session = activeSession, session.awaitingContinuation else { return }

        NotificationCoordinator.shared.clearCheckpointNotification()
        session.awaitingContinuation = false
        session.lastCheckpointAt = Date()
        activeSession = session
        infoMessage = "Continuing \(session.issue.references.short)."
        scheduleCheckpoint()
        persistActiveSession()
    }

    func stopTrackingWithoutBooking() {
        checkpointTask?.cancel()
        checkpointTask = nil
        NotificationCoordinator.shared.clearCheckpointNotification()

        let ref = activeSession?.issue.references.short ?? ""
        activeSession = nil
        sessionStore.clear()
        infoMessage = "Discarded tracking for \(ref)."
    }

    func finishAwaitingSession() {
        checkpointTask?.cancel()
        checkpointTask = nil
        NotificationCoordinator.shared.clearCheckpointNotification()

        guard let session = activeSession else { return }
        let totalMinutes = session.accumulatedMinutes
        activeSession = nil
        sessionStore.clear()

        guard totalMinutes > 0 else {
            infoMessage = "Stopped tracking \(session.issue.references.short)."
            return
        }

        Task {
            await book(issue: session.issue, minutes: totalMinutes, followUp: "Booked \(totalMinutes) minutes to \(session.issue.references.short).")
        }
    }

    func finishAwaitingSessionIncludingElapsed() {
        checkpointTask?.cancel()
        checkpointTask = nil
        NotificationCoordinator.shared.clearCheckpointNotification()

        guard let session = activeSession else { return }
        let totalMinutes = session.accumulatedMinutes + minutesSinceLastCheckpoint(session: session)
        activeSession = nil
        sessionStore.clear()

        guard totalMinutes > 0 else {
            infoMessage = "Stopped tracking \(session.issue.references.short)."
            return
        }

        Task {
            await book(issue: session.issue, minutes: totalMinutes, followUp: "Booked \(totalMinutes) minutes to \(session.issue.references.short).")
        }
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
        guard let session = activeSession, !session.awaitingContinuation else { return }

        checkpointTask = nil
        let updated = Self.applyCheckpoint(to: session, checkpointMinutes: checkpointMinutes, at: Date())
        activeSession = updated
        persistActiveSession()

        infoMessage = "\(updated.accumulatedMinutes) minutes accumulated on \(updated.issue.references.short)."
        NotificationCoordinator.shared.sendCheckpointNotification(for: updated.issue, checkpointMinutes: checkpointMinutes, soundName: settings.notificationSound)
        NotificationCoordinator.shared.beginCheckpointReminderLoop(for: updated.issue, checkpointMinutes: checkpointMinutes, soundName: settings.notificationSound)
    }

    private func book(issue: GitLabIssue, minutes: Int, followUp: String) async {
        do {
            let configuration = try await authManager.currentAuthorization()
            try await api.addSpentTime(issue: issue, duration: "\(minutes)m", configuration: configuration)
            errorMessage = nil
            infoMessage = followUp

            let entry = BookingHistoryEntry(
                id: UUID(),
                issueID: issue.id,
                issueReference: issue.references.short,
                issueTitle: issue.title,
                issueWebURL: issue.webURL,
                minutes: minutes,
                bookedAt: Date()
            )
            bookingHistory = historyStore.append(entry)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearBookingHistory() {
        historyStore.clear()
        bookingHistory = []
    }

    func syncHistoryFromGitLab(cutoff: Date? = nil, force: Bool = false) async {
        guard !isSyncingHistory else { return }

        if !force, isSyncCoveredBy(existingCutoff: lastSyncedCutoff, newCutoff: cutoff), hasSyncedHistoryAtLeastOnce {
            return
        }

        guard authManager.isAuthenticated, let currentUserID = authManager.currentUser?.id else {
            historySyncError = "Connect your GitLab account to sync history."
            return
        }

        isSyncingHistory = true
        historySyncError = nil

        do {
            let configuration = try await authManager.currentAuthorization()
            let closedIssues = try await api.fetchClosedAssignedIssues(updatedAfter: cutoff, configuration: configuration)

            var issuesByID: [Int: GitLabIssue] = [:]
            for issue in issues where cutoff.map({ issue.updatedAt >= $0 }) ?? true {
                issuesByID[issue.id] = issue
            }
            for issue in closedIssues {
                issuesByID[issue.id] = issue
            }
            let snapshotIssues = Array(issuesByID.values)
            var remoteEntries: [BookingHistoryEntry] = []

            for issue in snapshotIssues {
                let notes = try await api.fetchIssueNotes(projectID: issue.projectID, issueIID: issue.iid, configuration: configuration)
                for note in notes where note.system && note.author.id == currentUserID {
                    if let cutoff, note.createdAt < cutoff {
                        continue
                    }

                    guard let minutes = GitLabTimeNoteParser.addedMinutes(from: note.body), minutes > 0 else {
                        continue
                    }

                    remoteEntries.append(
                        BookingHistoryEntry(
                            id: UUID(),
                            issueID: issue.id,
                            issueReference: issue.references.short,
                            issueTitle: issue.title,
                            issueWebURL: issue.webURL,
                            minutes: minutes,
                            bookedAt: note.createdAt,
                            gitLabEventID: note.id
                        )
                    )
                }
            }

            bookingHistory = historyStore.mergeRemote(remoteEntries)
            lastHistorySyncAt = Date()
            lastSyncedCutoff = narrowerCutoff(existing: lastSyncedCutoff, new: cutoff)
            hasSyncedHistoryAtLeastOnce = true
        } catch {
            historySyncError = error.localizedDescription
        }

        isSyncingHistory = false
    }

    private func isSyncCoveredBy(existingCutoff: Date?, newCutoff: Date?) -> Bool {
        guard let existingCutoff else { return true }
        guard let newCutoff else { return false }
        return newCutoff >= existingCutoff
    }

    private func narrowerCutoff(existing: Date?, new: Date?) -> Date? {
        guard let existing else { return nil }
        guard let new else { return nil }
        return min(existing, new)
    }

    private func minutesSinceLastCheckpoint(session: Session) -> Int {
        Self.minutesBetween(from: session.lastCheckpointAt, to: Date())
    }

    private func restorePersistedSessionIfNeeded() async {
        guard let persisted = sessionStore.load() else {
            return
        }

        var session = Session(
            issue: persisted.issue,
            startedAt: persisted.startedAt,
            lastCheckpointAt: persisted.lastCheckpointAt,
            awaitingContinuation: persisted.awaitingContinuation,
            accumulatedMinutes: persisted.accumulatedMinutes
        )

        activeSession = session

        if session.awaitingContinuation {
            infoMessage = "\(session.accumulatedMinutes) minutes accumulated on \(session.issue.references.short)."
            NotificationCoordinator.shared.sendCheckpointNotification(for: session.issue, checkpointMinutes: checkpointMinutes, soundName: settings.notificationSound)
            NotificationCoordinator.shared.beginCheckpointReminderLoop(for: session.issue, checkpointMinutes: checkpointMinutes, soundName: settings.notificationSound)
            return
        }

        guard authManager.isAuthenticated else {
            infoMessage = "Restore paused. Connect your GitLab account to continue \(session.issue.references.short)."
            return
        }

        let elapsed = Date().timeIntervalSince(session.lastCheckpointAt)
        let checkpointInterval = TimeInterval(checkpointMinutes * 60)

        if elapsed >= checkpointInterval {
            let checkpointFiredAt = session.lastCheckpointAt.addingTimeInterval(checkpointInterval)
            let updated = Self.applyCheckpoint(to: session, checkpointMinutes: checkpointMinutes, at: checkpointFiredAt)
            activeSession = updated
            persistActiveSession()

            infoMessage = "\(updated.accumulatedMinutes) minutes accumulated on \(updated.issue.references.short)."
            NotificationCoordinator.shared.sendCheckpointNotification(for: updated.issue, checkpointMinutes: checkpointMinutes, soundName: settings.notificationSound)
            NotificationCoordinator.shared.beginCheckpointReminderLoop(for: updated.issue, checkpointMinutes: checkpointMinutes, soundName: settings.notificationSound)
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
                awaitingContinuation: activeSession.awaitingContinuation,
                accumulatedMinutes: activeSession.accumulatedMinutes
            )
        )
    }
}
