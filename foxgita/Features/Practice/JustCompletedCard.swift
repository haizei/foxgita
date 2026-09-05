import SwiftUI

struct JustCompletedCard: View {
    var title: String
    var minutes: String
    var summary: String
    var onPracticeAgain: () -> Void
    var onViewRecord: () -> Void
    var onCreateProject: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "刚刚完成"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(GitaTheme.brand500)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            Text(summary.isEmpty ? minutes : "\(minutes) · \(summary)")
                .font(.system(size: 13))
                .foregroundStyle(GitaTheme.textSecondary)
            HStack(spacing: 10) {
                Button(String(localized: "再练一次"), action: onPracticeAgain)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GitaTheme.brandOn)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 40)
                    .background(GitaTheme.brand500)
                    .clipShape(Capsule())
                Button(String(localized: "查看记录"), action: onViewRecord)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GitaTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 40)
                    .background(GitaTheme.bgSubtle)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            if let onCreateProject {
                Button("建立长期项目", action: onCreateProject)
                    .font(.system(size: 14))
                    .foregroundStyle(GitaTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: GitaTheme.shadowCard, radius: 8, y: 4)
    }
}
