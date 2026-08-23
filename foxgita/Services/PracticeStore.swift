//
//  PracticeStore.swift
//  foxgita
//

import Foundation

struct MediaReviewContext: Equatable, Sendable {
    var recordingId: String
    var fileName: String
    var durationSec: Int
    var taskTitle: String
    var steps: [String]
    var bpm: Int
    var timeSig: String
    var note: String
}

/// Command layer. Views read through `@Query` for free reactivity and write
/// only through here, so every invariant and every error path lives in one
/// place. Failures surface as `lastError` for the toast to pick up.
@Observable
@MainActor
final class PracticeStore {
    private(set) var lastError: StoreError?

    @ObservationIgnored private let repository: PracticeRepository
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let taskMemorySync: TaskMemorySync?
    @ObservationIgnored private let aiCandidateSync: AICandidateSync?

    init(
        repository: PracticeRepository,
        defaults: UserDefaults = .standard,
        taskMemorySync: TaskMemorySync? = nil,
        aiCandidateSync: AICandidateSync? = nil
    ) {
        self.repository = repository
        self.defaults = defaults
        self.taskMemorySync = taskMemorySync
        self.aiCandidateSync = aiCandidateSync
    }

    func clearError() { lastError = nil }

    // MARK: - Launch

    func prepare() {
        RecordingStore.migrateLegacyFiles()
        seedIfNeeded()
        ensureProfile()
        gcOrphanRecordings()
    }

    func activeProfileForDebug() throws -> LocalProfile? {
        try repository.activeProfile()
    }

    func seedIfNeeded() {
        guard !defaults.bool(forKey: SeedData.seededKey) else { return }
        perform {
            for template in SeedData.templates() { try repository.add(template) }
            try repository.save()
            defaults.set(true, forKey: SeedData.seededKey)
        }
    }

    /// Removes clips no longer referenced by any recording row — e.g. a take
    /// recorded and then abandoned by leaving the practice screen.
    @discardableResult
    func gcOrphanRecordings() -> Int {
        guard let sessions = try? repository.sessions() else { return 0 }
        let referenced = Set(sessions.flatMap { $0.recordings.map(\.fileName) })
        return RecordingStore.removeOrphans(referenced: referenced)
    }

    // MARK: - Tasks

    @discardableResult
    func activateTemplate(
        _ templateId: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String? {
        guard let template = try? repository.task(id: templateId) else {
            lastError = .notFound
            return nil
        }
        guard template.isTemplate else { return template.id }

        let dayKey = PracticeTaskRules.localDayKey(for: now, calendar: calendar)
        let dailyId = "active-\(template.id)-\(dayKey)"
        let legacyId = "active-\(template.id)"

        if let existing = try? repository.task(id: dailyId) {
            return ensureActive(existing)
        }
        if let tombstone = try? repository.taskIncludingDeleted(id: dailyId),
           tombstone.deletedAt != nil {
            return ensureActive(tombstone)
        }
        if let legacy = try? repository.task(id: legacyId),
           let started = legacy.startedOn,
           calendar.isDate(started, inSameDayAs: now) {
            return ensureActive(legacy)
        }

        guard let profileId = requireProfileId() else { return nil }
        let copy = TaskItem(
            id: dailyId, title: template.title, subtitle: template.subtitle,
            category: template.category, targetMin: template.targetMin,
            defaultBpm: template.defaultBpm, timeSig: template.timeSig,
            steps: template.steps, status: .active, startedOn: now,
            sortOrder: template.sortOrder, isTemplate: false,
            profileId: profileId
        )
        return produce {
            try repository.add(copy)
            try repository.save()
            return copy.id
        }
    }

    @discardableResult
    func createCustomTask(name: String, minutes: Int, category: PracticeCategory) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let clampedMinutes = min(60, max(1, minutes))
        guard let profileId = requireProfileId() else { return nil }
        let task = TaskItem(
            id: "custom-\(UUID().uuidString)",
            title: trimmed.isEmpty ? String(localized: "未命名练习") : trimmed,
            subtitle: String(localized: "自定义 · \(clampedMinutes) 分钟"),
            category: category,
            targetMin: clampedMinutes,
            steps: [String(localized: "新步骤")],
            startedOn: Date(),
            sortOrder: 50,
            profileId: profileId
        )
        let saved = produce {
            try repository.add(task)
            try repository.save()
            return task.id
        }
        if saved != nil { applySyncUpsert(task) }
        return saved
    }

    @discardableResult
    func createFromAIDraft(_ draft: AIPracticeDraft) -> String? {
        guard let profileId = requireProfileId() else { return nil }
        let task = TaskItem(
            id: "custom-\(UUID().uuidString)",
            title: draft.title,
            subtitle: draft.subtitleLine,
            category: draft.category,
            targetMin: draft.targetMin,
            steps: draft.steps,
            startedOn: Date(),
            sortOrder: 50,
            profileId: profileId
        )
        let saved = produce {
            try repository.add(task)
            try repository.save()
            return task.id
        }
        if saved != nil { applySyncUpsert(task) }
        return saved
    }

    func setTaskStatus(_ taskId: String, to status: TaskStatus) {
        guard let task = try? repository.task(id: taskId) else {
            lastError = .notFound
            return
        }
        perform {
            task.status = status
            task.touch()
            try repository.save()
        }
    }

    func updateTaskPracticeState(_ taskId: String, steps: [String], bpm: Int) {
        guard let task = try? repository.task(id: taskId) else {
            lastError = .notFound
            return
        }
        perform {
            task.steps = steps
            task.defaultBpm = min(200, max(40, bpm))
            task.touch()
            try repository.save()
        }
        if lastError == nil { applySyncUpsert(task) }
    }

    func updateTask(_ taskId: String, title: String, subtitle: String, minutes: Int) {
        guard let task = try? repository.task(id: taskId) else {
            lastError = .notFound
            return
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        perform {
            task.title = trimmed.isEmpty ? task.title : trimmed
            task.subtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
            task.targetMin = min(60, max(1, minutes))
            task.touch()
            try repository.save()
        }
        if lastError == nil { applySyncUpsert(task) }
    }

    /// Soft-delete so sync can still see the tombstone later.
    func softDeleteTask(_ taskId: String) {
        guard let task = try? repository.task(id: taskId) else {
            lastError = .notFound
            return
        }
        let profileId = task.profileId
        perform {
            task.deletedAt = Date()
            task.touch()
            try repository.save()
        }
        if lastError == nil { applySyncDelete(taskId: taskId, profileId: profileId) }
    }

    func updateSession(_ sessionId: String, title: String, note: String, minutes: Int) {
        guard let session = try? repository.session(id: sessionId) else {
            lastError = .notFound
            return
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let clampedMinutes = min(180, max(1, minutes))
        perform {
            session.taskTitle = trimmed.isEmpty ? session.taskTitle : trimmed
            session.noteText = note.trimmingCharacters(in: .whitespacesAndNewlines)
            session.durationSec = clampedMinutes * 60
            session.updatedAt = Date()
            try repository.save()
        }
    }

    func softDeleteSession(_ sessionId: String) {
        guard let session = try? repository.session(id: sessionId) else {
            lastError = .notFound
            return
        }
        perform {
            session.deletedAt = Date()
            session.updatedAt = Date()
            try repository.save()
        }
    }

    // MARK: - Sessions

    /// Invariants: the window must be ordered, the duration non-negative, and a
    /// recording row is only created for a clip that is actually on disk. The
    /// session and its recordings commit together or not at all.
    @discardableResult
    func finishSession(
        taskId: String,
        steps: [String],
        note: String,
        startedAt: Date,
        endedAt: Date,
        durationSec: Int,
        bpm: Int,
        recordings: [AudioRecorderService.Clip]
    ) -> String? {
        guard let task = try? repository.task(id: taskId) else {
            lastError = .notFound
            return nil
        }
        guard endedAt >= startedAt, durationSec >= 0 else {
            lastError = .invalidInput
            return nil
        }

        let existingClipCount = recordings.filter {
            FileManager.default.fileExists(atPath: $0.url.path)
        }.count
        guard PracticeRecordRules.isEffective(
            durationSec: durationSec,
            noteText: note,
            recordingCount: existingClipCount
        ) else {
            lastError = .invalidInput
            return nil
        }

        guard let profileId = requireProfileId() else { return nil }
        let session = PracticeSession(
            taskId: task.id,
            taskTitle: task.title,
            category: task.category,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSec: durationSec,
            bpm: bpm,
            timeSig: task.timeSig,
            steps: steps,
            noteText: note,
            profileId: profileId
        )
        for clip in recordings where FileManager.default.fileExists(atPath: clip.url.path) {
            session.recordings.append(
                RecordingRef(
                    id: clip.id, fileName: clip.fileName, bytes: clip.bytes,
                    durationSec: clip.durationSec, createdAt: clip.createdAt, label: clip.label
                )
            )
        }

        return produce {
            task.steps = steps
            task.defaultBpm = min(200, max(40, bpm))
            task.touch()
            try repository.add(session)
            try repository.save()
            return session.id
        }
    }

    func beginOpenSession(
        taskId: String,
        steps: [String],
        note: String,
        startedAt: Date,
        endedAt: Date,
        durationSec: Int,
        bpm: Int,
        clip: AudioRecorderService.Clip
    ) -> String? {
        guard let task = try? repository.task(id: taskId) else {
            lastError = .notFound
            return nil
        }
        guard endedAt >= startedAt, durationSec >= 0 else {
            lastError = .invalidInput
            return nil
        }
        guard FileManager.default.fileExists(atPath: clip.url.path) else {
            lastError = .fileMissing
            return nil
        }
        guard let profileId = requireProfileId() else { return nil }
        let session = PracticeSession(
            taskId: task.id,
            taskTitle: task.title,
            category: task.category,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSec: durationSec,
            bpm: bpm,
            timeSig: task.timeSig,
            steps: steps,
            noteText: note,
            profileId: profileId
        )
        session.recordings.append(Self.ref(from: clip))
        return produce {
            task.steps = steps
            task.touch()
            try repository.add(session)
            try repository.save()
            return session.id
        }
    }

    func appendRecording(sessionId: String, clip: AudioRecorderService.Clip) -> Bool {
        guard let session = try? repository.session(id: sessionId) else {
            lastError = .notFound
            return false
        }
        guard FileManager.default.fileExists(atPath: clip.url.path) else {
            lastError = .fileMissing
            return false
        }
        return produce {
            session.recordings.append(Self.ref(from: clip))
            session.updatedAt = Date()
            try repository.save()
            return true
        } ?? false
    }

    func updateOpenSession(
        sessionId: String,
        steps: [String],
        note: String,
        endedAt: Date,
        durationSec: Int,
        bpm: Int
    ) -> Bool {
        guard let session = try? repository.session(id: sessionId) else {
            lastError = .notFound
            return false
        }
        guard let task = try? repository.task(id: session.taskId) else {
            lastError = .notFound
            return false
        }
        guard endedAt >= session.startedAt, durationSec >= 0 else {
            lastError = .invalidInput
            return false
        }
        return produce {
            session.stepsSnapshotRaw = StepCoding.encode(steps)
            session.noteText = note
            session.endedAt = endedAt
            session.durationSec = durationSec
            session.bpm = bpm
            session.updatedAt = Date()
            task.steps = steps
            task.defaultBpm = min(200, max(40, bpm))
            task.touch()
            try repository.save()
            return true
        } ?? false
    }

    private static func ref(from clip: AudioRecorderService.Clip) -> RecordingRef {
        RecordingRef(
            id: clip.id, fileName: clip.fileName, bytes: clip.bytes,
            durationSec: clip.durationSec, createdAt: clip.createdAt, label: clip.label
        )
    }

    // MARK: - Reviews

    func markReviewsPending(recordingIds: [String]) {
        perform {
            for id in recordingIds {
                guard let rec = try repository.recording(id: id) else { continue }
                rec.reviewStatus = .pending
                rec.reviewHighlight = ""
                rec.reviewFocus = ""
                rec.reviewNextAction = ""
                rec.videoFindings = []
                rec.updatedAt = Date()
                rec.syncState = .local
            }
            try repository.save()
        }
    }

    func applyReview(recordingId: String, draft: MediaReviewDraft) {
        var pending: (profileId: String, recordingId: String, focus: String)?
        perform {
            if let rec = try repository.recording(id: recordingId) {
                rec.reviewStatus = .ready
                rec.reviewHighlight = draft.highlight
                rec.reviewFocus = draft.focus
                rec.reviewNextAction = draft.nextAction
                rec.videoFindings = []
                rec.updatedAt = Date()
                rec.syncState = .local
                if let profileId = rec.session?.profileId, !profileId.isEmpty {
                    pending = (profileId, recordingId, draft.focus)
                }
            }
            try repository.save()
        }
        if lastError == nil, let pending {
            applyCandidateFocus(
                profileId: pending.profileId,
                focus: pending.focus,
                recordingId: pending.recordingId,
                skill: .reviewMedia
            )
        }
    }

    func applyVideoDiagnosis(recordingId: String, draft: VideoDiagnosisDraft) {
        var pending: (profileId: String, recordingId: String, focus: String)?
        perform {
            if let rec = try repository.recording(id: recordingId) {
                rec.reviewStatus = .ready
                rec.reviewHighlight = draft.highlight
                rec.reviewFocus = draft.focus
                rec.reviewNextAction = draft.nextAction
                rec.videoFindings = draft.findings
                rec.updatedAt = Date()
                rec.syncState = .local
                if let profileId = rec.session?.profileId, !profileId.isEmpty {
                    pending = (profileId, recordingId, draft.focus)
                }
            }
            try repository.save()
        }
        if lastError == nil, let pending {
            applyCandidateFocus(
                profileId: pending.profileId,
                focus: pending.focus,
                recordingId: pending.recordingId,
                skill: .diagnoseVideo
            )
        }
    }

    func markReviewsFailed(recordingIds: [String]) {
        perform {
            for id in recordingIds {
                guard let rec = try repository.recording(id: id) else { continue }
                rec.reviewStatus = .failed
                rec.reviewHighlight = ""
                rec.reviewFocus = ""
                rec.reviewNextAction = ""
                rec.videoFindings = []
                rec.updatedAt = Date()
                rec.syncState = .local
            }
            try repository.save()
        }
    }

    func reviewContext(recordingId: String) -> MediaReviewContext? {
        guard let recording = try? repository.recording(id: recordingId) else { return nil }
        let session = recording.session ?? (try? repository.sessions().first { session in
            session.recordings.contains { $0.id == recordingId && $0.deletedAt == nil }
        })
        guard let session else { return nil }
        return MediaReviewContext(
            recordingId: recording.id,
            fileName: recording.fileName,
            durationSec: recording.durationSec,
            taskTitle: session.taskTitle,
            steps: session.steps,
            bpm: session.bpm,
            timeSig: session.timeSig,
            note: session.noteText
        )
    }

    // MARK: - Data

    func resetAll() {
        perform {
            try repository.removeAll()
            for template in SeedData.templates() { try repository.add(template) }
            try repository.save()
            defaults.set(true, forKey: SeedData.seededKey)
            RecordingStore.removeAll()
        }
        ensureProfile()
    }

    // MARK: - Error plumbing

    private func ensureProfile() {
        perform {
            let profile = try repository.ensureDefaultProfile()
            if profile.memoryConsentState.isEmpty {
                profile.consent = profile.memoryConsent ? .enabled : .undecided
            }
            try repository.backfillEmptyProfileIds(profile.id)
            try repository.save()
        }
    }

    private func requireProfileId() -> String? {
        guard let id = try? repository.ensureDefaultProfile().id else {
            lastError = .saveFailed
            return nil
        }
        return id
    }

    private func ensureActive(_ task: TaskItem) -> String? {
        if task.status == .active && task.deletedAt == nil { return task.id }
        return produce {
            task.deletedAt = nil
            task.status = .active
            task.touch()
            try repository.save()
            return task.id
        }
    }

    private func applyCandidateFocus(
        profileId: String,
        focus: String,
        recordingId: String,
        skill: SkillDefinition
    ) {
        guard let sync = aiCandidateSync else { return }
        sync.syncFocus(
            profileId: profileId,
            focus: focus,
            recordingId: recordingId,
            skill: skill
        )
        if let error = sync.lastError { lastError = error }
    }

    private func applySyncUpsert(_ task: TaskItem) {
        guard let sync = taskMemorySync else { return }
        sync.syncUpsert(task: task)
        if let error = sync.lastError { lastError = error }
    }

    private func applySyncDelete(taskId: String, profileId: String) {
        guard let sync = taskMemorySync else { return }
        sync.syncDelete(taskId: taskId, profileId: profileId)
        if let error = sync.lastError { lastError = error }
    }

    private func perform(_ work: () throws -> Void) {
        _ = produce(work)
    }

    private func produce<T>(_ work: () throws -> T) -> T? {
        do {
            let value = try work()
            lastError = nil
            return value
        } catch {
            repository.rollback()
            lastError = StoreError.from(error)
            return nil
        }
    }
}
