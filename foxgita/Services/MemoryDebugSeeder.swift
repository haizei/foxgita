import Foundation

enum MemorySeedCatalog {
    struct Seed {
        var key: String
        var kind: MemoryScope
        var summaryText: String
        var confidence: Double
        var importance: Double
    }

    static let items: [Seed] = [
        .init(key: "goal.current_song", kind: .goal, summaryText: "当前目标：《晴天》前奏", confidence: 1, importance: 1),
        .init(key: "practice.available_minutes", kind: .preference, summaryText: "通常可练 20 分钟", confidence: 1, importance: 0.8),
        .init(key: "technique.barre_chord.F", kind: .ability, summaryText: "F 和弦按弦清晰度仍需改善", confidence: 1, importance: 0.7),
    ]
}

#if DEBUG
enum MemoryDebugSeeder {
    static let defaultsKey = "gita.debug.memorySeed"

    @MainActor
    static func seedIfNeeded(
        defaults: UserDefaults,
        profile: LocalProfile,
        repository: MemoryRepository
    ) throws {
        guard defaults.bool(forKey: defaultsKey) else { return }
        profile.consent = .enabled
        for seed in MemorySeedCatalog.items {
            try repository.upsertDebug(
                MemoryItem(
                    profileId: profile.id,
                    kind: seed.kind,
                    key: seed.key,
                    summaryText: seed.summaryText,
                    sourceType: "debug_seed",
                    sourceId: seed.key,
                    confidence: seed.confidence,
                    importance: seed.importance
                )
            )
        }
        try repository.save()
    }
}
#endif
