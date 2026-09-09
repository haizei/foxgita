import Foundation

struct ContextFenceResult: Sendable {
    let text: String
    let warnings: [ContextWarning]
}

enum ContextFencer {
    static func fence(_ raw: String, limit: Int) -> ContextFenceResult {
        let normalized = raw.precomposedStringWithCompatibilityMapping
        let controlFiltered = removeUnsafeScalars(from: normalized)
        let neutralized = neutralizeProtocolText(in: controlFiltered.text)
        let truncated = truncate(neutralized.text, to: limit)

        var warnings: [ContextWarning] = []
        if controlFiltered.removed {
            warnings.append(.controlCharactersRemoved)
        }
        if neutralized.replaced {
            warnings.append(.protocolTextNeutralized)
        }
        if truncated.didTruncate {
            warnings.append(.truncated)
        }

        return ContextFenceResult(text: truncated.text, warnings: warnings)
    }

    static func removeUnsafeScalars(from text: String) -> (text: String, removed: Bool) {
        var scalars = String.UnicodeScalarView()
        var removed = false

        for scalar in text.unicodeScalars {
            if isUnsafeControl(scalar) {
                removed = true
            } else {
                scalars.append(scalar)
            }
        }

        return (String(scalars), removed)
    }

    static func neutralizeProtocolText(in text: String) -> (text: String, replaced: Bool) {
        let tags = replacingMatches(
            in: text,
            pattern: "(?is)<\\s*/?\\s*[a-z][a-z0-9_-]*\\b[^>]*>",
            with: "[untrusted-tag]"
        )
        let boundaries = replacingMatches(
            in: tags.text,
            pattern: "(?im)(^|\\r?\\n[\\t ]*\\r?\\n[\\t ]*)(assistant|system|developer|user|tool)\\s*:",
            with: "$1[untrusted-protocol-boundary] "
        )

        return (boundaries.text, tags.replaced || boundaries.replaced)
    }

    static func truncate(_ text: String, to limit: Int) -> (text: String, didTruncate: Bool) {
        let safeLimit = max(0, limit)
        guard text.count > safeLimit else { return (text, false) }
        return (String(text.prefix(safeLimit)), true)
    }

    private static func isUnsafeControl(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x0009, 0x000A, 0x000D:
            return false
        case 0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF:
            return true
        default:
            return CharacterSet.controlCharacters.contains(scalar)
        }
    }

    private static func replacingMatches(
        in text: String,
        pattern: String,
        with replacement: String
    ) -> (text: String, replaced: Bool) {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return (text, false)
        }

        let range = NSRange(text.startIndex..., in: text)
        guard expression.firstMatch(in: text, range: range) != nil else {
            return (text, false)
        }
        return (expression.stringByReplacingMatches(in: text, range: range, withTemplate: replacement), true)
    }
}
