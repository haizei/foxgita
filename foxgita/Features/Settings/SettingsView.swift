//
//  SettingsView.swift
//  foxgita
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppRouter.self) private var router
    @Environment(PracticeStore.self) private var store
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    @AppStorage("gita.reminder.on") private var remindOn = false
    @AppStorage("gita.reminder.hour") private var remindHour = 20
    @AppStorage("gita.reminder.minute") private var remindMinute = 0
    @State private var showClearConfirm = false
    @State private var toast: String?

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
