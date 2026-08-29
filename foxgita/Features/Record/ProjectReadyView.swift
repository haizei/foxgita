import SwiftData
import SwiftUI

struct ProjectReadyView: View {
    let projectId: UUID
    @Environment(AppRouter.self) private var router

    var body: some View {
        ZStack {
            PageBackground()
            VStack(alignment: .leading, spacing: 16) {
                Button("关闭") { leave() }
                Text("项目已创建").font(GitaFont.title())
                Button("返回项目列表") { leave() }
                Spacer(minLength: 0)
            }
            .padding(GitaTheme.pagePadding)
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
    }

    private func leave() {
        if !router.recordPath.isEmpty {
            router.recordPath.removeLast()
        }
    }
}
