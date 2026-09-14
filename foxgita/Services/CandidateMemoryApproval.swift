import CryptoKit
import Foundation

struct CandidateMemoryDraft: Equatable, Sendable {
    let profileID: String
    let evidenceID: String
    let evidenceSummary: String
    var semantic: String
    let skill: SkillDefinition

    var id: String { CandidateMemoryApprovalGate.hash(self) }
}

@MainActor
final class CandidateMemoryApprovalGate {
    private let issuer: ApprovalTokenIssuer
    private let gate: MutationGate

    init(secret: Data = Data(UUID().uuidString.utf8)) {
        let issuer = ApprovalTokenIssuer(secret: secret)
        self.issuer = issuer
        self.gate = MutationGate(authority: ApprovalAuthority(issuer: issuer))
    }

    func issue(
        _ draft: CandidateMemoryDraft,
        userID: String,
        sessionID: String,
        now: Date = Date()
    ) -> ApprovalToken {
        issuer.issue(
            userID: userID,
            sessionID: sessionID,
            draftID: draft.id,
            draftHash: Self.hash(draft),
            expiresAt: now.addingTimeInterval(300)
        )
    }

    func validate(
        _ token: ApprovalToken,
        draft: CandidateMemoryDraft,
        userID: String,
        sessionID: String,
        now: Date = Date()
    ) async throws {
        try await gate.validate(
            token,
            userID: userID,
            sessionID: sessionID,
            draftID: draft.id,
            draftHash: Self.hash(draft),
            now: now
        )
    }

    static func hash(_ draft: CandidateMemoryDraft) -> String {
        let fields = [
            draft.profileID,
            draft.evidenceID,
            draft.semantic.trimmingCharacters(in: .whitespacesAndNewlines),
            draft.skill.id,
            draft.skill.version,
        ]
        let digest = SHA256.hash(data: Data(fields.joined(separator: "\u{1E}").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
