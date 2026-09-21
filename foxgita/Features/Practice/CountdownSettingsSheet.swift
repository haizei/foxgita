import SwiftUI

struct CountdownSettingsSheet: View {
    let isExistingPlan: Bool
    let onApply: (Int, Bool) -> Void
    let onCloseCountdown: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var minutes: Int
    @State private var reminderEnabled: Bool

    init(
        minutes: Int,
        reminderEnabled: Bool,
        isExistingPlan: Bool,
        onApply: @escaping (Int, Bool) -> Void,
        onCloseCountdown: @escaping () -> Void
    ) {
        _minutes = State(initialValue: min(60, max(1, minutes)))
        _reminderEnabled = State(initialValue: reminderEnabled)
        self.isExistingPlan = isExistingPlan
        self.onApply = onApply
        self.onCloseCountdown = onCloseCountdown
    }

    var body: some View {
        VStack(spacing: 22) {
            Capsule()
                .fill(GitaTheme.borderSubtle)
                .frame(width: 38, height: 5)

            Text(isExistingPlan ? "调整倒计时" : "设置倒计时")
                .font(GitaFont.title(.semibold))

            HStack(spacing: 26) {
                stepButton(systemName: "minus", delta: -1)
                Text("\(minutes):00")
                    .font(GitaFont.timer())
                    .monospacedDigit()
                    .frame(minWidth: 110)
                    .accessibilityIdentifier("countdown.duration")
                stepButton(systemName: "plus", delta: 1)
            }

            HStack(spacing: 10) {
                ForEach([5, 10, 15], id: \.self) { preset in
                    Button("\(preset) 分钟") { minutes = preset }
                        .font(GitaFont.caption(.semibold))
                        .foregroundStyle(minutes == preset ? GitaTheme.brandOn : GitaTheme.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(minutes == preset ? GitaTheme.brand500 : GitaTheme.bgSubtle)
                        .clipShape(Capsule())
                }
            }

            Toggle(isOn: $reminderEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("结束提醒").font(GitaFont.callout(.semibold))
                    Text("倒计时结束时播放提示并振动")
                        .font(GitaFont.caption())
                        .foregroundStyle(GitaTheme.textSecondary)
                }
            }
            .tint(GitaTheme.brand500)
            .accessibilityIdentifier("countdown.reminder-toggle")

            Button {
                onApply(minutes, reminderEnabled)
                dismiss()
            } label: {
                Text(isExistingPlan ? "应用并返回" : "开始倒计时")
                    .font(GitaFont.callout(.semibold))
                    .foregroundStyle(GitaTheme.brandOn)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(GitaTheme.brand500)
                    .clipShape(Capsule())
            }
            .accessibilityIdentifier(isExistingPlan ? "countdown.apply" : "countdown.start")

            if isExistingPlan {
                Button("关闭倒计时") {
                    onCloseCountdown()
                    dismiss()
                }
                .font(GitaFont.callout(.semibold))
                .foregroundStyle(GitaTheme.statusError)
                .frame(minHeight: 44)
                .accessibilityIdentifier("countdown.close")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 24)
        .presentationDetents([.height(isExistingPlan ? 490 : 430)])
        .presentationDragIndicator(.hidden)
        .accessibilityIdentifier("countdown.settings-sheet")
    }

    private func stepButton(systemName: String, delta: Int) -> some View {
        Button {
            minutes = min(60, max(1, minutes + delta))
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(GitaTheme.bgSubtle)
                .clipShape(Circle())
        }
        .foregroundStyle(GitaTheme.textPrimary)
        .disabled(delta < 0 ? minutes == 1 : minutes == 60)
    }
}
