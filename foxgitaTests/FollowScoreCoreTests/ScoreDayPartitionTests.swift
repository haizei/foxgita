import Foundation
import Testing
#if canImport(GitaScoreCore)
@testable import GitaScoreCore
#else
@testable import foxgita
#endif

struct ScoreDayPartitionTests {
    @Test func intervalAcrossMidnightIsSplitWithoutAddingTimeToTheWrongDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let end = try #require(calendar.date(from: .init(year: 2026,month: 11,day: 2,hour: 0,minute: 0,second: 2)))
        let parts = ScoreDayPartition.split(endingAt: end,seconds: 3,calendar: calendar)
        #expect(parts.count == 2)
        #expect(parts[0].dayKey == "2026-11-01")
        #expect(parts[0].seconds == 1)
        #expect(parts[1].dayKey == "2026-11-02")
        #expect(parts[1].seconds == 2)
    }
}
