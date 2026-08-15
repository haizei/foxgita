//
//  foxgitaApp.swift
//  foxgita
//

import SwiftData
import SwiftUI

@main
struct foxgitaApp: App {
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    @State private var router = AppRouter()
    @State private var store: PracticeStore
    @State private var reminderDelegate: ReminderDelegate?
    private let container: ModelContainer

    init() {
        let schema = Schema(versionedSchema: GitaSchemaV4.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            let container = try ModelContainer(
                for: schema, migrationPlan: GitaMigrationPlan.self, configurations: [config]
            )
            self.container = container
            _store = State(
                initialValue: PracticeStore(
                    repository: SwiftDataPracticeRepository(context: container.mainContext)
                )
            )
        } catch {
            fatalError("SwiftData failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(router)
                .environment(store)
                .modelContainer(container)
                .tint(GitaTheme.brand500)
                .preferredColorScheme(appearance.colorScheme)
                .onAppear {
                    store.prepare()
                    if reminderDelegate == nil {
                        reminderDelegate = ReminderDelegate { router.openTodayFirstPractice = true }
                    }
                }
        }
    }
}
