import Foundation
import SwiftData
import Testing
@testable import foxgita

@MainActor
struct MemoryDebugSeederTests {
    @Test func catalogHasThreeAppendixBKeys() {
        #expect(MemorySeedCatalog.items.map(\.key) == [
            "goal.current_song",
            "practice.available_minutes",
            "technique.barre_chord.F",
        ])
    }

    @Test func seedIfNeededNoopsUnlessFlagSet() throws {
        let schema = Schema(versionedSchema: GitaSchemaV9.self)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let profile = LocalProfile(id: "p1")
        context.insert(profile)
        try context.save()
        let repo = SwiftDataMemoryRepository(context: context)
        let defaults = UserDefaults(suiteName: "seed.\(UUID().uuidString)")!

        try MemoryDebugSeeder.seedIfNeeded(defaults: defaults, profile: profile, repository: repo)
        #expect(profile.memoryConsent == false)
        #expect(try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date()).isEmpty)

        defaults.set(true, forKey: MemoryDebugSeeder.defaultsKey)
        try MemoryDebugSeeder.seedIfNeeded(defaults: defaults, profile: profile, repository: repo)
        try repo.save()
        #expect(profile.consent == .enabled)
        #expect(profile.memoryConsent == true)
        let goals = try repo.fetch(profileId: "p1", scopes: [.goal, .preference, .ability], matching: "", now: Date())
        #expect(Set(goals.map(\.key)) == Set(MemorySeedCatalog.items.map(\.key)))
    }
}
