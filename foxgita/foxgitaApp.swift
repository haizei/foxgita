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
    @State private var reviewRunner: ReviewJobRunner
    @State private var reminderDelegate: ReminderDelegate?
    private let container: ModelContainer
    private let liveMemory: LiveMemoryContext

    init() {
        let schema = Schema(versionedSchema: GitaSchemaV6.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            let container = try ModelContainer(
                for: schema, migrationPlan: GitaMigrationPlan.self, configurations: [config]
            )
            self.container = container
            let memoryRepo = SwiftDataMemoryRepository(context: container.mainContext)
            let liveMemory = LiveMemoryContext(repository: memoryRepo, context: container.mainContext)
            self.liveMemory = liveMemory
            let store = PracticeStore(
                repository: SwiftDataPracticeRepository(context: container.mainContext)
            )
            _store = State(initialValue: store)
            _reviewRunner = State(
                initialValue: ReviewJobRunner(
                    store: store,
                    generator: MediaReviewGenerator(client: MediaReviewClient(memory: liveMemory)),
                    videoGenerator: VideoDiagnosisGenerator(client: VideoDiagnosisClient(memory: liveMemory))
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
                .environment(reviewRunner)
                .environment(\.memoryContext, liveMemory)
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
