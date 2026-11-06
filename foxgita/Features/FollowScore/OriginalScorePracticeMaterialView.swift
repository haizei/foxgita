import SwiftUI

/// Projects original-score associations through the same practice-material entry.
/// The record retains its immutable version even after a material is hidden.
struct OriginalScorePracticeMaterialView: View {
    let item: PracticeItem
    let refresh: UUID
    var onOpen: () -> Void
    @State private var library: OriginalScoreLibrary?
    @State private var error: String?

    private var record: OriginalScorePracticeRecord? {
        library?.records.first { $0.practiceItemID == item.id }
    }
    var body: some View {
        Group {
            if let library, let record, let document = library.version(record.versionID) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("练习材料").font(GitaFont.headline())
                    Label(document.title, systemImage: "doc.richtext").font(GitaFont.callout(.bold))
                    if let range = try? document.indices(for: record.range) {
                        Text("原谱跟弹 · 第\(range.lowerBound + 1)–\(range.upperBound + 1)行 · \(Int(record.bpm)) BPM")
                            .font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
                    }
                    NavigationLink {
                        OriginalScoreHistoryView(document: document, record: record, profileID: library.profileID)
                    } label: { Text("查看本次练习的谱面").font(GitaFont.callout()) }
                    Button("打开原谱跟弹", action: onOpen).buttonStyle(ScorePrimaryStyle())
                        .accessibilityIdentifier("practice.score-material")
                }.scoreSurface()
            } else { ScorePracticeMaterialView(item: item, refresh: refresh, onOpen: onOpen) }
            if let error { Text(error).font(.caption).foregroundStyle(GitaTheme.statusError) }
        }
        .task(id: refresh) {
            do { library = try OriginalScoreLibraryProvider.library(profileID: item.profileId) }
            catch { self.error = error.localizedDescription }
        }
    }
}
