//
//  MigrationTests.swift
//  foxgitaTests
//

import Foundation
import SwiftData
import Testing

@testable import foxgita

/// Boots a V2 store on disk, then reopens it under the V3 migration plan and
/// checks that user rows survive — the exact failure mode of the old
/// "delete everything on seed bump" path.
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

        // --- Phase 2: reopen under V3 + migration plan --------------------
        let v3Schema = Schema(versionedSchema: GitaSchemaV3.self)
        let config = ModelConfiguration(schema: v3Schema, url: url)
        let container = try ModelContainer(
            for: v3Schema, migrationPlan: GitaMigrationPlan.self, configurations: [config]
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
    }
}
