import Foundation

protocol ContextResourceReading: Sendable {
    func fetch(ref: ResourceRef) async throws -> ContextResource
}

struct ContextResource: Sendable {
    let ref: ResourceRef
    let text: String
    let trusted: Bool
    let revision: String
}

enum ContextFetchError: Error, Equatable {
    case kindNotAllowed(ResourceRef)
    case tooManyItems
    case notFound(ResourceRef)
}

struct ContextFetcher: Sendable {
    let reader: any ContextResourceReading

    func fetch(refs: [ResourceRef], policy: FetchPolicy) async throws -> (ContextSnapshot, SeenSet) {
        guard refs.count <= policy.maxItems else { throw ContextFetchError.tooManyItems }

        var sections: [ContextSection] = []
        var warnings: [ContextWarning] = []
        var total = 0

        for ref in refs {
            guard policy.allowedKinds.contains(ref.kind) else {
                throw ContextFetchError.kindNotAllowed(ref)
            }

            let resource = try await reader.fetch(ref: ref)
            let fenced = ContextFencer.fence(resource.text, limit: policy.maxCharactersPerItem)
            guard total + fenced.text.count <= policy.maxTotalCharacters else { break }

            total += fenced.text.count
            warnings += fenced.warnings
            sections.append(ContextSection(ref: ref, text: fenced.text, trusted: resource.trusted))
        }

        let id = UUID()
        let snapshot = ContextSnapshot(
            id: id,
            createdAt: Date(),
            sections: sections,
            warnings: warnings,
            revision: sections.map(\.ref.id).joined(separator: ":")
        )
        return (snapshot, SeenSet(snapshotID: id, resources: Set(sections.map(\.ref))))
    }
}
