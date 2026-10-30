#if DEBUG
import AVFoundation
import Foundation

/// Deterministic, in-memory project data for the three-screen UI journey.
@MainActor
enum ProjectDetailUITestFixture {
    static let launchArgument = "-ProjectDetailUITestFixture"
    static let projectName = "三屏验收项目"

    static func seed(store: PracticeStore, router: AppRouter) throws {
        let calendar = Calendar.current
        let now = Date()
        let firstDay = calendar.date(byAdding: .day, value: -14, to: now)!
        let recentDay = calendar.date(byAdding: .day, value: -1, to: now)!
        let project = try store.createProject(name: projectName, goal: "完整演奏", now: firstDay)
        try store.updateProjectFocus(id: project.id, currentFocus: "练熟副歌", now: recentDay)

        let first = try store.createTodayPracticeItem(projectId: project.id, now: firstDay, calendar: calendar)
        try store.savePracticeItem(id: first.id, durationSeconds: 600, note: "先练慢速节奏", now: firstDay)
        try attachTone(to: first.id, store: store, at: firstDay)
        try attachTone(to: first.id, store: store, at: firstDay.addingTimeInterval(60))

        let recent = try store.createTodayPracticeItem(projectId: project.id, now: recentDay, calendar: calendar)
        try store.savePracticeItem(id: recent.id, durationSeconds: 900, note: "副歌更连贯", now: recentDay)
        try attachTone(to: recent.id, store: store, at: recentDay)
        try store.setProjectStageVersion(projectId: project.id, itemId: first.id, now: recentDay)

        router.selectedTab = .record
        router.recordSegment = .project
        router.recordPath = [.projectDetail(projectId: project.id)]
    }

    private static func attachTone(to itemId: UUID, store: PracticeStore, at date: Date) throws {
        let fileName = RecordingStore.newFileName(extension: "caf")
        let url = RecordingStore.url(for: fileName)
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 8_000,
            channels: 1,
            interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8_000)!
        buffer.frameLength = 8_000
        let channel = buffer.floatChannelData![0]
        for index in 0..<Int(buffer.frameLength) {
            channel[index] = Float(sin(Double(index) * 2 * .pi * 220 / 8_000) * 0.08)
        }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        try store.attachRecording(
            RecordingRef(
                fileName: fileName,
                bytes: RecordingStore.byteSize(of: url),
                durationSec: 1,
                createdAt: date
            ),
            toPracticeItemId: itemId,
            now: date
        )
    }
}
#endif
