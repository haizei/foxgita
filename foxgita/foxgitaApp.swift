//
//  foxgitaApp.swift
//  foxgita
//

import SwiftData
import SwiftUI

@main
struct foxgitaApp: App {
    @State private var router = AppRouter()

    private let container: ModelContainer = {
        let schema = Schema([TaskItem.self, PracticeSession.self, RecordingRef.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("SwiftData failed: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(router)
                .modelContainer(container)
                .tint(GitaTheme.brand500)
                .preferredColorScheme(router.isDark ? .dark : .light)
                .onAppear {
                    SeedData.seedIfNeeded(context: container.mainContext)
                }
        }
    }
}
