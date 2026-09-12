//
//  SchemaV19.swift
//  foxgita
//

import Foundation
import SwiftData

/// Adds a plan reference to metronome training history. V18 is intentionally
/// kept byte-for-byte compatible with the first development build that wrote
/// tempo-ramp data, so those stores can be identified and migrated.
enum GitaSchemaV19: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(19, 0, 0) }

    typealias TaskItem = GitaSchemaV18.TaskItem
    typealias PracticeSession = GitaSchemaV18.PracticeSession
    typealias RecordingRef = GitaSchemaV18.RecordingRef
    typealias LocalProfile = GitaSchemaV18.LocalProfile
    typealias MemoryItem = GitaSchemaV18.MemoryItem
    typealias PracticeItem = GitaSchemaV18.PracticeItem
    typealias Project = GitaSchemaV18.Project
    typealias AIInvocationLog = GitaSchemaV18.AIInvocationLog
    typealias TempoRampPlan = GitaSchemaV18.TempoRampPlan

    static var models: [any PersistentModel.Type] {
        [
            TaskItem.self, PracticeSession.self, RecordingRef.self, LocalProfile.self,
            MemoryItem.self, PracticeItem.self, Project.self, AIInvocationLog.self,
            TempoRampPlan.self, MetronomeTrainingSession.self,
        ]
    }

    @Model
    final class MetronomeTrainingSession {
        @Attribute(.unique) var id: UUID
        var practiceItemId: UUID
        /// Legacy V18 sessions receive a generated compatibility value during
        /// lightweight migration; new V19 sessions always set the actual plan.
        var planId: UUID = UUID()
        var startedAt: Date
        var endedAt: Date?
        var stateRaw: String
        var completionReasonRaw: String?
        var startBPM: Int
        var targetBPM: Int
        var finalBPM: Int
        var stableMaxBPM: Int
        var completedBars: Int
        var completedStageCount: Int
        var pauseCount: Int
        var interruptionCount: Int
        var timeSignature: String
        var accentPatternRaw: String
        var subdivisionRaw: Int
        var createdAt: Date
        var updatedAt: Date

        init(
            id: UUID = UUID(), practiceItemId: UUID, planId: UUID, startedAt: Date = Date(),
            state: MetronomeTrainingState = .running,
            completionReason: MetronomeTrainingCompletionReason? = nil,
            settings: TempoRampSettings,
            finalBPM: Int? = nil, completedBars: Int = 0,
            timeSignature: String, accentPatternRaw: String, subdivisionRaw: Int,
            createdAt: Date = Date(), updatedAt: Date = Date()
        ) {
            self.id = id
            self.practiceItemId = practiceItemId
            self.planId = planId
            self.startedAt = startedAt
            self.stateRaw = state.rawValue
            self.completionReasonRaw = completionReason?.rawValue
            self.startBPM = settings.startBPM
            self.targetBPM = settings.targetBPM
            self.finalBPM = finalBPM ?? settings.startBPM
            self.stableMaxBPM = finalBPM ?? settings.startBPM
            self.completedBars = completedBars
            self.completedStageCount = 0
            self.pauseCount = 0
            self.interruptionCount = 0
            self.timeSignature = timeSignature
            self.accentPatternRaw = accentPatternRaw
            self.subdivisionRaw = subdivisionRaw
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }

        var state: MetronomeTrainingState {
            get { MetronomeTrainingState(rawValue: stateRaw) ?? .running }
            set { stateRaw = newValue.rawValue }
        }

        var completionReason: MetronomeTrainingCompletionReason? {
            get { completionReasonRaw.flatMap(MetronomeTrainingCompletionReason.init(rawValue:)) }
            set { completionReasonRaw = newValue?.rawValue }
        }
    }
}

typealias TempoRampPlan = GitaSchemaV19.TempoRampPlan
typealias MetronomeTrainingSession = GitaSchemaV19.MetronomeTrainingSession
