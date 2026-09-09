import Foundation
import Testing
@testable import foxgita

struct AISecurityGateTests {
    @Test func provenanceRejectsReferenceNotFetchedThisInvocation() {
        let seen = SeenSet(snapshotID: UUID(), resources: [ResourceRef(kind: "task", id: "seen")])
        #expect(throws: GateRefusal.provenanceRefused(ResourceRef(kind: "task", id: "guessed"))) {
            try ProvenanceGate.validate(ResourceRef(kind: "task", id: "guessed"), against: seen)
        }
    }

    @Test func approvalTokenRejectsWrongDraftAndReplay() async throws {
        let issuer = ApprovalTokenIssuer(secret: Data(repeating: 7, count: 32))
        let token = issuer.issue(
            userID: "u1",
            sessionID: "s1",
            draftID: "d1",
            draftHash: "h1",
            expiresAt: Date(timeIntervalSinceReferenceDate: 10_000)
        )
        let gate = MutationGate(issuer: issuer)

        await #expect(throws: GateRefusal.approvalMismatch) {
            try await gate.validate(
                token,
                userID: "u1",
                sessionID: "s1",
                draftID: "d2",
                draftHash: "h1",
                now: Date(timeIntervalSinceReferenceDate: 9_999)
            )
        }
        try await gate.validate(
            token,
            userID: "u1",
            sessionID: "s1",
            draftID: "d1",
            draftHash: "h1",
            now: Date(timeIntervalSinceReferenceDate: 9_999)
        )
        await #expect(throws: GateRefusal.approvalReplayed) {
            try await gate.validate(
                token,
                userID: "u1",
                sessionID: "s1",
                draftID: "d1",
                draftHash: "h1",
                now: Date(timeIntervalSinceReferenceDate: 9_999)
            )
        }
    }

    @Test func approvalTokenRejectsExpiredAndForgedTokens() async throws {
        let issuer = ApprovalTokenIssuer(secret: Data(repeating: 7, count: 32))
        let expired = issuer.issue(
            userID: "u1",
            sessionID: "s1",
            draftID: "d1",
            draftHash: "h1",
            expiresAt: Date(timeIntervalSinceReferenceDate: 10_000)
        )
        let valid = issuer.issue(
            userID: "u1",
            sessionID: "s1",
            draftID: "d1",
            draftHash: "h1",
            expiresAt: Date(timeIntervalSinceReferenceDate: 10_002)
        )
        let forged = ApprovalToken(
            id: valid.id,
            userID: valid.userID,
            sessionID: valid.sessionID,
            draftID: valid.draftID,
            draftHash: "h2",
            expiresAt: valid.expiresAt,
            signature: valid.signature
        )
        let gate = MutationGate(issuer: issuer)
        let now = Date(timeIntervalSinceReferenceDate: 10_001)

        await #expect(throws: GateRefusal.approvalExpired) {
            try await gate.validate(
                expired, userID: "u1", sessionID: "s1", draftID: "d1", draftHash: "h1", now: now
            )
        }
        await #expect(throws: GateRefusal.approvalMismatch) {
            try await gate.validate(
                forged, userID: "u1", sessionID: "s1", draftID: "d1", draftHash: "h2", now: now
            )
        }
    }
}
