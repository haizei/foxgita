import Testing
@testable import foxgita

struct MetronomeSoundPresetTests {
    @Test func presetNamesAndOrderMatchSoundSheetContract() {
        #expect(MetronomeSoundPreset.allCases == [
            .realMetronome, .electronicMetronome, .windChime, .woodblock,
            .drumKit1, .drumKit2, .handClap,
        ])
        #expect(MetronomeSoundPreset.allCases.map(\.displayName) == [
            "真实节拍器", "电子节拍器", "风铃声", "木鱼声",
            "架子鼓1", "架子鼓2", "拍手",
        ])
    }

    @Test func persistedPresetValuesRoundTrip() {
        let rawValues = [
            "realMetronome", "electronicMetronome", "windChime", "woodblock",
            "drumKit1", "drumKit2", "handClap",
        ]
        #expect(MetronomeSoundPreset.allCases.map(\.rawValue) == rawValues)
        for rawValue in rawValues {
            #expect(MetronomeSoundPreset.decode(rawValue).rawValue == rawValue)
        }
    }

    @Test func legacyValuesPreserveClosestSoundMeaning() {
        #expect(MetronomeSoundPreset.decode("standard") == .realMetronome)
        #expect(MetronomeSoundPreset.decode("penetrating") == .electronicMetronome)
        #expect(MetronomeSoundPreset.decode("acousticGuitar") == .electronicMetronome)
        #expect(MetronomeSoundPreset.decode("highNoise") == .handClap)
        #expect(MetronomeSoundPreset.decode("drums") == .handClap)
        #expect(MetronomeSoundPreset.decode(nil) == .realMetronome)
        #expect(MetronomeSoundPreset.decode("future-preset") == .realMetronome)
    }

    @Test func currentSoundSheetKeepsLegacySelectionsUntilSamplesArrive() {
        #expect(MetronomeSoundMode.allCases == [.standard, .penetrating, .highNoise])
    }
}
