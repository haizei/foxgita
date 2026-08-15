//
//  SchemaV2.swift
//  foxgita
//
//  The shape shipped before sync-oriented metadata existed. Kept only so the
//  migration plan has something to migrate *from* — nothing outside the
//  migration and its tests should reference these types.
//

import Foundation
import SwiftData

enum GitaSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

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

        init(
            id: String, title: String, subtitle: String, categoryRaw: String,
            targetMin: Int, defaultBpm: Int, timeSig: String, stepsRaw: String,
            statusRaw: String, startedOn: Date?, sortOrder: Int, isTemplate: Bool
        ) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.categoryRaw = categoryRaw
            self.targetMin = targetMin
            self.defaultBpm = defaultBpm
            self.timeSig = timeSig
            self.stepsRaw = stepsRaw
            self.statusRaw = statusRaw
            self.startedOn = startedOn
            self.sortOrder = sortOrder
            self.isTemplate = isTemplate
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
        @Relationship(deleteRule: .cascade, inverse: \GitaSchemaV2.RecordingRef.session)
        var recordings: [GitaSchemaV2.RecordingRef]

        init(
            id: String, taskId: String, taskTitle: String, categoryRaw: String,
            startedAt: Date, endedAt: Date, durationSec: Int, bpm: Int,
            timeSig: String, stepsSnapshotRaw: String, noteText: String,
            recordings: [GitaSchemaV2.RecordingRef] = []
        ) {
            self.id = id
            self.taskId = taskId
            self.taskTitle = taskTitle
            self.categoryRaw = categoryRaw
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.durationSec = durationSec
            self.bpm = bpm
            self.timeSig = timeSig
            self.stepsSnapshotRaw = stepsSnapshotRaw
            self.noteText = noteText
            self.recordings = recordings
        }
    }

    @Model
    final class RecordingRef {
        @Attribute(.unique) var id: String
        var fileName: String
        var bytes: Int
        var createdAt: Date
        var label: String
        var session: GitaSchemaV2.PracticeSession?

        init(id: String, fileName: String, bytes: Int, createdAt: Date, label: String) {
            self.id = id
            self.fileName = fileName
            self.bytes = bytes
            self.createdAt = createdAt
            self.label = label
        }
    }
}
