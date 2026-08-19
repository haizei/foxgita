import Foundation

struct PracticeClipDescriptor: Equatable {
    var id: String
    var fileName: String
    var createdAt: Date
    var deletedAt: Date?
}

enum PracticeClipQuery {
    static func visible(
        clips: [PracticeClipDescriptor], videoMode: Bool
    ) -> [PracticeClipDescriptor] {
        var seen = Set<String>()
        return clips
            .filter { $0.deletedAt == nil }
            .filter { MediaReviewMedia.isVideo(fileName: $0.fileName) == videoMode }
            .sorted { $0.createdAt > $1.createdAt }
            .filter { seen.insert($0.id).inserted }
    }

    static func timestamp(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh-Hans")
        formatter.timeZone = timeZone
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }
}
