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
    @State private var settings: AppSettings
    @State private var authManager: GitLabAuthManager
    @State private var projectManager: ProjectManager
    @State private var tracker: TrackingManager

    init() {
        let settings = AppSettings()
        let authManager = GitLabAuthManager(settings: settings)
        _settings = State(initialValue: settings)
        _authManager = State(initialValue: authManager)
        _projectManager = State(initialValue: ProjectManager(authManager: authManager))
        _tracker = State(initialValue: TrackingManager(authManager: authManager))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(settings: settings, authManager: authManager, projectManager: projectManager, tracker: tracker)
                .frame(width: 380, height: 520)
        } label: {
            MenuBarLabelView(settings: settings, tracker: tracker)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: settings, authManager: authManager, projectManager: projectManager, tracker: tracker)
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
