//
//  PracticeRepository.swift
//  foxgita
//

import Foundation
import SwiftData

/// Persistence seam. `PracticeStore` holds the business rules and talks only to
/// this, so a future sync layer can decorate the SwiftData implementation
/// without any view changing.
@MainActor
protocol PracticeRepository: AnyObject {
    // Legacy Task / Session APIs — kept until daily PracticeItem is the write path.
    func tasks() throws -> [TaskItem]
    func task(id: String) throws -> TaskItem?
    func taskIncludingDeleted(id: String) throws -> TaskItem?
    func liveTask(originKey: String) throws -> TaskItem?
    func sessions() throws -> [PracticeSession]
    func session(id: String) throws -> PracticeSession?
    func recording(id: String) throws -> RecordingRef?
    func add(_ task: TaskItem) throws
    func add(_ session: PracticeSession) throws
    func removeAll() throws
    func save() throws
    func rollback()
    func activeProfile() throws -> LocalProfile?
    func ensureDefaultProfile() throws -> LocalProfile
    func backfillEmptyProfileIds(_ profileId: String) throws

    func practiceItems(profileId: UUID) throws -> [PracticeItem]
    func practiceItem(id: UUID, profileId: UUID) throws -> PracticeItem?
    func insertPracticeItem(_ item: PracticeItem) throws
}

enum StoreError: LocalizedError, Equatable {
    case notFound
    case invalidInput
    case saveFailed
    case fileMissing
    case permissionDenied
    case diskFull

    var errorDescription: String? {
        switch self {
        case .notFound: return String(localized: "找不到这条练习")
        case .invalidInput: return String(localized: "这次练习的信息不完整，没能保存")
        case .saveFailed: return String(localized: "保存失败，请再试一次")
        case .fileMissing: return String(localized: "录音文件找不到了")
        case .permissionDenied: return String(localized: "权限不足，无法完成操作")
        case .diskFull: return String(localized: "存储空间不足")
        }
    }

    /// Maps a Foundation/SwiftData failure onto the cases the UI knows about.
    static func from(_ error: Error) -> StoreError {
        if let storeError = error as? StoreError { return storeError }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileWriteOutOfSpaceError: return .diskFull
            case NSFileWriteNoPermissionError, NSFileReadNoPermissionError: return .permissionDenied
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError: return .fileMissing
            default: break
            }
        }
        return .saveFailed
    }
}

@MainActor
final class SwiftDataPracticeRepository: PracticeRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func tasks() throws -> [TaskItem] {
        try context.fetch(
            FetchDescriptor<TaskItem>(
                predicate: #Predicate { $0.deletedAt == nil },
                sortBy: [SortDescriptor(\.sortOrder)]
            )
        )
    }

    func task(id: String) throws -> TaskItem? {
        try context.fetch(
            FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id && $0.deletedAt == nil })
        ).first
    }

    func taskIncludingDeleted(id: String) throws -> TaskItem? {
        try context.fetch(
            FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })
        ).first
    }

    func liveTask(originKey: String) throws -> TaskItem? {
        let key = originKey
        guard !key.isEmpty else { return nil }
        return try context.fetch(
            FetchDescriptor<TaskItem>(
                predicate: #Predicate<TaskItem> { $0.originKey == key && $0.deletedAt == nil }
            )
        ).first
    }

    func sessions() throws -> [PracticeSession] {
        try context.fetch(
            FetchDescriptor<PracticeSession>(
                predicate: #Predicate { $0.deletedAt == nil },
                sortBy: [SortDescriptor(\.endedAt, order: .reverse)]
            )
        )
    }

    func session(id: String) throws -> PracticeSession? {
        try context.fetch(
            FetchDescriptor<PracticeSession>(
                predicate: #Predicate { $0.id == id && $0.deletedAt == nil }
            )
        ).first
    }

    func recording(id: String) throws -> RecordingRef? {
        try context.fetch(
            FetchDescriptor<RecordingRef>(
                predicate: #Predicate { $0.id == id && $0.deletedAt == nil }
            )
        ).first
    }

    func add(_ task: TaskItem) throws { context.insert(task) }

    func add(_ session: PracticeSession) throws { context.insert(session) }

    func practiceItems(profileId: UUID) throws -> [PracticeItem] {
        let pid = profileId
        return try context.fetch(
            FetchDescriptor<PracticeItem>(
                predicate: #Predicate { $0.profileId == pid && $0.deletedAt == nil }
            )
        )
    }

    func practiceItem(id: UUID, profileId: UUID) throws -> PracticeItem? {
        let itemId = id
        let pid = profileId
        return try context.fetch(
            FetchDescriptor<PracticeItem>(
                predicate: #Predicate { $0.id == itemId && $0.profileId == pid && $0.deletedAt == nil }
            )
        ).first
    }

    func insertPracticeItem(_ item: PracticeItem) throws { context.insert(item) }

    func removeAll() throws {
        try context.delete(model: RecordingRef.self)
        try context.delete(model: PracticeSession.self)
        try context.delete(model: TaskItem.self)
        try context.delete(model: PracticeItem.self)
    }

    func save() throws {
        guard context.hasChanges else { return }
        try context.save()
    }

    func rollback() { context.rollback() }

    func activeProfile() throws -> LocalProfile? {
        try context.fetch(
            FetchDescriptor<LocalProfile>(
                predicate: #Predicate { $0.isActive == true },
                sortBy: [SortDescriptor(\.createdAt)]
            )
        ).first
    }

    func ensureDefaultProfile() throws -> LocalProfile {
        let all = try context.fetch(
            FetchDescriptor<LocalProfile>(sortBy: [SortDescriptor(\.createdAt)])
        )
        if let active = all.first(where: \.isActive) {
            for extra in all where extra.isActive && extra.id != active.id {
                extra.isActive = false
            }
            return active
        }
        if let first = all.first {
            first.isActive = true
            return first
        }
        let profile = LocalProfile()
        context.insert(profile)
        return profile
    }

    func backfillEmptyProfileIds(_ profileId: String) throws {
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        for task in tasks where task.profileId.isEmpty { task.profileId = profileId }
        let sessions = try context.fetch(FetchDescriptor<PracticeSession>())
        for session in sessions where session.profileId.isEmpty { session.profileId = profileId }
    }
}

/// Array-backed double used by the store tests. It deliberately keeps no
/// SwiftData context so command logic can be exercised in isolation.
@MainActor
final class InMemoryPracticeRepository: PracticeRepository {
    private(set) var storedTasks: [TaskItem] = []
    private(set) var storedSessions: [PracticeSession] = []
    private(set) var storedProfiles: [LocalProfile] = []
    private(set) var storedPracticeItems: [PracticeItem] = []
    private var pendingTasks: [TaskItem] = []
    private var pendingSessions: [PracticeSession] = []
    private var pendingPracticeItems: [PracticeItem] = []

    var saveError: StoreError?
    private(set) var saveCount = 0

    func tasks() throws -> [TaskItem] {
        storedTasks.filter { $0.deletedAt == nil }.sorted { $0.sortOrder < $1.sortOrder }
    }

    func task(id: String) throws -> TaskItem? {
        try tasks().first { $0.id == id }
    }

    func taskIncludingDeleted(id: String) throws -> TaskItem? {
        storedTasks.first { $0.id == id }
    }

    func liveTask(originKey: String) throws -> TaskItem? {
        guard !originKey.isEmpty else { return nil }
        return try tasks().first { $0.originKey == originKey }
    }

    func sessions() throws -> [PracticeSession] {
        storedSessions.filter { $0.deletedAt == nil }.sorted { $0.endedAt > $1.endedAt }
    }

    func session(id: String) throws -> PracticeSession? {
        try sessions().first { $0.id == id }
    }

    func recording(id: String) throws -> RecordingRef? {
        storedSessions.lazy.flatMap(\.recordings).first { $0.id == id && $0.deletedAt == nil }
    }

    func add(_ task: TaskItem) throws { pendingTasks.append(task) }

    func add(_ session: PracticeSession) throws { pendingSessions.append(session) }

    func practiceItems(profileId: UUID) throws -> [PracticeItem] {
        storedPracticeItems.filter { $0.profileId == profileId && $0.deletedAt == nil }
    }

    func practiceItem(id: UUID, profileId: UUID) throws -> PracticeItem? {
        storedPracticeItems.first { $0.id == id && $0.profileId == profileId && $0.deletedAt == nil }
    }

    func insertPracticeItem(_ item: PracticeItem) throws { pendingPracticeItems.append(item) }

    func removeAll() throws {
        storedTasks = []
        storedSessions = []
        storedPracticeItems = []
        pendingTasks = []
        pendingSessions = []
        pendingPracticeItems = []
    }

    func save() throws {
        if let saveError {
            throw saveError
        }
        saveCount += 1
        storedTasks.append(contentsOf: pendingTasks)
        storedSessions.append(contentsOf: pendingSessions)
        for item in pendingPracticeItems {
            if let index = storedPracticeItems.firstIndex(where: { $0.id == item.id }) {
                storedPracticeItems[index] = item
            } else {
                storedPracticeItems.append(item)
            }
        }
        pendingTasks = []
        pendingSessions = []
        pendingPracticeItems = []
    }

    func rollback() {
        pendingTasks = []
        pendingSessions = []
        pendingPracticeItems = []
    }

    func activeProfile() throws -> LocalProfile? {
        storedProfiles.filter(\.isActive).sorted { $0.createdAt < $1.createdAt }.first
    }

    func ensureDefaultProfile() throws -> LocalProfile {
        let all = storedProfiles.sorted { $0.createdAt < $1.createdAt }
        if let active = all.first(where: \.isActive) {
            for extra in all where extra.isActive && extra.id != active.id {
                extra.isActive = false
            }
            return active
        }
        if let first = all.first {
            first.isActive = true
            return first
        }
        let profile = LocalProfile()
        storedProfiles.append(profile)
        return profile
    }

    func backfillEmptyProfileIds(_ profileId: String) throws {
        for task in storedTasks where task.profileId.isEmpty { task.profileId = profileId }
        for task in pendingTasks where task.profileId.isEmpty { task.profileId = profileId }
        for session in storedSessions where session.profileId.isEmpty { session.profileId = profileId }
        for session in pendingSessions where session.profileId.isEmpty { session.profileId = profileId }
    }

    func profileCount() -> Int { storedProfiles.count }
}
