import SwiftUI

struct ProjectProgressStoryView: View {
    let story: ProjectProgressStory?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let story {
                Text(story.headline)
                    .font(GitaFont.headline())
                    .foregroundStyle(GitaTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(ProjectProgressStory.disclaimer)
                    .font(GitaFont.caption())
                    .foregroundStyle(GitaTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                timeline(story.milestones)
            } else {
                Text(ProjectProgressStory.emptyMessage)
                    .font(GitaFont.body())
                    .foregroundStyle(GitaTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(GitaTheme.categoryOrangeSoft)
                    .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
            }
        }
        .padding(story == nil ? 0 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(story == nil ? Color.clear : GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
        .shadow(color: story == nil ? .clear : GitaTheme.shadowCard, radius: 6, y: 3)
    }

    private func timeline(_ milestones: [ProjectProgressMilestone]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(milestones.enumerated()), id: \.element.id) { index, milestone in
                VStack(spacing: 8) {
                    Text(ProgressFirstFormat.monthDay(milestone.dayKey))
                        .font(GitaFont.caption())
                        .foregroundStyle(GitaTheme.textSecondary)
                        .lineLimit(1)
                    ZStack {
                        if milestones.count > 1 {
                            Rectangle()
                                .fill(GitaTheme.borderSubtle)
                                .frame(height: 2)
                                .opacity(index == milestones.count - 1 ? 0 : 1)
                                .offset(x: 18)
                        }
                        Circle()
                            .stroke(GitaTheme.brand500, lineWidth: index == milestones.count - 1 ? 0 : 2)
                            .background(Circle().fill(index == milestones.count - 1 ? GitaTheme.brand500 : GitaTheme.bgSurface))
                            .frame(width: 12, height: 12)
                    }
                    .frame(height: 12)
                    Text(milestone.label)
                        .font(GitaFont.caption())
                        .foregroundStyle(GitaTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
