//
//  Models.swift
//  foxgita
//

import Foundation
import SwiftData

typealias TaskItem = GitaSchemaV3.TaskItem
typealias PracticeSession = GitaSchemaV3.PracticeSession
typealias RecordingRef = GitaSchemaV3.RecordingRef

/// Per-record sync bookkeeping. Everything is `local` until a remote backend
/// exists; the field is here so migrating to sync later is not a schema break.
enum SyncState: String, Codable, Sendable {
    case local, pendingUpload, synced
}

enum GitaSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [TaskItem.self, PracticeSession.self, RecordingRef.self]
    }

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

        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var deletedAt: Date?
        var syncStateRaw: String = SyncState.local.rawValue

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
            isTemplate: Bool = false,
            now: Date = Date()
        ) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.categoryRaw = category.rawValue
            self.targetMin = targetMin
            self.defaultBpm = defaultBpm
            self.timeSig = timeSig
            self.stepsRaw = StepCoding.encode(steps)
            self.statusRaw = status.rawValue
            self.startedOn = startedOn
            self.sortOrder = sortOrder
            self.isTemplate = isTemplate
            self.createdAt = now
            self.updatedAt = now
            self.syncStateRaw = SyncState.local.rawValue
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
            get { StepCoding.decode(stepsRaw) }
            set { stepsRaw = StepCoding.encode(newValue) }
        }

        var syncState: SyncState {
            get { SyncState(rawValue: syncStateRaw) ?? .local }
            set { syncStateRaw = newValue.rawValue }
        }

        var isDeleted: Bool { deletedAt != nil }

        /// Call after any mutation so sync can order writes.
        func touch(_ now: Date = Date()) {
            updatedAt = now
            syncState = .local
        }
    }

    @Model
    final class PracticeSession {
        #Index<PracticeSession>([\.endedAt], [\.taskId])

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

        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var deletedAt: Date?
        var syncStateRaw: String = SyncState.local.rawValue

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
            recordings: [RecordingRef] = [],
            now: Date = Date()
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
            self.stepsSnapshotRaw = StepCoding.encode(steps)
            self.noteText = noteText
            self.recordings = recordings
            self.createdAt = now
            self.updatedAt = now
            self.syncStateRaw = SyncState.local.rawValue
        }

        var category: PracticeCategory {
            PracticeCategory(rawValue: categoryRaw) ?? .chord
        }

        var steps: [String] { StepCoding.decode(stepsSnapshotRaw) }

        var syncState: SyncState {
            get { SyncState(rawValue: syncStateRaw) ?? .local }
            set { syncStateRaw = newValue.rawValue }
        }

        var durationMinutes: Int {
            guard durationSec > 0 else { return 0 }
            return max(1, Int(ceil(Double(durationSec) / 60.0)))
        }
    }

    @Model
    final class RecordingRef {
        @Attribute(.unique) var id: String
        /// File name only — the sandbox container path changes between installs,
        /// so the directory is resolved at runtime by `RecordingStore`.
        var fileName: String
        var bytes: Int
        var durationSec: Int = 0
        var createdAt: Date
        var label: String
        var session: PracticeSession?

        var updatedAt: Date = Date()
        var deletedAt: Date?
        var syncStateRaw: String = SyncState.local.rawValue

        init(
            id: String = UUID().uuidString,
            fileName: String,
            bytes: Int,
            durationSec: Int = 0,
            createdAt: Date = Date(),
            label: String = ""
        ) {
            self.id = id
            self.fileName = fileName
            self.bytes = bytes
            self.durationSec = durationSec
            self.createdAt = createdAt
            self.label = label
            self.updatedAt = createdAt
            self.syncStateRaw = SyncState.local.rawValue
        }

        var syncState: SyncState {
            get { SyncState(rawValue: syncStateRaw) ?? .local }
            set { syncStateRaw = newValue.rawValue }
        }

        var fileURL: URL { RecordingStore.url(for: fileName) }

        var durationLabel: String {
            guard durationSec > 0 else { return String(localized: "时长未知") }
            return String(format: "%d:%02d", durationSec / 60, durationSec % 60)
        }

        var sizeLabel: String {
            if bytes < 1024 { return "\(bytes) B" }
            return String(format: "%.1f KB", Double(bytes) / 1024)
        }
    }
}

enum StepCoding {
    static func encode(_ steps: [String]) -> String {
        (try? String(data: JSONEncoder().encode(steps), encoding: .utf8)) ?? "[]"
    }

    static func decode(_ raw: String) -> [String] {
        guard let data = raw.data(using: .utf8),
              let value = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return value
    }
}

/// V2 → V3 only adds defaulted attributes and indexes, so the stage is
/// lightweight. It exists so shipped stores upgrade in place instead of being
/// deleted, which is what the old seed logic did.
enum GitaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [GitaSchemaV2.self, GitaSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [MigrationStage.lightweight(fromVersion: GitaSchemaV2.self, toVersion: GitaSchemaV3.self)]
    }
}
