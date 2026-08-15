//
//  SettingsView.swift
//  foxgita
//

import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppRouter.self) private var router
    @Environment(PracticeStore.self) private var store
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    @AppStorage("gita.reminder.on") private var remindOn = false
    @AppStorage("gita.reminder.hour") private var remindHour = 20
    @AppStorage("gita.reminder.minute") private var remindMinute = 0
    @AppStorage(LLMSettingsKey.baseURL) private var llmBaseURL = ""
    @AppStorage(LLMSettingsKey.model) private var llmModel = ""
    @State private var llmBaseURLDraft = ""
    @State private var llmModelDraft = ""
    @State private var llmAPIKey = ""
    @State private var llmKeyStored = false
    @State private var showClearConfirm = false
    @State private var toast: String?
    private let llmCredentials = LLMCredentialsStore()

    var body: some View {
        ZStack {
            PageBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("设置").font(GitaFont.title())
                        Text("让练习更适合你的节奏")
                            .font(GitaFont.caption())
                            .foregroundStyle(GitaTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    sectionLabel("练习提醒")
                    group {
                        toggleRow("每日提醒", "到点轻轻提醒你摸琴", $remindOn)
                        if remindOn {
                            Divider().foregroundStyle(GitaTheme.borderSubtle)
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("提醒时间").font(.system(size: 14, weight: .semibold))
                                    Text("只鼓励，不制造压力")
                                        .font(.system(size: 12))
                                        .foregroundStyle(GitaTheme.textSecondary)
                                }
                                Spacer()
                                DatePicker(
                                    selection: reminderTime, displayedComponents: .hourAndMinute
                                ) { EmptyView() }
                                    .labelsHidden()
                            }
                            .padding(16)
                        }
                    }

                    sectionLabel("外观")
                    group {
                        VStack(alignment: .leading, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("主题外观").font(.system(size: 14, weight: .semibold))
                                Text("深色模式下卡片、文字与图标会一起切换")
                                    .font(.system(size: 12))
                                    .foregroundStyle(GitaTheme.textSecondary)
                            }
                            SegmentedPills(
                                titles: AppAppearance.allCases.map(\.label),
                                selection: appearanceIndex
                            )
                        }
                        .padding(16)
                    }

                    sectionLabel("数据")
                    group {
                        rowButton(title: "清除本地数据", subtitle: "删除全部练习记录、笔记与录音") {
                            showClearConfirm = true
                        } trailing: {
                            Text("清除").font(.system(size: 13)).foregroundStyle(GitaTheme.statusError)
                        }
                    }

                    sectionLabel("AI 接口")
                    group {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Base URL").font(.system(size: 13, weight: .semibold))
                                    Spacer()
                                    Button("粘贴") {
                                        if let pasted = UIPasteboard.general.string?
                                            .trimmingCharacters(in: .whitespacesAndNewlines),
                                            !pasted.isEmpty
                                        {
                                            llmBaseURLDraft = pasted
                                        }
                                    }
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(GitaTheme.brand500)
                                    if !llmBaseURLDraft.isEmpty {
                                        Button("清空") { llmBaseURLDraft = "" }
                                            .font(.system(size: 13))
                                            .foregroundStyle(GitaTheme.statusError)
                                    }
                                }
                                ZStack(alignment: .topLeading) {
                                    if llmBaseURLDraft.isEmpty {
                                        Text("点「粘贴」填入接口地址，灰色字不是已填内容")
                                            .font(.system(size: 13))
                                            .foregroundStyle(GitaTheme.textTertiary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 10)
                                            .allowsHitTesting(false)
                                    }
                                    TextEditor(text: $llmBaseURLDraft)
                                        .font(.system(size: 14))
                                        .scrollContentBackground(.hidden)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .frame(minHeight: 88)
                                }
                                .padding(4)
                                .background(GitaTheme.bgSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            Divider().foregroundStyle(GitaTheme.borderSubtle)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Model").font(.system(size: 13, weight: .semibold))
                                    Spacer()
                                    Button("填 qwen3.8-max") {
                                        llmModelDraft = "qwen3.8-max"
                                    }
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(GitaTheme.brand500)
                                }
                                TextField("这里要手填，灰色提示不算数", text: $llmModelDraft)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .font(.system(size: 14))
                            }
                            Divider().foregroundStyle(GitaTheme.borderSubtle)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("API Key").font(.system(size: 13, weight: .semibold))
                                    Spacer()
                                    Button("粘贴") {
                                        if let pasted = UIPasteboard.general.string?
                                            .trimmingCharacters(in: .whitespacesAndNewlines),
                                            !pasted.isEmpty
                                        {
                                            llmAPIKey = pasted
                                        }
                                    }
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(GitaTheme.brand500)
                                }
                                SecureField(
                                    llmKeyStored ? "已保存，输入新值可覆盖" : "点粘贴，再点下面保存",
                                    text: $llmAPIKey
                                )
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.system(size: 14))
                            }
                            HStack(spacing: 12) {
                                Button("保存") { saveLLMKey() }
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(GitaTheme.brand500)
                                Button("清除密钥") { clearLLMKey() }
                                    .font(.system(size: 14))
                                    .foregroundStyle(GitaTheme.statusError)
                            }
                            Text(llmStatusText)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(
                                    llmMissingFields.isEmpty ? GitaTheme.statusSuccess : GitaTheme.statusError
                                )
                            Text("图片会发送到你填写的接口地址，费用由该服务商向你收取。Gita 不托管密钥。")
                                .font(.system(size: 11))
                                .foregroundStyle(GitaTheme.textSecondary)
                        }
                        .padding(16)
                    }

                    sectionLabel("关于")
                    group {
                        infoRow("Gita", "今天只练一点点")
                        Divider().foregroundStyle(GitaTheme.borderSubtle)
                        infoRow("版本", appVersion)
                        Divider().foregroundStyle(GitaTheme.borderSubtle)
                        infoRow("数据存储", "全部保存在本设备，不会上传")
                    }

                    Text("今天只练一点点，也算向前")
                        .font(.system(size: 12))
                        .foregroundStyle(GitaTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }

            if let toast {
                VStack {
                    Spacer()
                    ToastBanner(text: toast).padding(.bottom, 40)
                }
            }
        }
        .alert("清除本地数据？", isPresented: $showClearConfirm) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                store.resetAll()
                router.selectedTab = .practice
            }
        } message: {
            Text("将删除全部练习记录、笔记与录音，且无法恢复。入门练习会恢复为初始状态。")
        }
        .onAppear {
            llmBaseURLDraft = llmBaseURL
            llmModelDraft = llmModel
            llmKeyStored = llmCredentials.loadAPIKey()?.isEmpty == false
        }
        .onChange(of: llmBaseURLDraft) { _, _ in persistLLMFields() }
        .onChange(of: llmModelDraft) { _, _ in persistLLMFields() }
        .onDisappear {
            persistLLMFields()
        }
        .onChange(of: remindOn) { _, on in
            Task { await applyReminder(enabled: on) }
        }
        .onChange(of: remindHour) { _, _ in
            Task { await applyReminder(enabled: remindOn) }
        }
        .onChange(of: remindMinute) { _, _ in
            Task { await applyReminder(enabled: remindOn) }
        }
    }

    private var llmMissingFields: [String] {
        llmCredentials.missingFieldLabels(baseURL: llmBaseURLDraft, model: llmModelDraft)
    }

    private var llmStatusText: String {
        if llmMissingFields.isEmpty {
            return String(localized: "已就绪，可去练习页使用拍摄/照片")
        }
        return String(localized: "还缺 \(llmMissingFields.joined(separator: "、"))。API Key 必须点保存。")
    }

    private func persistLLMFields() {
        llmBaseURL = llmBaseURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        llmModel = llmModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveLLMKey() {
        persistLLMFields()
        let trimmed = llmAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            guard llmKeyStored else {
                toast = String(localized: "请输入 API Key")
                hideToast()
                return
            }
            toast = String(localized: "已保存")
            hideToast()
            return
        }
        do {
            try llmCredentials.saveAPIKey(trimmed)
            llmAPIKey = ""
            llmKeyStored = true
            toast = String(localized: "已保存")
            hideToast()
        } catch {
            toast = String(localized: "保存失败")
            hideToast()
        }
    }

    private func clearLLMKey() {
        llmCredentials.clearAPIKey()
        llmAPIKey = ""
        llmKeyStored = false
        toast = String(localized: "已清除")
        hideToast()
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    private var appearanceIndex: Binding<Int> {
        Binding(
            get: { AppAppearance.allCases.firstIndex(of: appearance) ?? 0 },
            set: { appearance = AppAppearance.allCases[$0] }
        )
    }

    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: remindHour, minute: remindMinute, second: 0, of: Date()
                ) ?? Date()
            },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                remindHour = c.hour ?? 20
                remindMinute = c.minute ?? 0
            }
        )
    }

    private func applyReminder(enabled: Bool) async {
        guard enabled else {
            ReminderScheduler.cancel()
            return
        }
        guard await ReminderScheduler.requestAuthorization() else {
            remindOn = false
            toast = String(localized: "请在系统「设置 · 通知」中允许 Gita 发送提醒")
            hideToast()
            return
        }
        await ReminderScheduler.schedule(hour: remindHour, minute: remindMinute)
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(GitaTheme.textSecondary)
            .padding(.top, 4)
    }

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(GitaTheme.bgSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 14, weight: .semibold))
            Spacer()
            Text(value).font(.system(size: 13)).foregroundStyle(GitaTheme.textSecondary)
        }
        .padding(16)
    }

    private func toggleRow(_ title: String, _ sub: String, _ on: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(sub).font(.system(size: 12)).foregroundStyle(GitaTheme.textSecondary)
            }
            Spacer()
            Toggle(isOn: on) { EmptyView() }.labelsHidden().tint(GitaTheme.brand500)
        }
        .padding(16)
    }

    private func rowButton<T: View>(
        title: String,
        subtitle: String,
        action: @escaping () -> Void,
        @ViewBuilder trailing: () -> T
    ) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(GitaTheme.textPrimary)
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(GitaTheme.textSecondary)
                }
                Spacer()
                trailing()
            }
            .padding(16)
        }
        .buttonStyle(.plain)
    }

    private func hideToast() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { toast = nil }
    }
}
