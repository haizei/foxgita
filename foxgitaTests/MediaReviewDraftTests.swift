import Testing
@testable import foxgita

struct MediaReviewDraftTests {
    @Test func normalizeHappyPathTrims() throws {
        let draft = try MediaReviewDraft.normalize(
            .init(highlight: "  节奏稳  ", focus: " F 慢 ", nextAction: " 70 BPM ")
        )
        #expect(draft.highlight == "节奏稳")
        #expect(draft.focus == "F 慢")
        #expect(draft.nextAction == "70 BPM")
    }

    @Test func normalizeRejectsEmptyField() {
        #expect(throws: MediaReviewDraftError.emptyField) {
            try MediaReviewDraft.normalize(
                .init(highlight: "好", focus: "   ", nextAction: "练")
            )
        }
        #expect(throws: MediaReviewDraftError.emptyField) {
            try MediaReviewDraft.normalize(
                .init(highlight: nil, focus: "a", nextAction: "b")
            )
        }
    }

    @Test func normalizeTruncatesTo80Characters() throws {
        let long = String(repeating: "字", count: 90)
        let draft = try MediaReviewDraft.normalize(
            .init(highlight: long, focus: "改", nextAction: "练")
        )
        #expect(draft.highlight.count == 80)
        #expect(draft.highlight == String(repeating: "字", count: 80))
    }
}
