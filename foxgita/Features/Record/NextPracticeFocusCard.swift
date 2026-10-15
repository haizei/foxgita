import SwiftUI

struct NextPracticeFocusCard: View {
    let decision: ProjectPracticeStateHandoff.Decision
    let onHandoff: () -> Void
    let onEditFocus: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("下次练什么")
                    .font(GitaFont.headline())
                    .foregroundStyle(GitaTheme.textPrimary)
                Spacer(minLength: 8)
                Button("项目当前重点 · 可修改", action: onEditFocus)
                    .font(GitaFont.caption())
                    .foregroundStyle(GitaTheme.textSecondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    focusContent
                    Spacer(minLength: 0)
                    startButton
                }
                VStack(alignment: .leading, spacing: 12) {
                    focusContent
                    startButton
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GitaTheme.categoryOrangeSoft)
            .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius12))
        }
    }

    private var focusContent: some View {
        HStack(alignment: .center, spacing: 10) {
            targetBadge
            VStack(alignment: .leading, spacing: 4) {
                Text(decision.focusTitle)
                    .font(GitaFont.body(.semibold))
                    .foregroundStyle(GitaTheme.textPrimary)
                Text(decision.instruction)
                    .font(GitaFont.caption())
                    .foregroundStyle(GitaTheme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var startButton: some View {
        Button(action: onHandoff) {
            Text(decision.buttonLabel)
                .font(GitaFont.callout(.semibold))
                .foregroundStyle(GitaTheme.brandOn)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(GitaTheme.brand500)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var targetBadge: some View {
        ZStack {
            Circle()
                .stroke(GitaTheme.brand500.opacity(0.28), lineWidth: 2)
                .frame(width: 36, height: 36)
            Circle()
                .stroke(GitaTheme.brand500, lineWidth: 2)
                .frame(width: 22, height: 22)
            Circle()
                .fill(GitaTheme.brand500)
                .frame(width: 8, height: 8)
        }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
    }
}
