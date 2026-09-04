import Foundation

struct AIInvocationLogRowModel: Equatable {
    var skillTitle: String
    var statusText: String
    var errorText: String?
    var outcomeText: String
    var completedText: String
    var durationText: String
    var modelText: String
}

enum AIInvocationLogPresentation {
    static func row(_ log: AIInvocationLog) -> AIInvocationLogRowModel {
        AIInvocationLogRowModel(
            skillTitle: skillTitle(log.skillId),
            statusText: statusText(log.statusRaw),
            errorText: log.errorTypeRaw.isEmpty ? nil : log.errorTypeRaw,
            outcomeText: outcomeText(log.draftOutcomeRaw),
            completedText: log.completedAt == nil ? "未完成" : "已完成",
            durationText: "\(log.durationMs) 毫秒",
            modelText: log.model
        )
    }

    private static func skillTitle(_ skillId: String) -> String {
        switch skillId {
        case SkillID.planFromImage: return "图片转练习"
        case SkillID.reviewMedia: return "媒体复盘"
        case SkillID.diagnoseVideo: return "录像分段诊断"
        case SkillID.nextSession: return "下次练习安排"
        default: return "其他调用"
        }
    }

    private static func statusText(_ raw: String) -> String {
        switch raw {
        case "success": return "成功"
        case "failure": return "失败"
        default: return raw
        }
    }

    private static func outcomeText(_ raw: String) -> String {
        switch raw {
        case "accepted": return "已接受"
        case "edited": return "已编辑"
        case "regenerated": return "已重生成"
        case "abandoned": return "已放弃"
        default: return "仅调用"
        }
    }
}
