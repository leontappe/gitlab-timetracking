//
//  NotificationCoordinator.swift
//  My GitLab Timetracking
//

import Foundation
import UserNotifications
import AppKit
import os.log

@MainActor
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCoordinator()

    static let continueActionID = "CONTINUE_TRACKING"
    static let stopActionID = "STOP_TRACKING"
    static let categoryID = "TRACKING_CHECKPOINT"
    static let notificationID = "TRACKING_CHECKPOINT_ACTIVE"

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "GitLabTimetracking", category: "Notifications")

    var onContinue: (() -> Void)?
    var onStop: (() -> Void)?
    private var reminderTask: Task<Void, Never>?
    private var alertSound: NSSound?

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
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                Self.log.error("Notification authorization error: \(error.localizedDescription)")
            } else if !granted {
                Self.log.warning("Notification authorization denied by user")
            }
        }
    }

    func sendCheckpointNotification(for issue: GitLabIssue, checkpointMinutes: Int) {
        let content = UNMutableNotificationContent()
        content.title = issue.references.short
        content.subtitle = issue.title
        content.body = "\(checkpointMinutes) minutes were added. Continue tracking this issue?"
        content.sound = .default
        content.categoryIdentifier = Self.categoryID

        let request = UNNotificationRequest(
            identifier: Self.notificationID,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
        playReminderSound()
    }

    func beginCheckpointReminderLoop(for issue: GitLabIssue, checkpointMinutes: Int, interval: TimeInterval = 180) {
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
                    self.sendCheckpointNotification(for: issue, checkpointMinutes: checkpointMinutes)
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

    private func playReminderSound() {
        let preferredNames = ["Submarine", "Funk", "Glass", "Hero"]

        for name in preferredNames {
            if let sound = NSSound(named: NSSound.Name(name)) {
                alertSound = sound
                sound.play()
                return
            }
        }

        NSSound.beep()
    }
}
