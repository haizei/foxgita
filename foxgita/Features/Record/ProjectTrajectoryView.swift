import SwiftData
import SwiftUI

struct ProjectTrajectoryView: View {
    let projectId: UUID
    @Environment(AppRouter.self) private var router

    var body: some View {
        ZStack {
            PageBackground()
            VStack(spacing: 0) {
                HStack {
                    Button {
                        if !router.recordPath.isEmpty { router.recordPath.removeLast() }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(GitaTheme.iconPrimary)
                            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                    Text("项目练习轨迹")
                        .font(GitaFont.headline())
                        .foregroundStyle(GitaTheme.textPrimary)
                    Spacer(minLength: 0)
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, GitaTheme.pagePadding)
                Spacer()
            }
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
    }
}
