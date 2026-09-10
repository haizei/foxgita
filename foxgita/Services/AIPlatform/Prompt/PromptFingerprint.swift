import CryptoKit
import Foundation

enum PromptFingerprint {
    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func frame(_ values: [String]) -> String {
        values.map { "\($0.utf8.count):\($0)" }.joined(separator: "\u{001E}")
    }

    static func canonicalJSON(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let canonicalData = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed]),
              let canonical = String(data: canonicalData, encoding: .utf8) else {
            return json
        }
        return canonical
    }
}
