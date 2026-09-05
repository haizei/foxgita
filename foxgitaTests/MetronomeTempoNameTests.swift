import Testing
@testable import foxgita

struct MetronomeTempoNameTests {
    @Test func mapsCommonTempos() {
        #expect(MetronomeTempoName.name(for: 80) == "Andantino")
        #expect(MetronomeTempoName.name(for: 76) == "Andantino")
        #expect(MetronomeTempoName.name(for: 120) == "Allegro")
        #expect(MetronomeTempoName.name(for: 60) == "Adagio")
    }

    @Test func clampsBeforeLookup() {
        #expect(MetronomeTempoName.name(for: 10) == "Largo")
        #expect(MetronomeTempoName.name(for: 250) == "Presto")
    }

    @Test func boundaryTransitions() {
        #expect(MetronomeTempoName.name(for: 59) == "Largo")
        #expect(MetronomeTempoName.name(for: 75) == "Adagio")
        #expect(MetronomeTempoName.name(for: 87) == "Andantino")
        #expect(MetronomeTempoName.name(for: 107) == "Moderato")
    }
}
