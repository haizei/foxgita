import Foundation
import Observation

struct NextFocusContext: Codable, Equatable, Sendable {
    var profileID: UUID
    var sourceID: UUID
    var sourceDay: String
    var title: String
    var categoryRaw: String
    var steps: [String] = []
    var note: String = ""
    var durationSeconds: Int = 0
    var projectID: UUID? = nil
    var projectName: String = ""
    var projectFocus: String = ""
    var bpm: Int? = nil
    var timeSignature: String? = nil
    var targetMinutes: Int = 10
    var scoreLink: ScorePracticeLink? = nil
    var observations: [String] = []

    var factualRecap: String { "已保存“\(title)”的练习记录。" }
}

struct NextFocusProjectUpdate: Codable, Equatable {
    var projectID: UUID
    var expectedFocus: String
    var text: String
}

struct NextFocusDraft: Codable, Identifiable, Equatable {
    var id = UUID()
    var context: NextFocusContext
    var text = ""
    var recap = ""
    var basis = ""
    var revision = 0
    var generationID: UUID? = nil
    var generated = false
    var editedByUser: Bool? = nil
    var consumed: Bool? = nil
    var generationError: String? = nil
    var pendingProjectUpdate: NextFocusProjectUpdate? = nil
    var requiresSupplement: Bool? = nil
    var supplement: String? = nil
}

struct NextFocusAction: Codable, Identifiable, Equatable {
    var id: UUID
    var context: NextFocusContext
    var text: String
    var skippedDay: String? = nil
    var executionDay: String? = nil
    var executionID: UUID? = nil

    var originID: String { "continuation.\(id.uuidString)" }
}

struct NextFocusDocument: Codable, Equatable {
    var version = 1
    var drafts: [String: NextFocusDraft] = [:]
    var action: NextFocusAction? = nil
    var completedExecutionIDs: [UUID]? = nil
}

struct NextFocusGenerationTicket: Equatable {
    var context: NextFocusContext
    var generationID: UUID
    var revision: Int
}

enum NextFocusError: LocalizedError, Equatable {
    case emptyFocus, replacementRequired, missingDraft, invalidOutput, unsupportedVersion, changedAction
    var errorDescription: String? {
        switch self {
        case .emptyFocus: "请填写下次练习重点"
        case .replacementRequired: "还有未完成的重点，请选择保留或替换"
        case .missingDraft: "重点草稿暂时无法读取，请重试"
        case .invalidOutput: "未能整理出有效的总结，请重试或手动填写"
        case .unsupportedVersion: "重点数据版本暂不支持，原数据已保留"
        case .changedAction: "建议练习已发生变化，请返回首页重新查看"
        }
    }
}

@MainActor
protocol NextFocusPersisting {
    func read(profileID: UUID) throws -> Data?
    func write(_ data: Data, profileID: UUID) throws
    func removeAll() throws
}

@MainActor
struct NextFocusFilePersistence: NextFocusPersisting {
    var directory: URL
    init(directory: URL? = nil) {
        if let directory { self.directory = directory; return }
        let folder: String
        if PracticeTestEnvironment.isActive {
            let run = PracticeTestEnvironment.recoveryRunID?.uuidString ?? String(ProcessInfo.processInfo.processIdentifier)
            folder = "NextFocus-Tests-" + run
        } else { folder = "NextFocus" }
        self.directory = URL.applicationSupportDirectory.appendingPathComponent(folder, isDirectory: true)
    }
    func read(profileID: UUID) throws -> Data? {
        let url = directory.appendingPathComponent(profileID.uuidString + ".json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }
    func write(_ data: Data, profileID: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(profileID.uuidString + ".json"), options: .atomic)
    }
    func removeAll() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }
}

/// Publish a new document only after its atomic write succeeds. A failed read
/// never creates an empty document over the unreadable original.
@Observable @MainActor
final class NextFocusStore {
    private(set) var documents: [UUID: NextFocusDocument] = [:]
    private(set) var readErrors: [UUID: String] = [:]
    private(set) var generating: Set<String> = []
    private(set) var generationErrors: [String: String] = [:]
    @ObservationIgnored private let persistence: any NextFocusPersisting
    @ObservationIgnored private var jobs: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var invalidatedGenerations: Set<UUID> = []

    init(persistence: (any NextFocusPersisting)? = nil) {
        self.persistence = persistence ?? NextFocusFilePersistence()
    }

    func document(_ profileID: UUID) throws -> NextFocusDocument {
        if let existing = documents[profileID] {
            readErrors[profileID] = nil
            return existing
        }
        do {
            let data = try persistence.read(profileID: profileID)
            let value = try data.map { try JSONDecoder().decode(NextFocusDocument.self, from: $0) }
                ?? NextFocusDocument()
            guard value.version == 1 else { throw NextFocusError.unsupportedVersion }
            documents[profileID] = value
            readErrors[profileID] = nil
            return value
        } catch {
            readErrors[profileID] = error.localizedDescription
            throw error
        }
    }

    private func update(_ profileID: UUID, _ change: (inout NextFocusDocument) throws -> Void) throws {
        var next = try document(profileID)
        try change(&next)
        try persistence.write(JSONEncoder().encode(next), profileID: profileID)
        documents[profileID] = next
    }

    @discardableResult
    func prepare(_ context: NextFocusContext) throws -> NextFocusDraft {
        if let draft = try document(context.profileID).drafts[context.sourceID.uuidString] { return draft }
        let draft = NextFocusDraft(context: context, recap: context.factualRecap)
        try update(context.profileID) { $0.drafts[context.sourceID.uuidString] = draft }
        return draft
    }

    func edit(profileID: UUID, sourceID: UUID, text: String) throws {
        invalidateGeneration(profileID: profileID, sourceID: sourceID)
        guard text.count <= 600 else { throw NextFocusError.invalidOutput }
        try update(profileID) { doc in
            guard var draft = doc.drafts[sourceID.uuidString] else { throw NextFocusError.missingDraft }
            draft.text = text
            draft.requiresSupplement = false
            draft.revision += 1
            draft.editedByUser = true
            draft.generationError = nil
            doc.drafts[sourceID.uuidString] = draft
        }
    }

    func editSupplement(profileID: UUID, sourceID: UUID, text: String) throws {
        invalidateGeneration(profileID: profileID, sourceID: sourceID)
        guard text.count <= 600 else { throw NextFocusError.invalidOutput }
        try update(profileID) { doc in
            guard var draft = doc.drafts[sourceID.uuidString] else { throw NextFocusError.missingDraft }
            draft.supplement = text
            draft.revision += 1
            doc.drafts[sourceID.uuidString] = draft
        }
    }

    func beginGeneration(_ context: NextFocusContext) throws -> NextFocusGenerationTicket {
        _ = try prepare(context)
        let generation = UUID()
        var revision = 0
        try update(context.profileID) { doc in
            guard var draft = doc.drafts[context.sourceID.uuidString] else { throw NextFocusError.missingDraft }
            draft.generationID = generation
            draft.generationError = nil
            revision = draft.revision
            doc.drafts[context.sourceID.uuidString] = draft
        }
        return .init(context: context, generationID: generation, revision: revision)
    }

    func applyGenerated(_ result: NextFocusOutput, ticket: NextFocusGenerationTicket) throws {
        guard !invalidatedGenerations.contains(ticket.generationID) else { return }
        let profile = ticket.context.profileID, source = ticket.context.sourceID.uuidString
        guard let current = try document(profile).drafts[source],
              current.generationID == ticket.generationID, current.revision == ticket.revision else { return }
        try update(profile) { doc in
            guard var draft = doc.drafts[source] else { throw NextFocusError.missingDraft }
            draft.recap = result.recap
            draft.context = ticket.context
            draft.text = result.focus
            draft.basis = result.basis
            draft.generated = true
            draft.requiresSupplement = result.focus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            draft.editedByUser = false
            draft.generationError = nil
            doc.drafts[source] = draft
        }
        NextFocusPageTiming.mark(sourceID: ticket.context.sourceID, .draftSaved)
    }

    @discardableResult
    func confirm(profileID: UUID, sourceID: UUID, replace: Bool = false,
                 updateProject: Bool = false, reviewedContext: NextFocusContext? = nil) throws -> NextFocusAction {
        guard let draft = try document(profileID).drafts[sourceID.uuidString] else { throw NextFocusError.missingDraft }
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw NextFocusError.emptyFocus }
        let context = reviewedContext ?? draft.context
        guard context.profileID == profileID, context.sourceID == sourceID else { throw NextFocusError.changedAction }
        let actionID = draft.consumed == true ? UUID() : draft.id
        var action = NextFocusAction(id: actionID, context: context, text: text)
        try update(profileID) { doc in
            if let old = doc.action {
                if old.id != draft.id && !replace { throw NextFocusError.replacementRequired }
                if old.id != draft.id { doc.drafts[old.context.sourceID.uuidString]?.consumed = true }
                if old.id == draft.id { action = old; action.text = text; action.context = context }
            }
            doc.action = action
            doc.drafts[sourceID.uuidString]?.id = action.id
            doc.drafts[sourceID.uuidString]?.consumed = false
            doc.drafts[sourceID.uuidString]?.revision += 1
            doc.drafts[sourceID.uuidString]?.editedByUser = true
            doc.drafts[sourceID.uuidString]?.pendingProjectUpdate = nil
            if updateProject, let projectID = context.projectID {
                doc.drafts[sourceID.uuidString]?.pendingProjectUpdate = .init(
                    projectID: projectID, expectedFocus: context.projectFocus, text: text)
            }
        }
        return action
    }

    func visibleAction(profileID: UUID, day: String) throws -> NextFocusAction? {
        let action = try document(profileID).action
        return action?.skippedDay == day ? nil : action
    }

    func skip(profileID: UUID, day: String?) throws {
        try update(profileID) { $0.action?.skippedDay = day }
    }

    func delete(profileID: UUID) throws {
        try update(profileID) { doc in
            if let action = doc.action { doc.drafts[action.context.sourceID.uuidString]?.consumed = true }
            doc.action = nil
        }
    }

    func associate(profileID: UUID, actionID: UUID, itemID: UUID, day: String) throws {
        try update(profileID) { doc in
            guard doc.action?.id == actionID else { throw NextFocusError.changedAction }
            doc.action?.executionDay = day
            doc.action?.executionID = itemID
        }
    }

    func complete(profileID: UUID, itemID: UUID, originID: String?) throws {
        guard let action = try document(profileID).action,
              action.executionID == itemID || action.originID == originID else { return }
        try update(profileID) { doc in
            doc.drafts[action.context.sourceID.uuidString]?.consumed = true
            var completed = doc.completedExecutionIDs ?? []
            if !completed.contains(itemID) { completed.append(itemID) }
            doc.completedExecutionIDs = completed
            doc.action = nil
        }
    }

    func clearProjectUpdate(profileID: UUID, sourceID: UUID) throws {
        try update(profileID) { $0.drafts[sourceID.uuidString]?.pendingProjectUpdate = nil }
    }

    func editProjectUpdate(profileID: UUID, sourceID: UUID, text: String) throws {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw NextFocusError.emptyFocus }
        guard value.count <= 600 else { throw NextFocusError.invalidOutput }
        try update(profileID) { doc in
            guard doc.drafts[sourceID.uuidString]?.pendingProjectUpdate != nil else {
                throw NextFocusError.missingDraft
            }
            doc.drafts[sourceID.uuidString]?.pendingProjectUpdate?.text = value
        }
    }

    /// An unsaved edit still supersedes the request that preceded it.
    private func invalidateGeneration(profileID: UUID, sourceID: UUID) {
        if let id = documents[profileID]?.drafts[sourceID.uuidString]?.generationID {
            invalidatedGenerations.insert(id)
        }
        let key = "\(profileID).\(sourceID)"
        jobs[key]?.cancel()
        jobs[key] = nil
        generating.remove(key)
    }

    func reset() throws {
        try persistence.removeAll()
        for job in jobs.values { job.cancel() }
        jobs.removeAll()
        generating.removeAll()
        documents.removeAll()
        readErrors.removeAll()
        generationErrors.removeAll()
        invalidatedGenerations.removeAll()
    }

    func isGenerating(_ context: NextFocusContext) -> Bool { generating.contains(jobKey(context)) }
    func generationError(_ context: NextFocusContext) -> String? { generationErrors[jobKey(context)] }
    private func jobKey(_ context: NextFocusContext) -> String { "\(context.profileID).\(context.sourceID)" }

    func generate(_ context: NextFocusContext, supplement: String = "", baseURL: String,
                  model: String, apiKey: String, client: (any NextFocusGenerating)? = nil) throws {
        let client = client ?? NextFocusClient()
        let requestModel = NextFocusClient.preferredModel(for: model)
        let ticket = try beginGeneration(context)
        let key = jobKey(context)
        generationErrors[key] = nil
        jobs[key]?.cancel()
        generating.insert(key)
        NextFocusPageTiming.mark(sourceID: context.sourceID, .generationQueued)
        NextFocusPageTiming.setModel(sourceID: context.sourceID, model: requestModel)
        jobs[key] = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            defer {
                if self.documents[context.profileID]?.drafts[context.sourceID.uuidString]?.generationID == ticket.generationID {
                    self.generating.remove(key)
                    self.jobs[key] = nil
                }
            }
            do {
                try Task.checkCancellation()
                NextFocusPageTiming.mark(sourceID: context.sourceID, .requestStarted)
                let output = try await client.generate(context: context, supplement: supplement,
                                                       baseURL: baseURL, model: requestModel, apiKey: apiKey)
                try Task.checkCancellation()
                NextFocusPageTiming.mark(sourceID: context.sourceID, .responseParsed)
                try self.applyGenerated(output, ticket: ticket)
            } catch is CancellationError {
                return
            } catch {
                // A failed result must not replace edits or errors for a newer request.
                guard !Task.isCancelled, !self.invalidatedGenerations.contains(ticket.generationID),
                      self.documents[context.profileID]?.drafts[context.sourceID.uuidString]?.generationID == ticket.generationID else { return }
                do {
                    try self.update(context.profileID) { doc in
                        doc.drafts[context.sourceID.uuidString]?.generationError = error.localizedDescription
                    }
                } catch { self.generationErrors[key] = "结果暂未保存：\(error.localizedDescription)。请重试。" }
            }
        }
    }
}
