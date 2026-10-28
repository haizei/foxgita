import Foundation

struct MetronomeVisualPreferences: Codable, Equatable {
    var beatModuleEnabled = true
    var pendulumEnabled = false
    var highlightStrong = true
    var highlightMedium = true
    var highlightNormal = true
    var barCounterVisible = false
    var hapticsEnabled = true
    var flashEnabled = false

    func highlights(_ kind: MetronomeBeatKind) -> Bool {
        switch kind {
        case .strong: highlightStrong
        case .medium: highlightMedium
        case .weak: highlightNormal
        case .mute: false
        }
    }
}

@MainActor @Observable
final class MetronomeVisualPreferencesStore {
    static let shared = MetronomeVisualPreferencesStore(defaults: PracticeTestEnvironment.defaults)
    static let storageKey = "gita.metronome.visualPreferences.v1"
    private(set) var value: MetronomeVisualPreferences
    @ObservationIgnored private let defaults: UserDefaults

    private struct Saved: Codable {
        let version: Int
        let preferences: MetronomeVisualPreferences
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(Saved.self, from: data),
           saved.version == 1 {
            value = saved.preferences
        } else {
            value = MetronomeVisualPreferences()
        }
    }

    func update(_ preference: MetronomeVisualPreferences) {
        do {
            let data = try JSONEncoder().encode(Saved(version: 1, preferences: preference))
            defaults.set(data, forKey: Self.storageKey)
            value = preference
        } catch {
            assertionFailure("Unable to encode metronome visual preferences: \(error)")
        }
    }
}
