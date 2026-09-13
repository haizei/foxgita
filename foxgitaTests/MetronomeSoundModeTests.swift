import Testing
@testable import foxgita

struct MetronomeSoundModeTests {
    @Test func exposesBeatCueModeVocabulary() {
        #expect(MetronomeSoundMode.standard.displayName == "标准")
        #expect(MetronomeSoundMode.penetrating.displayName == "穿透")
        #expect(MetronomeSoundMode.highNoise.displayName == "高噪声")
        #expect(MetronomeSoundMode.allCases == [.standard, .penetrating, .highNoise])
    }

    @Test func decodesLegacyValuesWithoutChangingSelection() {
        #expect(MetronomeSoundMode.decode("standard") == .standard)
        #expect(MetronomeSoundMode.decode("acousticGuitar") == .penetrating)
        #expect(MetronomeSoundMode.decode("drums") == .highNoise)
    }

    @Test func decodesStableValuesAndFallsBackSafely() {
        #expect(MetronomeSoundMode.standard.rawValue == "standard")
        #expect(MetronomeSoundMode.penetrating.rawValue == "penetrating")
        #expect(MetronomeSoundMode.highNoise.rawValue == "highNoise")
        #expect(MetronomeSoundMode.decode("penetrating") == .penetrating)
        #expect(MetronomeSoundMode.decode("highNoise") == .highNoise)
        #expect(MetronomeSoundMode.decode(nil) == .standard)
        #expect(MetronomeSoundMode.decode("future-mode") == .standard)
    }
}
