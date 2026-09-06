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
    private let memoryRepo: SwiftDataMemoryRepository
    private let memoryStore: MemoryStore
    private let invocationStore: AIInvocationStore
    private let coordinator: MemoryConsentCoordinator
    private let durationPreferenceSync: DurationPreferenceSync

    init() {
        let schema = Schema(versionedSchema: GitaSchemaV17.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            let container = try ModelContainer(
                for: schema, migrationPlan: GitaMigrationPlan.self, configurations: [config]
            )
            self.container = container
            let memoryRepo = SwiftDataMemoryRepository(context: container.mainContext)
            self.memoryRepo = memoryRepo
            let liveMemory = LiveMemoryContext(repository: memoryRepo, context: container.mainContext)
            self.liveMemory = liveMemory
            let taskMemorySync = TaskMemorySync(
                repository: memoryRepo, context: container.mainContext
            )
            let aiCandidateSync = AICandidateSync(
                repository: memoryRepo, context: container.mainContext
            )
            let durationPreferenceSync = DurationPreferenceSync(
                repository: memoryRepo, context: container.mainContext
            )
            let memoryStore = MemoryStore(
                repository: memoryRepo,
                context: container.mainContext,
                taskMemorySync: taskMemorySync
            )
            self.memoryStore = memoryStore
            self.durationPreferenceSync = durationPreferenceSync
            self.coordinator = MemoryConsentCoordinator(store: memoryStore)
            let invocationStore = AIInvocationStore(context: container.mainContext)
            self.invocationStore = invocationStore
            let invocationLog = LiveAIInvocationLog(store: invocationStore)
            let store = PracticeStore(
                repository: SwiftDataPracticeRepository(context: container.mainContext),
                taskMemorySync: taskMemorySync,
                aiCandidateSync: aiCandidateSync,
                invocationStore: invocationStore
            )
            _store = State(initialValue: store)
            _reviewRunner = State(
                initialValue: ReviewJobRunner(
                    store: store,
                    generator: MediaReviewGenerator(
                        client: MediaReviewClient(memory: liveMemory, log: invocationLog),
                        log: invocationLog
                    ),
                    videoGenerator: VideoDiagnosisGenerator(
                        client: VideoDiagnosisClient(memory: liveMemory, log: invocationLog),
                        log: invocationLog
                    )
                )
            )
        } catch {
            fatalError("SwiftData failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .memoryConsentGate()
                .environment(router)
                .environment(store)
                .environment(reviewRunner)
                .environment(\.memoryContext, liveMemory)
                .environment(memoryStore)
                .environment(invocationStore)
                .environment(coordinator)
                .environment(\.durationPreferenceSync, durationPreferenceSync)
                .modelContainer(container)
                .tint(GitaTheme.brand500)
                .preferredColorScheme(appearance.colorScheme)
                .onAppear {
                    store.prepare()
                    #if DEBUG
                    if let profile = try? store.activeProfileForDebug() {
                        try? MemoryDebugSeeder.seedIfNeeded(
                            defaults: .standard,
                            profile: profile,
                            repository: memoryRepo
                        )
                    }
                    #endif
                    memoryStore.reload()
                    if reminderDelegate == nil {
                        reminderDelegate = ReminderDelegate { router.openTodayFirstPractice = true }
                    }
                }
        }
    }
}
