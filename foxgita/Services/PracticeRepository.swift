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
    func tasks() throws -> [TaskItem]
    func task(id: String) throws -> TaskItem?
    func taskIncludingDeleted(id: String) throws -> TaskItem?
    func sessions() throws -> [PracticeSession]
    func session(id: String) throws -> PracticeSession?
    func recording(id: String) throws -> RecordingRef?
    func add(_ task: TaskItem) throws
    func add(_ session: PracticeSession) throws
    func removeAll() throws
    func save() throws
    func rollback()
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

    func removeAll() throws {
        try context.delete(model: RecordingRef.self)
        try context.delete(model: PracticeSession.self)
        try context.delete(model: TaskItem.self)
    }

    func save() throws {
        guard context.hasChanges else { return }
        try context.save()
    }

    func rollback() { context.rollback() }
}

/// Array-backed double used by the store tests. It deliberately keeps no
/// SwiftData context so command logic can be exercised in isolation.
@MainActor
final class InMemoryPracticeRepository: PracticeRepository {
    private(set) var storedTasks: [TaskItem] = []
    private(set) var storedSessions: [PracticeSession] = []
    private var pendingTasks: [TaskItem] = []
    private var pendingSessions: [PracticeSession] = []

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

    func removeAll() throws {
        storedTasks = []
        storedSessions = []
        pendingTasks = []
        pendingSessions = []
    }

    func save() throws {
        if let saveError {
            throw saveError
        }
        saveCount += 1
        storedTasks.append(contentsOf: pendingTasks)
        storedSessions.append(contentsOf: pendingSessions)
        pendingTasks = []
        pendingSessions = []
    }

    func rollback() {
        pendingTasks = []
        pendingSessions = []
    }
}
