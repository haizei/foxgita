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

enum PracticeReviewContext: Equatable, Sendable {
    case practiceItem(UUID)
    case legacySession(UUID)
}

enum PracticeItemSource: String {
    case custom
    case recommend
    case photo
    case next
    case project
}

struct PracticeItemInput {
    let title: String
    let category: PracticeCategory
    let source: PracticeItemSource
    let originId: String?
    let bpm: Int?
    let timeSignature: String?
    var steps: [String] = []
    var subtitle: String = ""
    var targetMin: Int = 0
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
    @ObservationIgnored private let invocationStore: AIInvocationStore?

    init(
        repository: PracticeRepository,
        defaults: UserDefaults = .standard,
        taskMemorySync: TaskMemorySync? = nil,
        aiCandidateSync: AICandidateSync? = nil,
        invocationStore: AIInvocationStore? = nil
    ) {
        self.repository = repository
        self.defaults = defaults
        self.taskMemorySync = taskMemorySync
        self.aiCandidateSync = aiCandidateSync
        self.invocationStore = invocationStore
    }

    func clearError() { lastError = nil }

    static func snapshot(from item: PracticeItem) -> PracticeItemSnapshot {
        PracticeItemSnapshot(
            id: item.id,
            practiceDayKey: item.practiceDayKey,
            createdAt: item.createdAt,
            title: item.title,
            durationSeconds: item.durationSeconds,
            isDeleted: item.deletedAt != nil,
            projectId: item.projectId,
            note: item.note,
            recordingCount: item.recordings.filter { $0.deletedAt == nil }.count,
            categoryRaw: item.categoryRaw,
            subtitle: item.subtitle,
            targetMin: item.targetMin
        )
    }

    static func snapshot(from project: Project) -> ProjectSnapshot {
        ProjectRules.snapshot(from: project)
    }

    func practiceItemSnapshots(profileId: UUID) throws -> [PracticeItemSnapshot] {
        try repository.practiceItems(profileId: profileId).map(Self.snapshot(from:))
    }

    // MARK: - Projects

    func createProject(name: String, goal: String, now: Date) throws -> Project {
        let prepared: ProjectSetupFields
        switch ProjectSetupRules.prepare(name: name, goal: goal) {
        case .success(let fields):
            prepared = fields
        case .failure:
            lastError = .invalidInput
            throw StoreError.invalidInput
        }
        let profileId = try requireProfileUUID()
        let project = Project(
            profileId: profileId,
            name: prepared.name,
            goal: prepared.goal,
            kindRaw: "",
            stageRaw: "",
            currentFocus: "",
            statusRaw: ProjectStatus.active.rawValue,
            createdAt: now,
            updatedAt: now
        )
        do {
            try repository.insertProject(project)
            try persistPracticeItemChanges()
            return project
        } catch {
            repository.rollback()
            lastError = StoreError.from(error)
            throw lastError ?? .saveFailed
        }
    }

    func updateProject(
        id: UUID,
        name: String,
        goal: String,
        kindRaw: String,
        stageRaw: String,
        currentFocus: String,
        now: Date
    ) throws {
        let prepared: ProjectSetupFields
        switch ProjectSetupRules.prepare(name: name, goal: goal) {
        case .success(let fields):
            prepared = fields
        case .failure:
            lastError = .invalidInput
            throw StoreError.invalidInput
        }
        let project = try requireLiveProject(id: id)
        project.name = prepared.name
        project.goal = prepared.goal
        project.kindRaw = kindRaw
        project.stageRaw = stageRaw
        project.currentFocus = ProjectSetupRules.trimmed(currentFocus)
        project.updatedAt = now
        try persistPracticeItemChanges()
    }

    func updateProjectBasics(id: UUID, name: String, goal: String, now: Date) throws {
        let prepared: ProjectSetupFields
        switch ProjectSetupRules.prepare(name: name, goal: goal) {
        case .success(let fields):
            prepared = fields
        case .failure:
            lastError = .invalidInput
            throw StoreError.invalidInput
        }
        let project = try requireLiveProject(id: id)
        project.name = prepared.name
        project.goal = prepared.goal
        project.updatedAt = now
        try persistPracticeItemChanges()
    }

    func updateProjectGoal(id: UUID, goal: String, now: Date) throws {
        let trimmed = ProjectSetupRules.trimmed(goal)
        if trimmed.count > ProjectSetupRules.goalMax {
            lastError = .invalidInput
            throw StoreError.invalidInput
        }
        let project = try requireLiveProject(id: id)
        project.goal = trimmed
        project.updatedAt = now
        try persistPracticeItemChanges()
    }

    func updateProjectStage(id: UUID, stageRaw: String, now: Date) throws {
        let project = try requireLiveProject(id: id)
        project.stageRaw = ProjectSetupRules.trimmed(stageRaw)
        project.updatedAt = now
        try persistPracticeItemChanges()
    }

    func setProjectStatus(id: UUID, status: ProjectStatus, now: Date) throws {
        let project = try requireLiveProject(id: id)
        project.status = status
        project.updatedAt = now
        if status != .active,
           let profile = try repository.activeProfile(),
           profile.pinnedProjectId == id {
            profile.pinnedProjectId = nil
        }
        try persistPracticeItemChanges()
    }

    func deleteProject(id: UUID, now: Date) throws {
        let project = try requireLiveProject(id: id)
        let profileId = project.profileId
        project.deletedAt = now
        project.updatedAt = now
        let items = try repository.practiceItems(profileId: profileId)
        for item in items where item.projectId == id {
            item.projectId = nil
            item.updatedAt = now
        }
        if let profile = try repository.activeProfile(), profile.pinnedProjectId == id {
            profile.pinnedProjectId = nil
        }
        try persistPracticeItemChanges()
    }

    func setPinnedProjectId(_ id: UUID?) throws {
        guard let profile = try repository.activeProfile() else {
            lastError = .notFound
            throw StoreError.notFound
        }
        if let id {
            let profileId = try requireProfileUUID()
            guard let project = try repository.project(id: id, profileId: profileId),
                  project.status == .active else {
                lastError = .notFound
                throw StoreError.notFound
            }
        }
        profile.pinnedProjectId = id
        try persistPracticeItemChanges()
    }

    func setPracticeItemProject(id: UUID, projectId: UUID?, now: Date) throws {
        let item = try requireLivePracticeItem(id: id)
        let previous = item.projectId
        if let projectId {
            if (try repository.project(id: projectId, profileId: item.profileId)) == nil {
                item.projectId = nil
            } else {
                item.projectId = projectId
            }
        } else {
            item.projectId = nil
        }
        if previous != item.projectId {
            try clearVersionRefs(pointingTo: id, now: now)
        }
        item.updatedAt = now
        try persistPracticeItemChanges()
    }

    func setProjectStageVersion(projectId: UUID, itemId: UUID?, now: Date) throws {
        try setProjectVersion(projectId: projectId, itemId: itemId, now: now) { project, value in
            project.stageVersionItemId = value
        }
    }

    func setProjectFinalVersion(projectId: UUID, itemId: UUID?, now: Date) throws {
        try setProjectVersion(projectId: projectId, itemId: itemId, now: now) { project, value in
            project.finalVersionItemId = value
        }
    }

    func createTodayPracticeItem(
        projectId: UUID,
        now: Date,
        calendar: Calendar
    ) throws -> PracticeItem {
        let profileId = try requireProfileUUID()
        guard let project = try repository.project(id: projectId, profileId: profileId),
              project.status == .active else {
            lastError = .notFound
            throw StoreError.notFound
        }
        let title = ProjectRules.titleForNewPracticeItem(Self.snapshot(from: project))
        let item = PracticeItem(
            id: UUID(),
            profileId: profileId,
            practiceDayKey: PracticeDayKey.make(from: now, calendar: calendar),
            title: title,
            categoryRaw: PracticeCategory.song.rawValue,
            durationSeconds: 0,
            bpm: nil,
            timeSignature: nil,
            note: "",
            sourceRaw: PracticeItemSource.project.rawValue,
            originId: nil,
            projectId: projectId,
            steps: PracticeDetailState.initialSteps([]),
            subtitle: "",
            targetMin: PracticeHomeState.initialTargetMin(0),
            createdAt: now,
            updatedAt: now
        )
        do {
            try repository.insertPracticeItem(item)
            try persistPracticeItemChanges()
            return item
        } catch {
            repository.rollback()
            lastError = StoreError.from(error)
            throw lastError ?? .saveFailed
        }
    }

    func createPracticeItem(input: PracticeItemInput, now: Date, calendar: Calendar) throws -> PracticeItem {
        let profileId = try requireProfileUUID()
        let lineage = try repository.practiceItems(profileId: profileId)
            .map(PracticeItemResumeQuery.lineageItem(from:))
        let seededBpm = PracticeItemResumeQuery.seedBpm(
            originId: input.originId,
            title: input.title,
            sourceRaw: input.source.rawValue,
            items: lineage,
            fallback: input.bpm
        )
        let item = PracticeItem(
            id: UUID(),
            profileId: profileId,
            practiceDayKey: PracticeDayKey.make(from: now, calendar: calendar),
            title: input.title,
            categoryRaw: input.category.rawValue,
            durationSeconds: 0,
            bpm: seededBpm,
            timeSignature: input.timeSignature,
            note: "",
            sourceRaw: input.source.rawValue,
            originId: input.originId,
            steps: PracticeDetailState.initialSteps(input.steps),
            subtitle: input.subtitle,
            targetMin: PracticeHomeState.initialTargetMin(input.targetMin),
            createdAt: now,
            updatedAt: now
        )
        do {
            try repository.insertPracticeItem(item)
            try persistPracticeItemChanges()
            return item
        } catch {
            repository.rollback()
            lastError = StoreError.from(error)
            throw lastError ?? .saveFailed
        }
    }

    func savePracticeItem(
        id: UUID,
        durationSeconds: Int,
        note: String,
        now: Date,
        steps: [String]? = nil,
        bpm: Int? = nil
    ) throws {
        let item = try requireLivePracticeItem(id: id)
        item.durationSeconds = max(0, durationSeconds)
        item.note = note
        if let steps {
            item.steps = PracticeDetailState.initialSteps(steps)
        }
        if let bpm {
            item.bpm = min(200, max(40, bpm))
        }
        item.updatedAt = now
        if let projectId = item.projectId,
           (try repository.project(id: projectId, profileId: item.profileId)) == nil {
            item.projectId = nil
        }
        try persistPracticeItemChanges()
        markInvocationIfEffective(item, now: now)
    }

    func updatePracticeItem(
        id: UUID,
        title: String,
        subtitle: String,
        minutes: Int,
        now: Date
    ) throws {
        let item = try requireLivePracticeItem(id: id)
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        item.title = trimmed.isEmpty ? item.title : trimmed
        item.subtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        item.targetMin = PracticeHomeState.initialTargetMin(minutes)
        item.updatedAt = now
        try persistPracticeItemChanges()
    }

    func softDeletePracticeItem(id: UUID, now: Date) throws {
        let item = try requireLivePracticeItem(id: id)
        item.deletedAt = now
        item.updatedAt = now
        try clearVersionRefs(pointingTo: id, now: now)
        try persistPracticeItemChanges()
    }

    func attachRecording(_ recording: RecordingRef, toPracticeItemId itemId: UUID, now: Date = Date()) throws {
        guard RecordingStore.fileExists(fileName: recording.fileName) else {
            lastError = .fileMissing
            throw StoreError.fileMissing
        }
        let item = try requireLivePracticeItem(id: itemId)
        recording.session = nil
        if !item.recordings.contains(where: { $0.id == recording.id }) {
            item.recordings.append(recording)
        }
        if recording.practiceItem == nil {
            recording.practiceItem = item
        }
        try persistPracticeItemChanges()
        markInvocationIfEffective(item, now: now)
    }

    // MARK: - Launch

    func prepare() {
        RecordingStore.migrateLegacyFiles()
        seedIfNeeded()
        ensureProfile()
        mergeLegacyActiveTasksIfNeeded()
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
        guard let sessions = try? repository.sessions(),
              let items = try? repository.practiceItemsIncludingDeleted()
        else { return 0 }
        let referenced = RecordingStore.referencedFileNames(
            practiceItems: items,
            sessions: sessions
        )
        return RecordingStore.removeOrphans(referenced: referenced)
    }

    // MARK: - Tasks

    @discardableResult
    func activateTemplate(
        _ templateId: String,
        now: Date = Date(),
        calendar _: Calendar = .current
    ) -> String? {
        guard let template = try? repository.task(id: templateId) else {
            lastError = .notFound
            return nil
        }
        guard template.isTemplate else { return template.id }

        let stableId = PracticeTaskOrigin.stableActiveId(templateId: template.id)
        if let tombstone = try? repository.taskIncludingDeleted(id: stableId),
           tombstone.deletedAt != nil {
            lastError = .notFound
            return nil
        }
        if let live = try? repository.task(id: stableId) {
            return ensureForToday(live.id, now: now)
        }

        guard let profileId = requireProfileId() else { return nil }
        let copy = TaskItem(
            id: stableId, title: template.title, subtitle: template.subtitle,
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
    func ensureForToday(_ taskId: String, now: Date = Date()) -> String? {
        guard let task = try? repository.task(id: taskId) else {
            lastError = .notFound
            return nil
        }
        return produce {
            task.status = .active
            task.startedOn = now
            task.touch()
            try repository.save()
            return task.id
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
    func createFromAIDraft(_ draft: AIPracticeDraft, originKey: String? = nil) -> String? {
        let key = originKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !key.isEmpty, let live = try? repository.liveTask(originKey: key) {
            live.title = draft.title
            live.subtitle = draft.subtitleLine
            live.category = draft.category
            live.targetMin = draft.targetMin
            live.steps = draft.steps
            guard let id = ensureForToday(live.id) else { return nil }
            applySyncUpsert(live)
            return id
        }

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
            profileId: profileId,
            originKey: key
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

    func isTemplateOriginDeleted(_ templateId: String) -> Bool {
        let id = PracticeTaskOrigin.stableActiveId(templateId: templateId)
        guard let task = try? repository.taskIncludingDeleted(id: id) else { return false }
        return task.deletedAt != nil
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
                if let profileId = profileId(for: rec) {
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
                if let profileId = profileId(for: rec) {
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

    func practiceReviewContext(recordingId: String) -> PracticeReviewContext? {
        guard let recording = try? repository.recording(id: recordingId) else { return nil }
        if let item = practiceItemOwning(recording) {
            return .practiceItem(item.id)
        }
        if let session = sessionOwning(recording), let sessionId = UUID(uuidString: session.id) {
            return .legacySession(sessionId)
        }
        return nil
    }

    func reviewContext(recordingId: String) -> MediaReviewContext? {
        guard let recording = try? repository.recording(id: recordingId) else { return nil }
        if let item = practiceItemOwning(recording) {
            return MediaReviewContext(
                recordingId: recording.id,
                fileName: recording.fileName,
                durationSec: recording.durationSec,
                taskTitle: item.title,
                steps: item.steps,
                bpm: item.bpm ?? 0,
                timeSig: item.timeSignature ?? "",
                note: item.note
            )
        }
        guard let session = sessionOwning(recording) else { return nil }
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

    private func mergeLegacyActiveTasksIfNeeded() {
        guard !defaults.bool(forKey: PracticeActiveTaskMerge.defaultsKey) else { return }
        perform {
            try PracticeActiveTaskMerge.applyPending(repository: repository)
            defaults.set(true, forKey: PracticeActiveTaskMerge.defaultsKey)
        }
    }

    private func requireProfileId() -> String? {
        guard let id = try? repository.ensureDefaultProfile().id else {
            lastError = .saveFailed
            return nil
        }
        return id
    }

    private func requireProfileUUID() throws -> UUID {
        guard let raw = requireProfileId(), let id = UUID(uuidString: raw) else {
            throw lastError ?? .saveFailed
        }
        return id
    }

    private func requireLivePracticeItem(id: UUID) throws -> PracticeItem {
        let profileId = try requireProfileUUID()
        guard let item = try repository.practiceItem(id: id, profileId: profileId) else {
            lastError = .notFound
            throw StoreError.notFound
        }
        return item
    }

    private func requireLiveProject(id: UUID) throws -> Project {
        let profileId = try requireProfileUUID()
        guard let project = try repository.project(id: id, profileId: profileId) else {
            lastError = .notFound
            throw StoreError.notFound
        }
        return project
    }

    private func clearVersionRefs(pointingTo itemId: UUID, now: Date) throws {
        let projects = try repository.projectsIncludingDeleted()
        for project in projects {
            var changed = false
            if project.stageVersionItemId == itemId {
                project.stageVersionItemId = nil
                changed = true
            }
            if project.finalVersionItemId == itemId {
                project.finalVersionItemId = nil
                changed = true
            }
            if changed { project.updatedAt = now }
        }
    }

    private func setProjectVersion(
        projectId: UUID,
        itemId: UUID?,
        now: Date,
        write: (Project, UUID?) -> Void
    ) throws {
        let project = try requireLiveProject(id: projectId)
        if let itemId {
            let item = try requireLivePracticeItem(id: itemId)
            let snap = Self.snapshot(from: item)
            guard snap.projectId == project.id, PracticeItemRules.isEffective(snap) else {
                lastError = .invalidInput
                throw StoreError.invalidInput
            }
            write(project, itemId)
        } else {
            write(project, nil)
        }
        project.updatedAt = now
        try persistPracticeItemChanges()
    }

    private func markInvocationIfEffective(_ item: PracticeItem, now: Date) {
        let snap = PracticeStore.snapshot(from: item)
        guard PracticeItemRules.isEffective(snap) else { return }
        invocationStore?.markCompleted(taskId: item.id.uuidString, now: now)
    }

    private func persistPracticeItemChanges() throws {
        do {
            try repository.save()
            lastError = nil
        } catch {
            repository.rollback()
            lastError = StoreError.from(error)
            throw lastError ?? .saveFailed
        }
    }

    private func practiceItemOwning(_ recording: RecordingRef) -> PracticeItem? {
        if let item = recording.practiceItem { return item }
        let items = (try? repository.practiceItemsIncludingDeleted()) ?? []
        return items.first { item in
            item.recordings.contains { $0.id == recording.id && $0.deletedAt == nil }
        }
    }

    private func sessionOwning(_ recording: RecordingRef) -> PracticeSession? {
        if let session = recording.session { return session }
        return try? repository.sessions().first { session in
            session.recordings.contains { $0.id == recording.id && $0.deletedAt == nil }
        }
    }

    private func profileId(for recording: RecordingRef) -> String? {
        if let item = practiceItemOwning(recording) {
            return item.profileId.uuidString
        }
        if let profileId = sessionOwning(recording)?.profileId, !profileId.isEmpty {
            return profileId
        }
        return nil
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
