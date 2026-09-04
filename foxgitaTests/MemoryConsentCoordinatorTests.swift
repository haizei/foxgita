import Foundation
import SwiftData
import Testing
@testable import foxgita

@MainActor
struct MemoryConsentCoordinatorTests {
    private func make() throws -> (MemoryConsentCoordinator, MemoryStore, LocalProfile) {
        let schema = Schema(versionedSchema: GitaSchemaV12.self)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let profile = LocalProfile(id: "p1")
        context.insert(profile)
        try context.save()
        let repo = SwiftDataMemoryRepository(context: context)
        let store = MemoryStore(repository: repo, context: context)
        store.reload()
        return (MemoryConsentCoordinator(store: store), store, profile)
    }

    @Test func proceedWithoutSheetWhenAlreadyDecided() async throws {
        let (coordinator, store, _) = try make()
        #expect(store.setConsent(.disabled))
        let result = await coordinator.ensureDecided()
        #expect(result == .proceed)
        #expect(coordinator.isPresented == false)
    }

    @Test func undecidedWaitsThenEnableContinues() async throws {
        let (coordinator, store, _) = try make()
        #expect(store.consent == .undecided)
        let task = Task { await coordinator.ensureDecided() }
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(coordinator.isPresented == true)
        coordinator.chooseEnabled()
        let result = await task.value
        #expect(result == .proceed)
        #expect(store.consent == .enabled)
        #expect(coordinator.isPresented == false)
    }

    @Test func chooseDisabledAfterEnsureDecidedProceedsWithDisabledConsent() async throws {
        let (coordinator, store, _) = try make()
        #expect(store.consent == .undecided)
        let task = Task { await coordinator.ensureDecided() }
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(coordinator.isPresented == true)
        coordinator.chooseDisabled()
        let result = await task.value
        #expect(result == .proceed)
        #expect(store.consent == .disabled)
        #expect(coordinator.isPresented == false)
    }

    @Test func chooseDisabledAfterCancelledWaiterStillResumes() async throws {
        let (coordinator, store, _) = try make()
        let task = Task { await coordinator.ensureDecided() }
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(coordinator.isPresented == true)
        task.cancel()
        coordinator.chooseDisabled()
        let result = await task.value
        #expect(result == .proceed)
        #expect(store.consent == .disabled)
        #expect(coordinator.isPresented == false)
    }

    @Test func concurrentEnsureDecidedBothProceedAfterOneEnable() async throws {
        let (coordinator, store, _) = try make()
        #expect(store.consent == .undecided)
        let first = Task { await coordinator.ensureDecided() }
        let second = Task { await coordinator.ensureDecided() }
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(coordinator.isPresented == true)
        coordinator.chooseEnabled()
        let r1 = await first.value
        let r2 = await second.value
        #expect(r1 == .proceed)
        #expect(r2 == .proceed)
        #expect(store.consent == .enabled)
        #expect(coordinator.isPresented == false)
    }
}
