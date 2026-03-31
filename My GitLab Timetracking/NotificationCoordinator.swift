//
//  NotificationCoordinator.swift
//  My GitLab Timetracking
//

import Foundation
import UserNotifications

@MainActor
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCoordinator()

    static let continueActionID = "CONTINUE_TRACKING"
    static let stopActionID = "STOP_TRACKING"
    static let categoryID = "TRACKING_CHECKPOINT"
    static let notificationID = "TRACKING_CHECKPOINT_ACTIVE"

    var onContinue: (() -> Void)?
    var onStop: (() -> Void)?
    private var reminderTask: Task<Void, Never>?

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let continueAction = UNNotificationAction(
            identifier: Self.continueActionID,
            title: "Continue",
            options: []
        )
        let stopAction = UNNotificationAction(
            identifier: Self.stopActionID,
            title: "Stop",
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [continueAction, stopAction],
            intentIdentifiers: []
        )

        center.setNotificationCategories([category])
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func sendCheckpointNotification(for issue: GitLabIssue) {
        let content = UNMutableNotificationContent()
        content.title = issue.references.short
        content.subtitle = issue.title
        content.body = "20 minutes were added. Continue tracking this issue?"
        content.sound = .default
        content.categoryIdentifier = Self.categoryID

        let request = UNNotificationRequest(
            identifier: Self.notificationID,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    func beginCheckpointReminderLoop(for issue: GitLabIssue, interval: TimeInterval = 180) {
        reminderTask?.cancel()
        reminderTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch {
                    return
                }

                if Task.isCancelled { return }
                await MainActor.run {
                    self.sendCheckpointNotification(for: issue)
                }
            }
        }
    }

    func clearCheckpointNotification() {
        reminderTask?.cancel()
        reminderTask = nil
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [Self.notificationID])
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            switch response.actionIdentifier {
            case Self.continueActionID:
                onContinue?()
            case Self.stopActionID:
                onStop?()
            default:
                break
            }
        }
    }
}
