import Foundation

struct AudioComparisonConfirmation: Codable, Equatable {
    let projectId: UUID
    let stageItemId: UUID
    let stageClipId: String
    let recentItemId: UUID
    let recentClipId: String
    let fragment: String

    init(projectId: UUID, stage: AudioBenchmarkTrack, recent: AudioBenchmarkTrack, fragment: String) {
        self.projectId = projectId
        stageItemId = stage.itemId
        stageClipId = stage.clip.id
        recentItemId = recent.itemId
        recentClipId = recent.clip.id
        self.fragment = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func matches(projectId: UUID, stage: AudioBenchmarkTrack, recent: AudioBenchmarkTrack) -> Bool {
        self.projectId == projectId
            && stageItemId == stage.itemId && stageClipId == stage.clip.id
            && recentItemId == recent.itemId && recentClipId == recent.clip.id
            && !fragment.isEmpty
    }
}

enum AudioComparisonConfirmationStore {
    private static func key(_ projectId: UUID) -> String {
        "project.audio-comparison.confirmation.\(projectId.uuidString)"
    }

    static func load(projectId: UUID, defaults: UserDefaults = .standard) -> AudioComparisonConfirmation? {
        guard let data = defaults.data(forKey: key(projectId)),
              let value = try? JSONDecoder().decode(AudioComparisonConfirmation.self, from: data),
              value.projectId == projectId else {
            return nil
        }
        return value
    }

    static func save(_ confirmation: AudioComparisonConfirmation, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(confirmation) else { return }
        defaults.set(data, forKey: key(confirmation.projectId))
    }

    static func clear(projectId: UUID, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(projectId))
    }
}
