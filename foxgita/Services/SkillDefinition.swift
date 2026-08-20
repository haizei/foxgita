import Foundation

enum SkillID {
    static let planFromImage = "practice.plan.from_image"
    static let reviewMedia = "practice.review.media"
    static let diagnoseVideo = "practice.diagnose.video"
}

enum MemoryScope: String, Equatable, Sendable {
    case fact
    case goal
    case preference
    case ability
    case summary
}

enum MemoryWritePolicy: Equatable, Sendable {
    case deny
    case candidates
}

struct SkillDefinition: Equatable, Sendable {
    var id: String
    var version: String
    var title: String
    var purpose: String
    var systemPrompt: String
    var userPrompt: String?
    var timeout: TimeInterval?
    var allowsFormatRetry: Bool
    var memoryReadScopes: [MemoryScope]
    var memoryWritePolicy: MemoryWritePolicy
}

extension SkillDefinition {
    static let planFromImage = SkillDefinition(
        id: SkillID.planFromImage,
        version: "1.0.0",
        title: "图片转练习",
        purpose: "从图片生成练习任务草稿",
        systemPrompt: "你是吉他练习教练。只输出合法 JSON。",
        userPrompt: """
        请根据图片总结成吉他练习任务。只返回 JSON 对象，不要 markdown，不要其它说明。
        字段：
        - title: 字符串
        - category: 仅能为 left/right/both/chord/scale/rhythm/song 之一
        - targetMin: 整数分钟
        - steps: 字符串数组（练习步骤）
        - chords: 可选，识别到的和弦名字符串数组（如 C、G、Am）
        - stepMinutes: 可选，与 steps 按下标对齐的整数分钟；没有则省略
        """,
        timeout: nil,
        allowsFormatRetry: true,
        memoryReadScopes: [],
        memoryWritePolicy: .deny
    )

    static let reviewMedia = SkillDefinition(
        id: SkillID.reviewMedia,
        version: "1.0.0",
        title: "媒体复盘",
        purpose: "根据波形或练习画面给出三段复盘",
        systemPrompt: """
        你是吉他练习陪伴教练。根据波形图或练习画面帧给出简短复盘。只返回 JSON，不要 markdown。
        字段：highlight（亮点）、focus（优先改善）、nextAction（下次练法）。
        每段一句话，不要编造时间戳（如 01:18），不要承诺精确音准鉴定。
        """,
        userPrompt: nil,
        timeout: nil,
        allowsFormatRetry: true,
        memoryReadScopes: [],
        memoryWritePolicy: .deny
    )

    static let diagnoseVideo = SkillDefinition(
        id: SkillID.diagnoseVideo,
        version: "1.0.0",
        title: "录像分段诊断",
        purpose: "根据关键帧给出可定位的分段诊断",
        systemPrompt: """
        你是吉他练习诊断教练。根据练习录像关键帧和可选波形，给出可定位的分段诊断。只返回 JSON，不要 markdown。
        字段：highlight、focus、nextAction（各一句话），findings（数组，可空）。
        每条 finding 字段：startSec、endSec（整数秒，必须落在 0 到视频时长之间）、title、evidence、cause、action。
        evidence 写看到或听到的具体现象。证据不足就少写或不写 finding，不要编造时间点，不要承诺精确音准鉴定。最多 5 条。
        """,
        userPrompt: nil,
        timeout: 180,
        allowsFormatRetry: true,
        memoryReadScopes: [],
        memoryWritePolicy: .deny
    )
}
