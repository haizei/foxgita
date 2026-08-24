//
//  MigrationTests.swift
//  foxgitaTests
//

import Foundation
import SwiftData
import Testing

@testable import foxgita

/// Boots a V2 store on disk, then reopens it under the V8 migration plan
/// (V2→V3→…→V8) and checks that user rows survive — the exact failure mode
/// of the old "delete everything on seed bump" path.
@MainActor
struct MigrationTests {
    @Test func v2StoreMigratesToV3WithoutLosingRows() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gita-migration-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        // --- Phase 1: write a V2 store ------------------------------------
        do {
            let v2Schema = Schema(versionedSchema: GitaSchemaV2.self)
            let config = ModelConfiguration(schema: v2Schema, url: url)
            let container = try ModelContainer(for: v2Schema, configurations: [config])
            let context = ModelContext(container)

            let task = GitaSchemaV2.TaskItem(
                id: "warm", title: "指尖热身", subtitle: "开放弦",
                categoryRaw: PracticeCategory.left.rawValue,
                targetMin: 5, defaultBpm: 80, timeSig: "4/4",
                stepsRaw: StepCoding.encode(["开放弦"]),
                statusRaw: TaskStatus.active.rawValue,
                startedOn: Date(), sortOrder: 0, isTemplate: false
            )
            context.insert(task)

            let ended = Date(timeIntervalSince1970: 1_700_000_000)
            let session = GitaSchemaV2.PracticeSession(
                id: "sess-1", taskId: "warm", taskTitle: "指尖热身",
                categoryRaw: PracticeCategory.left.rawValue,
                startedAt: ended.addingTimeInterval(-300), endedAt: ended,
                durationSec: 300, bpm: 80, timeSig: "4/4",
                stepsSnapshotRaw: StepCoding.encode(["开放弦"]),
                noteText: "迁移前写的笔记"
            )
            let recording = GitaSchemaV2.RecordingRef(
                id: "rec-1", fileName: "legacy.m4a", bytes: 2048,
                createdAt: ended, label: "片段"
            )
            session.recordings.append(recording)
            context.insert(session)
            try context.save()
        }

        // --- Phase 2: reopen under V8 + migration plan --------------------
        let v8Schema = Schema(versionedSchema: GitaSchemaV8.self)
        let config = ModelConfiguration(schema: v8Schema, url: url)
        let container = try ModelContainer(
            for: v8Schema, migrationPlan: GitaMigrationPlan.self, configurations: [config]
        )
        let context = ModelContext(container)

        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        let sessions = try context.fetch(FetchDescriptor<PracticeSession>())
        let recordings = try context.fetch(FetchDescriptor<RecordingRef>())

        #expect(tasks.count == 1)
        #expect(tasks[0].id == "warm")
        #expect(tasks[0].title == "指尖热身")
        // New V3 fields land with defaults rather than nil / crash.
        #expect(tasks[0].syncState == .local)
        #expect(tasks[0].deletedAt == nil)
        #expect(tasks[0].createdAt <= Date())

        #expect(sessions.count == 1)
        #expect(sessions[0].noteText == "迁移前写的笔记")
        #expect(sessions[0].durationSec == 300)
        #expect(sessions[0].syncState == .local)

        #expect(recordings.count == 1)
        #expect(recordings[0].fileName == "legacy.m4a")
        #expect(recordings[0].durationSec == 0) // new field, defaulted
        #expect(recordings[0].label == "片段")
        #expect(recordings[0].reviewStatus == .none)
        #expect(recordings[0].reviewHighlight.isEmpty)
        #expect(recordings[0].videoFindings.isEmpty)
    }

    @Test func v3StoreMigratesToV4WithEmptyReview() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gita-v3-v4-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let v3Schema = Schema(versionedSchema: GitaSchemaV3.self)
            let config = ModelConfiguration(schema: v3Schema, url: url)
            let container = try ModelContainer(for: v3Schema, configurations: [config])
            let context = ModelContext(container)
            let session = GitaSchemaV3.PracticeSession(
                id: "s1", taskId: "warm", taskTitle: "指尖热身",
                category: .left, startedAt: Date(), endedAt: Date(),
                durationSec: 60, bpm: 80, timeSig: "4/4",
                steps: ["开放弦"], noteText: ""
            )
            session.recordings.append(
                GitaSchemaV3.RecordingRef(
                    id: "r1", fileName: "clip.m4a", bytes: 100, durationSec: 12,
                    createdAt: Date(), label: "录音"
                )
            )
            context.insert(session)
            try context.save()
        }

        let v8Schema = Schema(versionedSchema: GitaSchemaV8.self)
        let config = ModelConfiguration(schema: v8Schema, url: url)
        let container = try ModelContainer(
            for: v8Schema, migrationPlan: GitaMigrationPlan.self, configurations: [config]
        )
        let recordings = try ModelContext(container).fetch(FetchDescriptor<RecordingRef>())
        #expect(recordings.count == 1)
        #expect(recordings[0].id == "r1")
        #expect(recordings[0].reviewStatus == .none)
        #expect(recordings[0].videoFindings.isEmpty)
    }

    @Test func v4StoreMigratesToV5WithEmptyFindings() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gita-v4-v5-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let v4Schema = Schema(versionedSchema: GitaSchemaV4.self)
            let config = ModelConfiguration(schema: v4Schema, url: url)
            let container = try ModelContainer(for: v4Schema, configurations: [config])
            let context = ModelContext(container)
            let session = GitaSchemaV4.PracticeSession(
                id: "s1", taskId: "warm", taskTitle: "指尖热身",
                category: .left, startedAt: Date(), endedAt: Date(),
                durationSec: 60, bpm: 80, timeSig: "4/4",
                steps: ["开放弦"], noteText: ""
            )
            let rec = GitaSchemaV4.RecordingRef(
                id: "r1", fileName: "clip.mov", bytes: 100, durationSec: 12,
                createdAt: Date(), label: "录像"
            )
            rec.reviewStatus = .ready
            rec.reviewHighlight = "稳"
            rec.reviewFocus = "F"
            rec.reviewNextAction = "慢练"
            session.recordings.append(rec)
            context.insert(session)
            try context.save()
        }

        let v8Schema = Schema(versionedSchema: GitaSchemaV8.self)
        let config = ModelConfiguration(schema: v8Schema, url: url)
        let container = try ModelContainer(
            for: v8Schema, migrationPlan: GitaMigrationPlan.self, configurations: [config]
        )
        let recordings = try ModelContext(container).fetch(FetchDescriptor<RecordingRef>())
        #expect(recordings.count == 1)
        #expect(recordings[0].reviewHighlight == "稳")
        #expect(recordings[0].reviewStatus == .ready)
        #expect(recordings[0].videoFindings.isEmpty)
    }

    @Test func v5StoreMigratesToV6WithoutLosingRows() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gita-v5-v6-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let v5Schema = Schema(versionedSchema: GitaSchemaV5.self)
            let config = ModelConfiguration(schema: v5Schema, url: url)
            let container = try ModelContainer(for: v5Schema, configurations: [config])
            let context = ModelContext(container)

            let task = GitaSchemaV5.TaskItem(
                id: "warm", title: "指尖热身", subtitle: "开放弦",
                category: .left, targetMin: 5, steps: ["开放弦"]
            )
            context.insert(task)

            let session = GitaSchemaV5.PracticeSession(
                id: "sess-1", taskId: "warm", taskTitle: "指尖热身",
                category: .left, startedAt: Date(), endedAt: Date(),
                durationSec: 300, bpm: 80, timeSig: "4/4",
                steps: ["开放弦"], noteText: "V5 笔记"
            )
            let rec = GitaSchemaV5.RecordingRef(
                id: "rec-1", fileName: "clip.m4a", bytes: 2048,
                durationSec: 12, createdAt: Date(), label: "片段"
            )
            rec.reviewHighlight = "稳"
            rec.reviewStatus = .ready
            session.recordings.append(rec)
            context.insert(session)
            try context.save()
        }

        let v8Schema = Schema(versionedSchema: GitaSchemaV8.self)
        let config = ModelConfiguration(schema: v8Schema, url: url)
        let container = try ModelContainer(
            for: v8Schema, migrationPlan: GitaMigrationPlan.self, configurations: [config]
        )
        let context = ModelContext(container)
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        let sessions = try context.fetch(FetchDescriptor<PracticeSession>())
        let recordings = try context.fetch(FetchDescriptor<RecordingRef>())

        #expect(tasks.count == 1)
        #expect(tasks[0].id == "warm")
        #expect(tasks[0].title == "指尖热身")
        #expect(tasks[0].profileId == "")
        #expect(sessions.count == 1)
        #expect(sessions[0].noteText == "V5 笔记")
        #expect(sessions[0].profileId == "")
        #expect(recordings.count == 1)
        #expect(recordings[0].fileName == "clip.m4a")
        #expect(recordings[0].reviewHighlight == "稳")
        #expect(recordings[0].reviewStatus == .ready)
    }

    @Test func v6StoreMigratesToV7WithoutLosingRowsAndLeavesConsentUndecided() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gita-v6-v7-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let v6Schema = Schema(versionedSchema: GitaSchemaV6.self)
            let config = ModelConfiguration(schema: v6Schema, url: url)
            let container = try ModelContainer(for: v6Schema, configurations: [config])
            let context = ModelContext(container)
            let task = GitaSchemaV6.TaskItem(
                id: "warm", title: "指尖热身", subtitle: "开放弦",
                category: .left, targetMin: 5, steps: ["开放弦"], profileId: "p1"
            )
            context.insert(task)
            let profile = GitaSchemaV6.LocalProfile(id: "p1", memoryConsent: false)
            context.insert(profile)
            let memory = GitaSchemaV6.MemoryItem(
                profileId: "p1", kind: .goal, key: "goal.current_song",
                summaryText: "当前目标：《晴天》前奏",
                sourceType: "debug_seed", sourceId: "goal.current_song",
                confidence: 1, importance: 1
            )
            context.insert(memory)
            try context.save()
        }

        let v8Schema = Schema(versionedSchema: GitaSchemaV8.self)
        let config = ModelConfiguration(schema: v8Schema, url: url)
        let container = try ModelContainer(
            for: v8Schema, migrationPlan: GitaMigrationPlan.self, configurations: [config]
        )
        let context = ModelContext(container)
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        let profiles = try context.fetch(FetchDescriptor<LocalProfile>())
        let memories = try context.fetch(FetchDescriptor<MemoryItem>())
        #expect(tasks.count == 1)
        #expect(tasks[0].profileId == "p1")
        #expect(memories.count == 1)
        #expect(memories[0].summaryText == "当前目标：《晴天》前奏")
        #expect(profiles.count == 1)
        #expect(profiles[0].memoryConsent == false)
        #expect(profiles[0].memoryConsentState == "")
    }

    @Test func v7StoreMigratesToV8WithoutLosingRowsAndDefaultsOriginKey() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gita-v7-v8-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let v7Schema = Schema(versionedSchema: GitaSchemaV7.self)
            let config = ModelConfiguration(schema: v7Schema, url: url)
            let container = try ModelContainer(for: v7Schema, configurations: [config])
            let context = ModelContext(container)
            let task = GitaSchemaV7.TaskItem(
                id: "warm", title: "指尖热身", subtitle: "开放弦",
                category: .left, targetMin: 5, steps: ["开放弦"], profileId: "p1"
            )
            context.insert(task)
            try context.save()
        }

        let v8Schema = Schema(versionedSchema: GitaSchemaV8.self)
        let config = ModelConfiguration(schema: v8Schema, url: url)
        let container = try ModelContainer(
            for: v8Schema, migrationPlan: GitaMigrationPlan.self, configurations: [config]
        )
        let context = ModelContext(container)
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        #expect(tasks.count == 1)
        #expect(tasks[0].id == "warm")
        #expect(tasks[0].title == "指尖热身")
        #expect(tasks[0].profileId == "p1")
        #expect(tasks[0].originKey == "")
    }
}
