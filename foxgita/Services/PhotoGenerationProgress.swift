import Foundation

enum PhotoGenerationProgress {
    static let captions = [
        "已识别和弦与节奏",
        "正在拆分练习步骤",
        "即将估算练习时长",
    ]
    static let stageSeconds: TimeInterval = 2.5
    static let fillDuration: TimeInterval = 12

    static func activeIndex(elapsed: TimeInterval, completed: Bool) -> Int {
        if completed { return captions.count - 1 }
        let index = Int(elapsed / stageSeconds)
        return min(captions.count - 1, max(0, index))
    }

    static func fraction(elapsed: TimeInterval, completed: Bool) -> Double {
        if completed { return 1 }
        return min(0.9, max(0, elapsed / fillDuration))
    }
}
