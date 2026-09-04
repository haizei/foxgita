//
//  Models.swift
//  foxgita
//

import Foundation
import SwiftData

typealias TaskItem = GitaSchemaV13.TaskItem
typealias PracticeSession = GitaSchemaV13.PracticeSession
typealias RecordingRef = GitaSchemaV13.RecordingRef
typealias LocalProfile = GitaSchemaV13.LocalProfile
typealias MemoryItem = GitaSchemaV13.MemoryItem
typealias PracticeItem = GitaSchemaV13.PracticeItem
typealias Project = GitaSchemaV13.Project
typealias AIInvocationLog = GitaSchemaV13.AIInvocationLog

/// Per-record sync bookkeeping. Everything is `local` until a remote backend
/// exists; the field is here so migrating to sync later is not a schema break.
enum SyncState: String, Codable, Sendable {
    case local, pendingUpload, synced
}

enum ReviewStatus: String, Codable, Sendable {
    case none, pending, ready, failed
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
        @Relationship(deleteRule: .cascade, inverse: \GitaSchemaV3.RecordingRef.session)
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
        var session: GitaSchemaV3.PracticeSession?

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

enum GitaSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

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
        @Relationship(deleteRule: .cascade, inverse: \GitaSchemaV4.RecordingRef.session)
        var recordings: [GitaSchemaV4.RecordingRef]

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
            recordings: [GitaSchemaV4.RecordingRef] = [],
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
        var reviewStatusRaw: String = ReviewStatus.none.rawValue
        var reviewHighlight: String = ""
        var reviewFocus: String = ""
        var reviewNextAction: String = ""

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

        var reviewStatus: ReviewStatus {
            get { ReviewStatus(rawValue: reviewStatusRaw) ?? .none }
            set { reviewStatusRaw = newValue.rawValue }
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

enum GitaSchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }

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
        @Relationship(deleteRule: .cascade, inverse: \GitaSchemaV5.RecordingRef.session)
        var recordings: [GitaSchemaV5.RecordingRef]

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
            recordings: [GitaSchemaV5.RecordingRef] = [],
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
        var reviewStatusRaw: String = ReviewStatus.none.rawValue
        var reviewHighlight: String = ""
        var reviewFocus: String = ""
        var reviewNextAction: String = ""
        var reviewFindingsJSON: String = "[]"

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

        var reviewStatus: ReviewStatus {
            get { ReviewStatus(rawValue: reviewStatusRaw) ?? .none }
            set { reviewStatusRaw = newValue.rawValue }
        }

        var videoFindings: [VideoFinding] {
            get {
                guard let data = reviewFindingsJSON.data(using: .utf8),
                      let value = try? JSONDecoder().decode([VideoFinding].self, from: data) else {
                    return []
                }
                return value
            }
            set {
                reviewFindingsJSON =
                    (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]"
            }
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

/// V2 → V3 adds defaulted attributes and indexes; V3 → V4 adds defaulted
/// review fields on RecordingRef; V4 → V5 adds defaulted findings JSON;
/// V5 → V6 adds profileId, LocalProfile, and MemoryItem;
/// V6 → V7 adds LocalProfile.memoryConsentState;
/// V7 → V8 adds TaskItem.originKey;
/// V8 → V9 adds PracticeItem and optional RecordingRef.practiceItem;
/// V9 → V10 adds Project, PracticeItem.projectId, LocalProfile.pinnedProjectId;
/// V10 → V11 adds optional Project.stageVersionItemId and Project.finalVersionItemId;
/// V11 → V12 adds PracticeItem.stepsRaw;
/// V12 → V13 adds AIInvocationLog.
enum GitaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            GitaSchemaV2.self, GitaSchemaV3.self, GitaSchemaV4.self,
            GitaSchemaV5.self, GitaSchemaV6.self, GitaSchemaV7.self,
            GitaSchemaV8.self, GitaSchemaV9.self, GitaSchemaV10.self,
            GitaSchemaV11.self, GitaSchemaV12.self, GitaSchemaV13.self,
        ]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: GitaSchemaV2.self, toVersion: GitaSchemaV3.self),
            .lightweight(fromVersion: GitaSchemaV3.self, toVersion: GitaSchemaV4.self),
            .lightweight(fromVersion: GitaSchemaV4.self, toVersion: GitaSchemaV5.self),
            .lightweight(fromVersion: GitaSchemaV5.self, toVersion: GitaSchemaV6.self),
            .lightweight(fromVersion: GitaSchemaV6.self, toVersion: GitaSchemaV7.self),
            .lightweight(fromVersion: GitaSchemaV7.self, toVersion: GitaSchemaV8.self),
            .lightweight(fromVersion: GitaSchemaV8.self, toVersion: GitaSchemaV9.self),
            .lightweight(fromVersion: GitaSchemaV9.self, toVersion: GitaSchemaV10.self),
            .lightweight(fromVersion: GitaSchemaV10.self, toVersion: GitaSchemaV11.self),
            .lightweight(fromVersion: GitaSchemaV11.self, toVersion: GitaSchemaV12.self),
            .lightweight(fromVersion: GitaSchemaV12.self, toVersion: GitaSchemaV13.self),
        ]
    }
}
