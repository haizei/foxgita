import Foundation
import SwiftData

enum MetronomeTrainingState: String, Codable, Sendable {
    case running, completed
}

enum MetronomeTrainingCompletionReason: String, Codable, Sendable {
    case targetCompleted = "target_completed"
    case userStopped = "user_stopped"
    case practiceFinished = "practice_finished"
    case interrupted
}

/// Adds reusable tempo-ramp plans and append-only training history without
/// changing the shipped V17 entities.
enum GitaSchemaV18: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(18, 0, 0) }

    typealias TaskItem = GitaSchemaV17.TaskItem
    typealias PracticeSession = GitaSchemaV17.PracticeSession
    typealias RecordingRef = GitaSchemaV17.RecordingRef
    typealias LocalProfile = GitaSchemaV17.LocalProfile
    typealias MemoryItem = GitaSchemaV17.MemoryItem
    typealias PracticeItem = GitaSchemaV17.PracticeItem
    typealias Project = GitaSchemaV17.Project
    typealias AIInvocationLog = GitaSchemaV17.AIInvocationLog

    static var models: [any PersistentModel.Type] {
        [
            TaskItem.self, PracticeSession.self, RecordingRef.self, LocalProfile.self,
            MemoryItem.self, PracticeItem.self, Project.self, AIInvocationLog.self,
            TempoRampPlan.self, MetronomeTrainingSession.self,
        ]
    }

    @Model
    final class TempoRampPlan {
        @Attribute(.unique) var id: UUID
        var practiceItemId: UUID
        var startBPM: Int
        var targetBPM: Int
        var barsPerStage: Int
        var stepBPM: Int
        var countInBars: Int
        var meterRaw: String
        var subdivisionRaw: Int
        var accentPatternRaw: String
        var createdAt: Date
        var updatedAt: Date

        init(
            id: UUID = UUID(), practiceItemId: UUID, settings: TempoRampSettings,
            meterRaw: String, subdivisionRaw: Int, accentPatternRaw: String,
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.practiceItemId = practiceItemId
            self.startBPM = settings.startBPM
            self.targetBPM = settings.targetBPM
            self.barsPerStage = settings.barsPerStage
            self.stepBPM = settings.stepBPM
            self.countInBars = settings.countInBars
            self.meterRaw = meterRaw
            self.subdivisionRaw = subdivisionRaw
            self.accentPatternRaw = accentPatternRaw
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }

        var settings: TempoRampSettings {
            TempoRampSettings(
                startBPM: startBPM, targetBPM: targetBPM,
                barsPerStage: barsPerStage, stepBPM: stepBPM, countInBars: countInBars
            )
        }
    }

    @Model
    final class MetronomeTrainingSession {
        @Attribute(.unique) var id: UUID
        var practiceItemId: UUID
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
            id: UUID = UUID(), practiceItemId: UUID, startedAt: Date = Date(),
            state: MetronomeTrainingState = .running,
            completionReason: MetronomeTrainingCompletionReason? = nil,
            settings: TempoRampSettings,
            finalBPM: Int? = nil, completedBars: Int = 0,
            timeSignature: String, accentPatternRaw: String, subdivisionRaw: Int,
            createdAt: Date = Date(), updatedAt: Date = Date()
        ) {
            self.id = id
            self.practiceItemId = practiceItemId
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

typealias TempoRampPlan = GitaSchemaV18.TempoRampPlan
typealias MetronomeTrainingSession = GitaSchemaV18.MetronomeTrainingSession

@MainActor
enum MetronomeTrainingPersistence {
    static func settleOrphanedRuns(in context: ModelContext, now: Date = Date()) throws {
        let descriptor = FetchDescriptor<MetronomeTrainingSession>(
            predicate: #Predicate { $0.stateRaw == "running" && $0.endedAt == nil }
        )
        for session in try context.fetch(descriptor) {
            session.state = .completed
            session.completionReason = .interrupted
            session.endedAt = now
            session.updatedAt = now
        }
        if context.hasChanges { try context.save() }
    }
}
