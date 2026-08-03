//
//  Models.swift
//  foxgita
//

import Foundation
import SwiftData

@Model
final class TaskItem {
    @Attribute(.unique) var id: String
    var title: String
    var subtitle: String
    var categoryRaw: String
    var targetMin: Int
    var defaultBpm: Int
    var timeSig: String
    var stepsRaw: String
    var statusRaw: String
    var startedOn: Date?
    var sortOrder: Int
    var isTemplate: Bool

    init(
        id: String = UUID().uuidString,
        title: String,
        subtitle: String,
        category: PracticeCategory,
        targetMin: Int,
        defaultBpm: Int = 80,
        timeSig: String = "4/4",
        steps: [String] = [],
        status: TaskStatus = .active,
        startedOn: Date? = Date(),
        sortOrder: Int = 0,
        isTemplate: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.categoryRaw = category.rawValue
        self.targetMin = targetMin
        self.defaultBpm = defaultBpm
        self.timeSig = timeSig
        self.stepsRaw = Self.encode(steps)
        self.statusRaw = status.rawValue
        self.startedOn = startedOn
        self.sortOrder = sortOrder
        self.isTemplate = isTemplate
    }

    var category: PracticeCategory {
        get { PracticeCategory(rawValue: categoryRaw) ?? .chord }
        set { categoryRaw = newValue.rawValue }
    }

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var steps: [String] {
        get { Self.decode(stepsRaw) }
        set { stepsRaw = Self.encode(newValue) }
    }

    private static func encode(_ steps: [String]) -> String {
        (try? String(data: JSONEncoder().encode(steps), encoding: .utf8)) ?? "[]"
    }

    private static func decode(_ raw: String) -> [String] {
        guard let data = raw.data(using: .utf8),
              let v = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return v
    }
}

@Model
final class PracticeSession {
    @Attribute(.unique) var id: String
    var taskId: String
    var taskTitle: String
    var categoryRaw: String
    var startedAt: Date
    var endedAt: Date
    var durationSec: Int
    var bpm: Int
    var timeSig: String
    var stepsSnapshotRaw: String
    var noteText: String
    @Relationship(deleteRule: .cascade, inverse: \RecordingRef.session)
    var recordings: [RecordingRef]

    init(
        id: String = UUID().uuidString,
        taskId: String,
        taskTitle: String,
        category: PracticeCategory,
        startedAt: Date,
        endedAt: Date,
        durationSec: Int,
        bpm: Int,
        timeSig: String,
        steps: [String],
        noteText: String = "",
        recordings: [RecordingRef] = []
    ) {
        self.id = id
        self.taskId = taskId
        self.taskTitle = taskTitle
        self.categoryRaw = category.rawValue
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSec = durationSec
        self.bpm = bpm
        self.timeSig = timeSig
        self.stepsSnapshotRaw = (try? String(data: JSONEncoder().encode(steps), encoding: .utf8)) ?? "[]"
        self.noteText = noteText
        self.recordings = recordings
    }

    var category: PracticeCategory {
        PracticeCategory(rawValue: categoryRaw) ?? .chord
    }

    var durationMinutes: Int {
        guard durationSec > 0 else { return 0 }
        return max(1, Int(ceil(Double(durationSec) / 60.0)))
    }
}

@Model
final class RecordingRef {
    @Attribute(.unique) var id: String
    var fileName: String
    var bytes: Int
    var createdAt: Date
    var label: String
    var session: PracticeSession?

    init(
        id: String = UUID().uuidString,
        fileName: String,
        bytes: Int,
        createdAt: Date = Date(),
        label: String = ""
    ) {
        self.id = id
        self.fileName = fileName
        self.bytes = bytes
        self.createdAt = createdAt
        self.label = label
    }

    var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    var sizeLabel: String {
        if bytes < 1024 { return "\(bytes) B" }
        return String(format: "%.1f KB", Double(bytes) / 1024)
    }
}
