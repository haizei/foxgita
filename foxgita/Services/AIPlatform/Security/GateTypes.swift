import Foundation

enum GateRefusal: Error, Equatable, Sendable {
    case provenanceRefused(ResourceRef)
    case approvalMissing
    case approvalExpired
    case approvalMismatch
    case approvalReplayed
    case staleDraft
    case constraintViolated(String)
}
