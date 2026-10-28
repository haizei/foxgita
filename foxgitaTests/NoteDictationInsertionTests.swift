import Testing
@testable import foxgita

struct NoteDictationInsertionTests {
    @Test func staleSelectionUpperBoundFallsBackToAppend() {
        let oldText = "abcdef"
        let range = oldText.startIndex..<oldText.endIndex
        let result = NoteDictationInsertion.insert(
            "语音", into: "ab", replacing: range, capturedText: "ab"
        )
        #expect(result.text == "ab\n语音")
        #expect(result.caretOffset == 5)
    }

    @Test func insertionJoiningEmojiSuffixKeepsValidCaret() {
        let source = "👩👩结束"
        let caret = source.index(after: source.startIndex)
        let result = NoteDictationInsertion.insert(
            "\u{200D}", into: source, replacing: caret..<caret, capturedText: source
        )
        #expect(result.text == "👩\u{200D}👩结束")
        #expect(result.caretOffset == 1)
    }

    @Test func missingSelectionAppendsWithOneNewline() {
        let result = NoteDictationInsertion.insert(
            "新内容", into: "原文\n", replacing: nil, capturedText: "原文\n"
        )
        #expect(result.text == "原文\n新内容")
        #expect(result.caretOffset == 6)
    }

    @Test func staleIndexInsideEmojiFallsBackToAppend() {
        let oldText = "ab"
        let caret = oldText.index(after: oldText.startIndex)
        let result = NoteDictationInsertion.insert(
            "语音", into: "😀", replacing: caret..<caret, capturedText: "😀"
        )
        #expect(result.text == "😀\n语音")
        #expect(result.caretOffset == 4)
    }

    @Test func combiningTextKeepsCaretOnCharacterBoundary() {
        let source = "ex"
        let caret = source.index(after: source.startIndex)
        let result = NoteDictationInsertion.insert(
            "\u{301}", into: source, replacing: caret..<caret, capturedText: source
        )
        #expect(result.text == "e\u{301}x")
        #expect(result.caretOffset == 1)
    }

    @Test func insertsAtValidCaret() {
        let source = "前半后半"
        let caret = source.index(source.startIndex, offsetBy: 2)
        let result = NoteDictationInsertion.insert(
            "语音", into: source, replacing: caret..<caret, capturedText: source
        )
        #expect(result.text == "前半语音后半")
        #expect(result.caretOffset == 4)
    }

    @Test func staleCaretFromLongerTextAppendsWithoutCrashing() {
        let oldText = "之前输入过的笔记"
        let staleCaret = oldText.endIndex
        let result = NoteDictationInsertion.insert(
            "语音", into: "", replacing: staleCaret..<staleCaret, capturedText: ""
        )
        #expect(result.text == "语音")
        #expect(result.caretOffset == 2)
    }

    @Test func textChangedDuringRecordingPreservesChanges() {
        let source = "原文"
        let caret = source.startIndex
        let result = NoteDictationInsertion.insert(
            "语音", into: "已修改", replacing: caret..<caret, capturedText: source
        )
        #expect(result.text == "已修改\n语音")
        #expect(result.caretOffset == 6)
    }

    @Test func replacesSelectedTextAndKeepsUnicodeCaret() {
        let source = "😀旧词结尾"
        let lower = source.index(after: source.startIndex)
        let upper = source.index(lower, offsetBy: 2)
        let result = NoteDictationInsertion.insert(
            "新词", into: source, replacing: lower..<upper, capturedText: source
        )
        #expect(result.text == "😀新词结尾")
        #expect(result.caretOffset == 3)
    }
}
