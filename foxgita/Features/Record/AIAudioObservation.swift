import Foundation

struct AIAudioCue: Equatable {
    let side: AudioComparisonPlayback.Side
    let seconds: TimeInterval?
    let caption: String
}

struct AIAudioObservation: Equatable {
    static let header = "✦ AI 观察 · 基于这两段录音"

    let conclusion: String
    let stageCue: AIAudioCue
    let recentCue: AIAudioCue
    let usesAudioTimestamps: Bool
}

enum AIAudioObservationRules {
    static func observe(
        stageNote: String,
        recentNote: String,
        stageDuration: TimeInterval,
        recentDuration: TimeInterval,
        audioAvailable: Bool
    ) -> AIAudioObservation {
        let conclusion = conclusionText(
            stageNote: stageNote,
            recentNote: recentNote,
            stageDuration: stageDuration,
            recentDuration: recentDuration,
            audioAvailable: audioAvailable
        )
        if audioAvailable {
            let stageMark = firstClock(in: stageNote) ?? fallbackMark(duration: stageDuration, prefersKeyword: stageNote.contains("停顿"))
            let recentMark = firstClock(in: recentNote) ?? fallbackMark(duration: recentDuration, prefersKeyword: recentNote.contains("连贯"))
            return AIAudioObservation(
                conclusion: conclusion,
                stageCue: AIAudioCue(side: .a, seconds: stageMark, caption: caption("阶段版", stageMark)),
                recentCue: AIAudioCue(side: .b, seconds: recentMark, caption: caption("最近", recentMark)),
                usesAudioTimestamps: stageMark != nil && recentMark != nil
            )
        }
        return AIAudioObservation(
            conclusion: conclusion,
            stageCue: AIAudioCue(side: .a, seconds: nil, caption: "阶段版"),
            recentCue: AIAudioCue(side: .b, seconds: nil, caption: "最近"),
            usesAudioTimestamps: false
        )
    }

    static func firstClock(in text: String) -> TimeInterval? {
        let chars = Array(text)
        var index = 0
        while index < chars.count {
            if chars[index].isNumber {
                var end = index
                while end < chars.count, chars[end].isNumber { end += 1 }
                let width = end - index
                if width >= 1, width <= 2, end < chars.count, chars[end] == ":" {
                    let secondStart = end + 1
                    var secondEnd = secondStart
                    while secondEnd < chars.count, chars[secondEnd].isNumber { secondEnd += 1 }
                    if secondEnd - secondStart == 2,
                       let minutes = Int(String(chars[index..<end])),
                       let seconds = Int(String(chars[secondStart..<secondEnd])),
                       seconds < 60 {
                        return TimeInterval(minutes * 60 + seconds)
                    }
                }
                index = end
            } else {
                index += 1
            }
        }
        return nil
    }

    private static func fallbackMark(duration: TimeInterval, prefersKeyword: Bool) -> TimeInterval? {
        guard duration > 0 else { return nil }
        let ratio = prefersKeyword ? 0.4 : 0.5
        return (duration * ratio).rounded(.down)
    }

    private static func caption(_ name: String, _ seconds: TimeInterval?) -> String {
        guard let seconds else { return name }
        return "\(name) \(ProgressFirstFormat.clock(seconds))"
    }

    private static func conclusionText(
        stageNote: String,
        recentNote: String,
        stageDuration: TimeInterval,
        recentDuration: TimeInterval,
        audioAvailable: Bool
    ) -> String {
        let stagePaused = stageNote.contains("停顿")
        let recentFlowing = recentNote.contains("连贯")
        if stagePaused && recentFlowing {
            return "最近这一次更连贯，阶段版里还有明显停顿。"
        }
        if stagePaused {
            return "阶段版里有一处停顿，可以对照最近这次听。"
        }
        if recentFlowing {
            return "最近这一次更连贯。"
        }
        if audioAvailable, stageDuration > 0, recentDuration + 5 < stageDuration {
            return "最近这段更紧凑。"
        }
        return "两段都留了下来，可以对照着听哪里更顺。"
    }
}
