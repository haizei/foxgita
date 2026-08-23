import Foundation

enum JustCompletedCopy {
    static func minutesLabel(durationSec: Int, hasNote: Bool, mediaCount: Int) -> String {
        if durationSec <= 0, hasNote || mediaCount > 0 {
            return String(localized: "不足 1 分钟")
        }
        let minutes = Int(ceil(Double(max(durationSec, 0)) / 60.0))
        return String(localized: "\(minutes) 分钟")
    }

    static func summary(hasNote: Bool, fileNames: [String]) -> String {
        var parts: [String] = []
        if hasNote { parts.append(String(localized: "笔记")) }
        let audio = fileNames.filter { !MediaReviewMedia.isVideo(fileName: $0) }.count
        let video = fileNames.filter { MediaReviewMedia.isVideo(fileName: $0) }.count
        if audio > 0 { parts.append(String(localized: "录音 \(audio)")) }
        if video > 0 { parts.append(String(localized: "视频 \(video)")) }
        return parts.joined(separator: " · ")
    }
}
