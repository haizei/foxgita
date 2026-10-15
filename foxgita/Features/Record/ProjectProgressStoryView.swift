import SwiftUI

struct ProjectProgressStoryView: View {
    let story: ProjectProgressStory
    let onOpenItem: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(story.headline)
                .font(GitaFont.headline())
                .foregroundStyle(GitaTheme.textPrimary)
            Text(ProjectProgressStory.disclaimer)
                .font(GitaFont.caption())
                .foregroundStyle(GitaTheme.textSecondary)
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(story.milestones.enumerated()), id: \.element.id) { index, milestone in
                    Button {
                        onOpenItem(milestone.id)
                    } label: {
                        VStack(spacing: 8) {
                            Text(ProgressFirstFormat.monthDay(milestone.dayKey))
                                .font(GitaFont.caption())
                                .foregroundStyle(index == story.milestones.count - 1 ? GitaTheme.brand500 : GitaTheme.textSecondary)
                            Circle()
                                .fill(index == story.milestones.count - 1 ? GitaTheme.brand500 : GitaTheme.bgSurface)
                                .overlay(Circle().stroke(index == story.milestones.count - 1 ? GitaTheme.brand500 : GitaTheme.borderSubtle, lineWidth: 2))
                                .frame(width: 14, height: 14)
                            Text(milestone.label)
                                .font(GitaFont.caption())
                                .foregroundStyle(index == story.milestones.count - 1 ? GitaTheme.brand500 : GitaTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 72, alignment: .top)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(ProgressFirstFormat.monthDay(milestone.dayKey))，\(milestone.label)，查看练习记录")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitaTheme.categoryOrangeSoft)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
    }
}
