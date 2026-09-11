import CryptoKit
import Foundation

@MainActor
final class PracticeDraftApprovalGate {
    private let issuer: ApprovalTokenIssuer
    private let gate: MutationGate

    init(secret: Data = Data(UUID().uuidString.utf8)) {
        let issuer = ApprovalTokenIssuer(secret: secret)
        self.issuer = issuer
        self.gate = MutationGate(authority: ApprovalAuthority(issuer: issuer))
    }

    func issue(
        draft: AIPracticeDraft,
        userID: String,
        sessionID: String,
        draftID: String,
        now: Date = Date()
    ) -> ApprovalToken {
        issuer.issue(
            userID: userID,
            sessionID: sessionID,
            draftID: draftID,
            draftHash: Self.hash(draft),
            expiresAt: now.addingTimeInterval(300)
        )
    }

    func validate(
        _ token: ApprovalToken,
        draft: AIPracticeDraft,
        userID: String,
        sessionID: String,
        draftID: String,
        now: Date = Date()
    ) async throws {
        try await gate.validate(
            token,
            userID: userID,
            sessionID: sessionID,
            draftID: draftID,
            draftHash: Self.hash(draft),
            now: now
        )
    }

    static func hash(_ draft: AIPracticeDraft) -> String {
        let fields = [
            draft.title,
            draft.category.rawValue,
            String(draft.targetMin),
            draft.steps.joined(separator: "\u{1F}"),
            draft.chords.joined(separator: "\u{1F}"),
        ]
        let digest = SHA256.hash(data: Data(fields.joined(separator: "\u{1E}").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
