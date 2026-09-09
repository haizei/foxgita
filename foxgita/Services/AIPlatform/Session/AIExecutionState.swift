enum AIExecutionState: String, Codable, Sendable {
    case created, fetching, fenced, assembling, authorizing
    case executing, validating, presenting, awaitingApproval, applying
    case completed, cancelled, failed, expired, superseded

    func canTransition(to next: Self) -> Bool {
        if [.cancelled, .failed, .expired, .superseded].contains(next) {
            return ![.completed, .cancelled, .failed, .expired, .superseded].contains(self)
        }

        return switch (self, next) {
        case (.created, .fetching), (.fetching, .fenced), (.fenced, .assembling),
             (.assembling, .authorizing), (.authorizing, .executing),
             (.executing, .validating), (.validating, .presenting),
             (.presenting, .awaitingApproval), (.presenting, .completed),
             (.awaitingApproval, .applying), (.applying, .completed): true
        default: false
        }
    }
}
