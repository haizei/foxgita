//
//  SchemaV7.swift
//  foxgita
//

import Foundation
import SwiftData

enum GitaSchemaV7: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(7, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [TaskItem.self, PracticeSession.self, RecordingRef.self, LocalProfile.self, MemoryItem.self]
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
        var profileId: String = ""

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
            profileId: String = "",
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
            self.profileId = profileId
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
        var profileId: String = ""
        @Relationship(deleteRule: .cascade, inverse: \GitaSchemaV7.RecordingRef.session)
        var recordings: [GitaSchemaV7.RecordingRef]

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
            recordings: [GitaSchemaV7.RecordingRef] = [],
            profileId: String = "",
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
            self.profileId = profileId
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

    @Model
    final class LocalProfile {
        @Attribute(.unique) var id: String
        var isActive: Bool
        var memoryConsent: Bool
        var memoryConsentState: String = ""
        var createdAt: Date
        var updatedAt: Date

        init(
            id: String = UUID().uuidString,
            isActive: Bool = true,
            memoryConsent: Bool = false,
            now: Date = Date()
        ) {
            self.id = id
            self.isActive = isActive
            self.memoryConsent = memoryConsent
            self.memoryConsentState = ""
            self.createdAt = now
            self.updatedAt = now
        }

        var consent: MemoryConsentState {
            get { MemoryConsentState(rawValue: memoryConsentState) ?? .undecided }
            set {
                memoryConsentState = newValue.rawValue
                memoryConsent = newValue == .enabled
                updatedAt = Date()
            }
        }
    }

    @Model
    final class MemoryItem {
        @Attribute(.unique) var id: String
        var profileId: String
        var kindRaw: String
        var key: String
        var summaryText: String
        var valueJSON: String
        var sourceType: String
        var sourceId: String
        var confidence: Double
        var importance: Double
        var expiresAt: Date?
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
        var schemaVersion: Int

        init(
            id: String = UUID().uuidString,
            profileId: String,
            kind: MemoryScope,
            key: String,
            summaryText: String,
            valueJSON: String = "",
            sourceType: String,
            sourceId: String,
            confidence: Double,
            importance: Double,
            expiresAt: Date? = nil,
            now: Date = Date(),
            schemaVersion: Int = 1
        ) {
            self.id = id
            self.profileId = profileId
            self.kindRaw = kind.rawValue
            self.key = key
            self.summaryText = summaryText
            self.valueJSON = valueJSON
            self.sourceType = sourceType
            self.sourceId = sourceId
            self.confidence = confidence
            self.importance = importance
            self.expiresAt = expiresAt
            self.createdAt = now
            self.updatedAt = now
            self.schemaVersion = schemaVersion
        }

        var kind: MemoryScope? { MemoryScope(rawValue: kindRaw) }
    }
}
