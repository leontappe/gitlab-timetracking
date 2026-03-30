//
//  My_GitLab_TimetrackingApp.swift
//  My GitLab Timetracking
//
//  Created by Leon Tappe on 30.03.26.
//

import SwiftUI
import SwiftData

@main
struct My_GitLab_TimetrackingApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
