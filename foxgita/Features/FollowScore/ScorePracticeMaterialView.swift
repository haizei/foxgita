import SwiftUI

struct ScorePracticeMaterialView: View {
    let item: PracticeItem
    let refresh: UUID
    var onOpen: () -> Void
    @State private var library: ScoreLibrary?
    @State private var error: String?
    private var linkedScore: ScoreDocument? {
        guard let library,let link = library.link(for: item.id) else { return nil }
        return library.score(versionID: link.versionID)
    }
    var body: some View {
        VStack(alignment: .leading,spacing: 12) {
            Text("练习材料").font(GitaFont.headline())
            if let score = linkedScore {
                Label(score.title,systemImage: "music.note.list").font(GitaFont.callout(.bold))
                if let library,let link = library.link(for: item.id) {
                    Text("第\(link.range.firstBar+1)–\(link.range.lastBar+1)小节 · \(Int(link.speed*100))%速度").font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
                    Text("我的难点 · \(library.passages.filter { $0.versionID == score.versionID }.count)个片段").font(GitaFont.caption()).foregroundStyle(GitaTheme.brand500)
                }
            } else { Text("给练习关联曲谱，保留原有计时和笔记。").font(GitaFont.callout()).foregroundStyle(GitaTheme.textSecondary) }
            Button(linkedScore == nil ? "关联曲谱" : "打开曲谱与难点",action: onOpen).buttonStyle(ScorePrimaryStyle()).accessibilityIdentifier("practice.score-material")
            if let error { Text(error).font(GitaFont.caption()).foregroundStyle(GitaTheme.statusError) }
        }.scoreSurface()
            .task(id: refresh) {
                do { library = try ScoreLibraryProvider.library(profileID: item.profileId) }
                catch { self.error = error.localizedDescription }
            }
    }
}
