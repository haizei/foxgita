/// Validates a TextSelection against its captured text before using its indices.
enum NoteDictationInsertion {
    struct Result {
        let text: String
        let caretOffset: Int
    }

    static func insert(
        _ dictation: String,
        into text: String,
        replacing range: Range<String.Index>?,
        capturedText: String
    ) -> Result {
        // TextField can retain a selection from a previous value. Never pass an
        // unvalidated index to distance, subscripting, or replaceSubrange.
        let boundaries = Array(text.indices) + [text.endIndex]
        guard text == capturedText, let range,
              let lower = boundaries.firstIndex(of: range.lowerBound),
              let upper = boundaries.firstIndex(of: range.upperBound),
              lower <= upper else {
            let separator = text.isEmpty || text.hasSuffix("\n") ? "" : "\n"
            let updated = text + separator + dictation
            return Result(text: updated, caretOffset: updated.count)
        }

        // Rebuild indices from the current string, including Unicode boundaries.
        let prefix = String(text[..<boundaries[lower]]) + dictation
        let updated = prefix + text[boundaries[upper]...]
        // Inserting a combining mark can merge characters on either side.
        let caret = updated.indices.first {
            $0.utf16Offset(in: updated) >= prefix.utf16.count
        } ?? updated.endIndex
        return Result(text: updated, caretOffset: updated.distance(from: updated.startIndex, to: caret))
    }
}
