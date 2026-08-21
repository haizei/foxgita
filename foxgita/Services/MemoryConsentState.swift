import Foundation

enum MemoryConsentState: String, Equatable, Sendable {
    case undecided
    case enabled
    case disabled
}

enum ConsentGateResult: Equatable, Sendable {
    case proceed
    case aborted
}

enum MemoryConsentCopy {
    static let lines: [String] = [
        "记忆保存在这台设备上。",
        "若启用以获得更贴合的建议，本次只会把少量相关文字发给你在设置里配置的模型服务。",
        "不会因为开启记忆而自动上传历史录音或视频；只有当前这次功能选中的内容会参与请求。",
        "你可以随时在设置里关闭或清除记忆。",
    ]
    static let enable = "启用并继续"
    static let decline = "暂不启用"
    static let title = "AI 记忆"
}
