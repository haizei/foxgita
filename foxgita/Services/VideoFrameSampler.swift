import Foundation

enum VideoFrameSampler {
    static func sampleSeconds(duration: Double, interval: Double = 8, maxCount: Int = 10) -> [Double] {
        guard duration > 0, duration.isFinite else { return [0] }
        var set: Set<Int> = [0]
        set.insert(Int((duration * 0.5).rounded()))
        set.insert(Int((duration * 0.98).rounded(.down)))
        var t = interval
        while t < duration, set.count < maxCount {
            set.insert(Int(t.rounded()))
            t += interval
        }
        var seconds = set.map { min(Double($0), duration) }.sorted()
        if seconds.count > maxCount {
            seconds = Array(seconds.prefix(maxCount - 1)) + [seconds.last!]
        }
        return seconds
    }
}
