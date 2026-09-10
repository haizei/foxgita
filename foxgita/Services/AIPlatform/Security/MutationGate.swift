import Foundation

actor ApprovalAuthority {
    private let issuer: ApprovalTokenIssuer
    private var consumed: Set<UUID> = []

    init(issuer: ApprovalTokenIssuer) {
        self.issuer = issuer
    }

    func validate(
        _ token: ApprovalToken,
        userID: String,
        sessionID: String,
        draftID: String,
        draftHash: String,
        now: Date
    ) throws {
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
        guard consumed.insert(token.id).inserted else {
            throw GateRefusal.approvalReplayed
        }
    }
}

struct MutationGate: Sendable {
    let authority: ApprovalAuthority

    init(authority: ApprovalAuthority) {
        self.authority = authority
    }

    func validate(
        _ token: ApprovalToken,
        userID: String,
        sessionID: String,
        draftID: String,
        draftHash: String,
        now: Date
    ) async throws {
        try await authority.validate(
            token,
            userID: userID,
            sessionID: sessionID,
            draftID: draftID,
            draftHash: draftHash,
            now: now
        )
    }
}
