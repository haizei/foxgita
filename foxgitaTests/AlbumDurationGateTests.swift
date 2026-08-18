import Testing
@testable import foxgita

struct AlbumDurationGateTests {
    @Test func rejectsBelowThirty() {
        #expect(AlbumDurationGate.verdict(durationSec: 29) == .tooShort)
        #expect(AlbumDurationGate.verdict(durationSec: 1) == .tooShort)
    }

    @Test func acceptsClosedRange() {
        #expect(AlbumDurationGate.verdict(durationSec: 30) == .ok)
        #expect(AlbumDurationGate.verdict(durationSec: 600) == .ok)
        #expect(AlbumDurationGate.verdict(durationSec: 180) == .ok)
    }

    @Test func rejectsAboveTenMinutes() {
        #expect(AlbumDurationGate.verdict(durationSec: 601) == .tooLong)
    }

    @Test func unknownWhenNonPositive() {
        #expect(AlbumDurationGate.verdict(durationSec: 0) == .unknown)
        #expect(AlbumDurationGate.verdict(durationSec: -3) == .unknown)
    }
}
