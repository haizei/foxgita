import Testing
@testable import foxgita

struct VideoDiagnosisDraftTests {
    @Test func normalizeMidVideoInvertedTimestamps() throws {
        let draft = try VideoDiagnosisDraft.normalize(
            .init(
                highlight: "稳", focus: "F", nextAction: "慢练",
                findings: [
                    .init(
                        startSec: 40, endSec: 20,
                        title: "按弦", evidence: "杂音",
                        cause: "离品丝", action: "靠近"
                    ),
                ]
            ),
            durationSec: 180
        )
        #expect(draft.findings.count == 1)
        #expect(draft.findings[0].startSec == 40)
        #expect(draft.findings[0].endSec == 60)
    }

    @Test func normalizeHappyPathClampsAndSorts() throws {
        let draft = try VideoDiagnosisDraft.normalize(
            .init(
                highlight: " 稳 ",
                focus: " F ",
                nextAction: " 慢练 ",
                findings: [
                    .init(
                        startSec: 240, endSec: 200,
                        title: " 切换迟缓 ", evidence: "听到断音",
                        cause: "抬指高", action: "提前准备"
                    ),
                    .init(
                        startSec: 10, endSec: 40,
                        title: "节奏偏慢", evidence: "拍点落后",
                        cause: "抢看谱", action: "跟着节拍器"
                    ),
                ]
            ),
            durationSec: 180
        )
        #expect(draft.highlight == "稳")
        #expect(draft.findings.count == 2)
        #expect(draft.findings[0].startSec == 10)
        #expect(draft.findings[1].startSec == 180)
        #expect(draft.findings[1].endSec == 180)
        #expect(draft.findings[0].endSec - draft.findings[0].startSec >= 10)
        #expect(draft.findings[0].endSec - draft.findings[0].startSec <= 30)
    }

    @Test func normalizeDropsIncompleteFindingsAndAllowsEmpty() throws {
        let draft = try VideoDiagnosisDraft.normalize(
            .init(
                highlight: "稳", focus: "无明确问题", nextAction: "保持",
                findings: [
                    .init(startSec: 1, endSec: 20, title: "", evidence: "x", cause: "y", action: "z"),
                ]
            ),
            durationSec: 60
        )
        #expect(draft.findings.isEmpty)
    }

    @Test func normalizeRejectsEmptySummary() {
        #expect(throws: VideoDiagnosisDraftError.emptyField) {
            try VideoDiagnosisDraft.normalize(
                .init(highlight: " ", focus: "a", nextAction: "b", findings: nil),
                durationSec: 30
            )
        }
    }

    @Test func normalizeCapsFiveFindingsAndTruncates() throws {
        let items = (0..<8).map { i in
            VideoDiagnosisDraft.RawFinding(
                startSec: i * 10, endSec: i * 10 + 15,
                title: "t\(i)", evidence: "e", cause: "c", action: "a"
            )
        }
        let long = String(repeating: "字", count: 90)
        let draft = try VideoDiagnosisDraft.normalize(
            .init(highlight: long, focus: "f", nextAction: "n", findings: items),
            durationSec: 400
        )
        #expect(draft.findings.count == 5)
        #expect(draft.highlight.count == 80)
    }
}
