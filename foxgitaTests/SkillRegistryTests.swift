import Foundation
import Testing
@testable import foxgita

struct SkillRegistryTests {
    @Test func builtinContainsFrozenSkillsWithDenyMemory() {
        let plan = SkillRegistry.builtin.skill(id: SkillID.planFromImage)
        let review = SkillRegistry.builtin.skill(id: SkillID.reviewMedia)
        let video = SkillRegistry.builtin.skill(id: SkillID.diagnoseVideo)
        #expect(plan != nil)
        #expect(review != nil)
        #expect(video != nil)
        #expect(plan?.version == "1.1.0")
        #expect(review?.version == "1.1.0")
        #expect(video?.version == "1.1.0")
        #expect(plan?.memoryReadScopes == [.goal, .preference])
        #expect(review?.memoryReadScopes == [.goal, .preference, .ability])
        #expect(video?.memoryReadScopes == [.goal, .preference, .ability])
        #expect(plan?.memoryWritePolicy == .deny)
        #expect(review?.memoryWritePolicy == .deny)
        #expect(video?.memoryWritePolicy == .deny)
        #expect(plan?.userPrompt != nil)
        #expect(review?.userPrompt == nil)
        #expect(video?.userPrompt == nil)
        #expect(plan?.timeout == nil)
        #expect(review?.timeout == nil)
        #expect(video?.timeout == 180)
        #expect(plan?.allowsFormatRetry == true)
        #expect(plan?.systemPrompt == "你是吉他练习教练。只输出合法 JSON。")
        #expect(plan?.userPrompt == """
        请根据图片总结成吉他练习任务。只返回 JSON 对象，不要 markdown，不要其它说明。
        字段：
        - title: 字符串
        - category: 仅能为 left/right/both/chord/scale/rhythm/song 之一
        - targetMin: 整数分钟
        - steps: 字符串数组（练习步骤）
        - chords: 可选，识别到的和弦名字符串数组（如 C、G、Am）
        - stepMinutes: 可选，与 steps 按下标对齐的整数分钟；没有则省略
        """)
        #expect(review?.systemPrompt == """
        你是吉他练习陪伴教练。根据波形图或练习画面帧给出简短复盘。只返回 JSON，不要 markdown。
        字段：highlight（亮点）、focus（优先改善）、nextAction（下次练法）。
        每段一句话，不要编造时间戳（如 01:18），不要承诺精确音准鉴定。
        """)
        #expect(video?.systemPrompt == """
        你是吉他练习诊断教练。根据练习录像关键帧和可选波形，给出可定位的分段诊断。只返回 JSON，不要 markdown。
        字段：highlight、focus、nextAction（各一句话），findings（数组，可空）。
        每条 finding 字段：startSec、endSec（整数秒，必须落在 0 到视频时长之间）、title、evidence、cause、action。
        evidence 写看到或听到的具体现象。证据不足就少写或不写 finding，不要编造时间点，不要承诺精确音准鉴定。最多 5 条。
        """)
    }

    @Test func missingIdReturnsNil() {
        #expect(SkillRegistry.builtin.skill(id: "no.such.skill") == nil)
        let empty = SkillRegistry(skills: [])
        #expect(empty.skill(id: SkillID.planFromImage) == nil)
    }
}
