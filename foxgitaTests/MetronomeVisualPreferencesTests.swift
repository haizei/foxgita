import Foundation
import Testing
@testable import foxgita

@MainActor
struct MetronomeVisualPreferencesTests {
    @Test func combinedVisualPreferencesSurviveReopeningWithoutChangingSound() throws {
        let suite = "visual-preferences-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = MetronomeVisualPreferencesStore(defaults: defaults)
        var preference = first.value
        #expect(preference.beatModuleEnabled)
        #expect(!preference.pendulumEnabled)
        #expect(!preference.barCounterVisible)
        preference.pendulumEnabled = true
        preference.highlightNormal = false
        preference.barCounterVisible = true
        first.update(preference)
        let reopened = MetronomeVisualPreferencesStore(defaults: defaults)
        #expect(reopened.value == preference)
        #expect(reopened.value.beatModuleEnabled && reopened.value.pendulumEnabled)
        let engine = MetronomeEngine()
        #expect(engine.soundPreset == .realMetronome)
        #expect(engine.volume == 80)
    }
}
