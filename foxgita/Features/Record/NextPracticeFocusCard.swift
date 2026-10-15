import SwiftUI

struct NextPracticeFocusCard: View {
    let decision: ProjectPracticeStateHandoff.Decision
    let showsAction: Bool
    let onHandoff: () -> Void
    let onEditFocus: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                targetBadge
                VStack(alignment: .leading, spacing: 4) {
                    Text(decision.focusTitle)
                        .font(GitaFont.body(.bold))
                        .foregroundStyle(GitaTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(decision.instruction)
                        .font(GitaFont.caption())
                        .foregroundStyle(GitaTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button(action: onEditFocus) {
                    Text("项目当前重点 · 可修改")
                        .font(GitaFont.caption())
                        .foregroundStyle(GitaTheme.brand500)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 84, alignment: .trailing)
                }
                .buttonStyle(.plain)
            }
            if showsAction {
                Button(action: onHandoff) {
                    Text(decision.buttonLabel)
                        .font(GitaFont.callout(.bold))
                        .foregroundStyle(GitaTheme.brandOn)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(GitaTheme.brand500)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
        .shadow(color: GitaTheme.shadowCard, radius: 6, y: 3)
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
