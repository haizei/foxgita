import Testing
@testable import foxgita

struct MemoryConsentCopyTests {
    @Test func frozenPrivacyLines() {
        #expect(MemoryConsentCopy.lines == [
            "记忆保存在这台设备上。",
            "若启用以获得更贴合的建议，本次只会把少量相关文字发给你在设置里配置的模型服务。",
            "不会因为开启记忆而自动上传历史录音或视频；只有当前这次功能选中的内容会参与请求。",
            "你可以随时在设置里关闭或清除记忆。",
        ])
        #expect(MemoryConsentCopy.enable == "启用并继续")
        #expect(MemoryConsentCopy.decline == "暂不启用")
        #expect(MemoryConsentCopy.title == "AI 记忆")
    }
}
