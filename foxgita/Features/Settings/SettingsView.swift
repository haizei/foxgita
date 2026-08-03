//
//  SettingsView.swift
//  foxgita
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppRouter.self) private var router
    @State private var remindOn = false
    @State private var hapticOn = true
    @State private var toast: String?

    var body: some View {
        @Bindable var router = router
        ZStack {
            PageBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("设置").font(.system(size: 20, weight: .bold))
                            Text("让练习更适合你的节奏")
                                .font(.system(size: 12))
                                .foregroundStyle(GitaTheme.textSecondary)
                        }
                        Spacer()
                        Text("关于")
                            .font(.system(size: 14))
                            .foregroundStyle(GitaTheme.textSecondary)
                    }

                    HStack(spacing: 12) {
                        ZStack(alignment: .bottomTrailing) {
                            Text(String(router.displayName.prefix(1)))
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(GitaTheme.iconActive)
                                .frame(width: 52, height: 52)
                                .background(GitaTheme.brand50)
                                .clipShape(Circle())
                            if router.role == .vip {
                                Text("高光")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(GitaTheme.brand500)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(GitaTheme.brand50)
                                    .clipShape(Capsule())
                                    .offset(x: 4, y: 2)
                            }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(router.displayName).font(.system(size: 16, weight: .bold))
                            Text(roleDesc)
                                .font(.system(size: 12))
                                .foregroundStyle(GitaTheme.textSecondary)
                        }
                        Spacer()
                        Text("编辑")
                            .font(.system(size: 12))
                            .foregroundStyle(GitaTheme.textSecondary)
                    }
                    .padding(16)
                    .background(GitaTheme.bgSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    sectionLabel("账号与同步")
                    group {
                        rowButton(title: "云同步", subtitle: cloudDesc) {
                            if router.role == .vip {
                                toast = "云同步已开启（演示）"
                            } else {
                                toast = "登录后即可云同步练习记录"
                            }
                            hideToast()
                        } trailing: {
                            Text(router.role == .vip ? "已开启" : "未开启")
                                .font(.system(size: 13))
                                .foregroundStyle(GitaTheme.textSecondary)
                        }
                    }

                    sectionLabel("练习偏好")
                    group {
                        toggleRow("每日提醒", "20:00 · 温柔提醒", $remindOn)
                        Divider().foregroundStyle(GitaTheme.borderSubtle)
                        valueRow("默认练习时长", "新任务默认 10 分钟", "10 分钟")
                        Divider().foregroundStyle(GitaTheme.borderSubtle)
                        valueRow("节拍器声音", "木质短音", "进入")
                    }

                    sectionLabel("外观与反馈")
                    group {
                        rowButton(title: "主题外观", subtitle: router.isDark ? "深色" : "浅色") {
                            router.isDark.toggle()
                        } trailing: {
                            Text("切换").font(.system(size: 13)).foregroundStyle(GitaTheme.textSecondary)
                        }
                        Divider().foregroundStyle(GitaTheme.borderSubtle)
                        toggleRow("触感反馈", "节拍与完成反馈", $hapticOn)
                        Divider().foregroundStyle(GitaTheme.borderSubtle)
                        valueRow("连续日提醒", "只鼓励，不制造压力", "已开启")
                    }

                    sectionLabel("成长角色（演示）")
                    group {
                        ForEach(UserRole.allCases, id: \.self) { role in
                            Button {
                                router.role = role
                            } label: {
                                HStack {
                                    Text(role.label)
                                        .foregroundStyle(GitaTheme.textPrimary)
                                    Spacer()
                                    if router.role == role {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(GitaTheme.brand500)
                                    }
                                }
                                .padding(16)
                            }
                            .buttonStyle(.plain)
                            if role != .vip { Divider().foregroundStyle(GitaTheme.borderSubtle) }
                        }
                    }

                    sectionLabel("数据与应用")
                    group {
                        valueRow("导出练习数据", "生成本地文件", "进入")
                        Divider().foregroundStyle(GitaTheme.borderSubtle)
                        valueRow("清除本地数据", "需再次确认", "进入")
                        Divider().foregroundStyle(GitaTheme.borderSubtle)
                        valueRow("关于吉他训记", "版本 1.0.0 · Hi-Fi", "进入")
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
        .preferredColorScheme(router.isDark ? .dark : .light)
    }

    private var roleDesc: String {
        switch router.role {
        case .guest: return "游客 · 示例可练，数据仅本地"
        case .novice: return "本地练习者 · 数据仅保存在设备"
        case .vip: return "坚持高光 · 云同步与分享已解锁"
        }
    }

    private var cloudDesc: String {
        router.role == .vip ? "跨设备同步练习记录" : "登录后跨设备同步练习记录"
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

    private func valueRow(_ title: String, _ sub: String, _ val: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(sub).font(.system(size: 12)).foregroundStyle(GitaTheme.textSecondary)
            }
            Spacer()
            Text(val).font(.system(size: 13)).foregroundStyle(GitaTheme.textSecondary)
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
            Toggle("", isOn: on).labelsHidden().tint(GitaTheme.brand500)
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
