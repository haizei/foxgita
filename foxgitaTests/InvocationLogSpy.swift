import Foundation
@testable import foxgita

final class InvocationLogSpy: AIInvocationRecording, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var inputs: [AIInvocationRecordInput] = []
    private(set) var artifactLinks: [(invocationID: String, artifactID: String, snapshotID: String)] = []

    func record(_ input: AIInvocationRecordInput) async {
        lock.withLock { inputs.append(input) }
    }

    func linkArtifact(invocationID: String, artifactID: String, contextSnapshotID: String) async {
        lock.withLock {
            artifactLinks.append((invocationID, artifactID, contextSnapshotID))
        }
    }
}
