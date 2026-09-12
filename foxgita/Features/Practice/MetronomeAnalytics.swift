enum MetronomeAnalytics {
    static var sink: ((String, [String: String]) -> Void)?

    static func emit(_ event: String, itemId: String, sessionId: String = "", _ values: [String: String] = [:]) {
        sink?(event, values.merging([
            "practice_item_id": itemId,
            "session_id": sessionId,
        ]) { current, _ in current })
    }
}
