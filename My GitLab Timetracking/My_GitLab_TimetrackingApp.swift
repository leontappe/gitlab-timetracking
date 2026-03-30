//
//  My_GitLab_TimetrackingApp.swift
//  My GitLab Timetracking
//
//  Created by Leon Tappe on 30.03.26.
//

import SwiftUI
import AppKit

@main
struct My_GitLab_TimetrackingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: AppSettings
    @StateObject private var authManager: GitLabAuthManager
    @StateObject private var tracker: TrackingManager

    init() {
        let settings = AppSettings()
        let authManager = GitLabAuthManager(settings: settings)
        _settings = StateObject(wrappedValue: settings)
        _authManager = StateObject(wrappedValue: authManager)
        _tracker = StateObject(wrappedValue: TrackingManager(authManager: authManager))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(settings: settings, authManager: authManager, tracker: tracker)
                .frame(width: 380, height: 520)
        } label: {
            MenuBarLabelView(tracker: tracker)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: settings, authManager: authManager, tracker: tracker)
                .frame(width: 520, height: 320)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NotificationCoordinator.shared.configure()
    }
}
