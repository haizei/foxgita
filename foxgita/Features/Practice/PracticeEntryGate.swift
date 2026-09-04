import Foundation

struct PracticeEntryToken: Hashable, Sendable {
    let id: UUID

    init(id: UUID = UUID()) {
        self.id = id
    }
}

enum PracticeEntry {
    static func custom(name: String, category: PracticeCategory) -> PracticeItemInput {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return PracticeItemInput(
            title: trimmed.isEmpty ? String(localized: "未命名练习") : trimmed,
            category: category,
            source: .custom,
            originId: nil,
            bpm: nil,
            timeSignature: nil,
            steps: [],
            subtitle: "",
            targetMin: 10
        )
    }

    static func recommend(from template: TaskItem) -> PracticeItemInput {
        PracticeItemInput(
            title: template.title,
            category: template.category,
            source: .recommend,
            originId: PracticeTaskOrigin.templateOriginKey(templateId: template.id),
            bpm: template.defaultBpm,
            timeSignature: template.timeSig,
            steps: template.steps,
            subtitle: template.subtitle,
            targetMin: template.targetMin
        )
    }

    static func photo(draft: AIPracticeDraft, generationId: String) -> PracticeItemInput {
        PracticeItemInput(
            title: draft.title,
            category: draft.category,
            source: .photo,
            originId: PracticeTaskOrigin.photoOriginKey(generationId: generationId),
            bpm: nil,
            timeSignature: nil,
            steps: draft.steps,
            subtitle: draft.subtitleLine,
            targetMin: draft.targetMin
        )
    }

    static func next(draft: AIPracticeDraft, generationId: String) -> PracticeItemInput {
        PracticeItemInput(
            title: draft.title,
            category: draft.category,
            source: .next,
            originId: PracticeTaskOrigin.nextOriginKey(generationId: generationId),
            bpm: nil,
            timeSignature: nil,
            steps: draft.steps,
            subtitle: draft.subtitleLine,
            targetMin: draft.targetMin
        )
    }
}

/// Guards one UI action / generation request against duplicate creates.
/// Token reuse is double-callback protection; origin reuse is photo/next request
/// idempotency. Distinct tokens with the same title still create two items.
@MainActor
final class PracticeEntryGate {
    private var itemsByToken: [UUID: PracticeItem] = [:]
    private var itemsByOrigin: [String: PracticeItem] = [:]

    func submit(
        store: PracticeStore,
        input: PracticeItemInput,
        token: PracticeEntryToken,
        now: Date,
        calendar: Calendar
    ) throws -> PracticeItem {
        if let item = itemsByToken[token.id] {
            return item
        }
        if let origin = reusableOrigin(input), let item = itemsByOrigin[origin] {
            itemsByToken[token.id] = item
            return item
        }
        let item = try store.createPracticeItem(input: input, now: now, calendar: calendar)
        itemsByToken[token.id] = item
        if let origin = reusableOrigin(input) {
            itemsByOrigin[origin] = item
        }
        return item
    }

    func commitIfSucceeded(
        _ succeeded: Bool,
        store: PracticeStore,
        input: PracticeItemInput,
        token: PracticeEntryToken,
        now: Date,
        calendar: Calendar
    ) throws -> PracticeItem? {
        guard succeeded else { return nil }
        return try submit(store: store, input: input, token: token, now: now, calendar: calendar)
    }

    private func reusableOrigin(_ input: PracticeItemInput) -> String? {
        guard input.source == .photo || input.source == .next else { return nil }
        let origin = input.originId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return origin.isEmpty ? nil : origin
    }
}
