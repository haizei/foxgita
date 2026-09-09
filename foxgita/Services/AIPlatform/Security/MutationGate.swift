import Foundation

actor ApprovalReplayStore {
    private var consumed: Set<UUID> = []

    func consume(_ id: UUID) throws {
        guard consumed.insert(id).inserted else {
            throw GateRefusal.approvalReplayed
        }
    }
}

struct MutationGate: Sendable {
    let issuer: ApprovalTokenIssuer
    let replayStore: ApprovalReplayStore

    init(issuer: ApprovalTokenIssuer, replayStore: ApprovalReplayStore = ApprovalReplayStore()) {
        self.issuer = issuer
        self.replayStore = replayStore
    }

    func validate(
        _ token: ApprovalToken,
        userID: String,
        sessionID: String,
        draftID: String,
        draftHash: String,
        now: Date
    ) async throws {
        guard issuer.verifies(token) else {
            throw GateRefusal.approvalMismatch
        }
        guard token.userID == userID,
              token.sessionID == sessionID,
              token.draftID == draftID,
              token.draftHash == draftHash else {
            throw GateRefusal.approvalMismatch
        }
        guard token.expiresAt > now else {
            throw GateRefusal.approvalExpired
        }
        try await replayStore.consume(token.id)
    }
}
