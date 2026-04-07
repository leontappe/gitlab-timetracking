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
        installStatusItemRightClick()
    }

    private func installStatusItemRightClick(attempt: Int = 0) {
        // Find the NSStatusItem that SwiftUI's MenuBarExtra creates internally
        // by using KVC on the private NSStatusBarWindow class
        let statusItem = NSApp.windows
            .filter { $0.className.contains("NSStatusBarWindow") }
            .compactMap { $0.value(forKey: "statusItem") as? NSStatusItem }
            .first

        guard let button = statusItem?.button else {
            if attempt < 20 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.installStatusItemRightClick(attempt: attempt + 1)
                }
            }
            return
        }

        guard !button.subviews.contains(where: { $0 is RightClickHandler }) else { return }

        let handler = RightClickHandler(frame: button.bounds)
        handler.autoresizingMask = [.width, .height]
        handler.onRightClick = { [weak self] in
            guard let self, let statusItem else { return }
            let menu = NSMenu()

            let settingsItem = NSMenuItem(title: "Settings…", action: #selector(self.openSettings), keyEquivalent: ",")
            settingsItem.target = self
            menu.addItem(settingsItem)

            menu.addItem(.separator())

            menu.addItem(withTitle: "Quit GitLab Timetracking", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

            statusItem.menu = menu
            button.performClick(nil)
            statusItem.menu = nil
        }
        button.addSubview(handler)
    }

    @objc private func openSettings() {
        NotificationCenter.default.post(name: .openSettings, object: nil)
    }
}

private class RightClickHandler: NSView {
    var onRightClick: (() -> Void)?

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }
}
