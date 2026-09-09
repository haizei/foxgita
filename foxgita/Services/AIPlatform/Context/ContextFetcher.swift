import Foundation

struct ContextFetchScope: Sendable {
    let invocationID: UUID
    let sessionID: UUID
    let authorizedResources: Set<ResourceRef>

    func authorizes(_ ref: ResourceRef) -> Bool {
        authorizedResources.contains(ref)
    }
}

protocol ContextResourceReading: Sendable {
    func fetch(ref: ResourceRef, scope: ContextFetchScope) async throws -> ContextResource
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
    case notAuthorized(ResourceRef)
    case resourceMismatch(requested: ResourceRef, received: ResourceRef)
}

struct ContextFetcher: Sendable {
    let reader: any ContextResourceReading

    func fetch(
        refs: [ResourceRef],
        policy: FetchPolicy,
        scope: ContextFetchScope
    ) async throws -> (ContextSnapshot, SeenSet) {
        guard refs.count <= policy.maxItems else { throw ContextFetchError.tooManyItems }

        var sections: [ContextSection] = []
        var warnings: [ContextWarning] = []
        var revisionTokens: [String] = []
        var total = 0

        for ref in refs {
            guard policy.allowedKinds.contains(ref.kind) else {
                throw ContextFetchError.kindNotAllowed(ref)
            }
            guard scope.authorizes(ref) else {
                throw ContextFetchError.notAuthorized(ref)
            }

            let resource = try await reader.fetch(ref: ref, scope: scope)
            guard resource.ref == ref else {
                throw ContextFetchError.resourceMismatch(requested: ref, received: resource.ref)
            }
            let fenced = ContextFencer.fence(resource.text, limit: policy.maxCharactersPerItem)
            guard total + fenced.text.count <= policy.maxTotalCharacters else { break }

            total += fenced.text.count
            warnings += fenced.warnings
            sections.append(ContextSection(ref: ref, text: fenced.text, trusted: resource.trusted))
            revisionTokens.append("\(ref.id)@\(resource.revision)")
        }

        let id = UUID()
        let snapshot = ContextSnapshot(
            id: id,
            createdAt: Date(),
            sections: sections,
            warnings: warnings,
            revision: revisionTokens.joined(separator: ":")
        )
        return (snapshot, SeenSet(snapshotID: id, resources: Set(sections.map(\.ref))))
    }
}
