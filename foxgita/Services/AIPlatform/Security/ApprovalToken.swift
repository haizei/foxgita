import CryptoKit
import Foundation

struct ApprovalToken: Hashable, Codable, Sendable {
    let id: UUID
    let userID: String
    let sessionID: String
    let draftID: String
    let draftHash: String
    let expiresAt: Date
    let signature: Data
}

struct ApprovalTokenIssuer: Sendable {
    private let secret: Data

    init(secret: Data) {
        self.secret = secret
    }

    func issue(
        userID: String,
        sessionID: String,
        draftID: String,
        draftHash: String,
        expiresAt: Date
    ) -> ApprovalToken {
        let id = UUID()
        let signature = signature(
            id: id,
            userID: userID,
            sessionID: sessionID,
            draftID: draftID,
            draftHash: draftHash,
            expiresAt: expiresAt
        )
        return ApprovalToken(
            id: id,
            userID: userID,
            sessionID: sessionID,
            draftID: draftID,
            draftHash: draftHash,
            expiresAt: expiresAt,
            signature: signature
        )
    }

    func verifies(_ token: ApprovalToken) -> Bool {
        let key = SymmetricKey(data: secret)
        return HMAC<SHA256>.isValidAuthenticationCode(
            token.signature,
            authenticating: signingPayload(
                id: token.id,
                userID: token.userID,
                sessionID: token.sessionID,
                draftID: token.draftID,
                draftHash: token.draftHash,
                expiresAt: token.expiresAt
            ),
            using: key
        )
    }

    private func signature(
        id: UUID,
        userID: String,
        sessionID: String,
        draftID: String,
        draftHash: String,
        expiresAt: Date
    ) -> Data {
        let key = SymmetricKey(data: secret)
        let code = HMAC<SHA256>.authenticationCode(
            for: signingPayload(
                id: id,
                userID: userID,
                sessionID: sessionID,
                draftID: draftID,
                draftHash: draftHash,
                expiresAt: expiresAt
            ),
            using: key
        )
        return Data(code)
    }

    private func signingPayload(
        id: UUID,
        userID: String,
        sessionID: String,
        draftID: String,
        draftHash: String,
        expiresAt: Date
    ) -> Data {
        var payload = Data()
        append(id.uuidString, to: &payload)
        append(userID, to: &payload)
        append(sessionID, to: &payload)
        append(draftID, to: &payload)
        append(draftHash, to: &payload)

        var expiration = expiresAt.timeIntervalSinceReferenceDate.bitPattern.bigEndian
        withUnsafeBytes(of: &expiration) { payload.append(contentsOf: $0) }
        return payload
    }

    private func append(_ value: String, to payload: inout Data) {
        let bytes = Data(value.utf8)
        var length = UInt64(bytes.count).bigEndian
        withUnsafeBytes(of: &length) { payload.append(contentsOf: $0) }
        payload.append(bytes)
    }
}
