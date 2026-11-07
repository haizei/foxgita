import SwiftUI

struct OriginalScoreReadingView: View {
    @Environment(\.dismiss) private var dismiss
    let draft: OriginalScoreDraft
    let library: OriginalScoreLibrary
    let entry: ScoreHubEntry
    let settings: OriginalScoreSettings
    var onReady: ((OriginalScoreDocument) -> Void)?
    @State private var document: OriginalScoreDocument?
    @State private var error: String?
    @State private var attempt = 0
    @State private var generation = UUID()

    var body: some View {
        Group {
            if let document {
                OriginalScorePlayerView(document: document, library: library, entry: entry, settings: settings)
            } else {
                VStack(spacing: 20) {
                    if let error {
                        Image(systemName: "doc.viewfinder").font(.largeTitle).foregroundStyle(GitaTheme.brand500)
                        Text("暂时没有读清谱子").font(.title2.bold())
                        Text(error).multilineTextAlignment(.center).foregroundStyle(GitaTheme.textSecondary)
                            .accessibilityIdentifier("original.read-error")
                        Button("重试读取") { attempt += 1 }.buttonStyle(.borderedProminent)
                    } else {
                        ProgressView().controlSize(.large)
                        Text("正在自动读取谱子…").font(.title2.bold())
                        Text("读取谱行、拍号和小节，完成后直接进入跟练。")
                            .multilineTextAlignment(.center).foregroundStyle(GitaTheme.textSecondary)
                    }
                    Text("原谱已保留，可稍后重试。无需手工标记谱行。")
                        .font(.caption).foregroundStyle(GitaTheme.textSecondary)
                }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(GitaTheme.bgDefault).navigationTitle("读取谱子")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { generation = UUID(); dismiss() } } }
            }
        }
        .interactiveDismissDisabled(document == nil && error == nil)
        .onDisappear { generation = UUID() }
        .task(id: attempt) {
            let token = generation
            guard document == nil else { return }
            error = nil
            do {
                let pages = try OriginalScoreSources.pages(for: draft.document, profileID: library.profileID)
                let result = try await OriginalScoreReader.read(pages: pages, document: draft.document)
                try Task.checkCancellation()
                guard generation == token else { return }
                var ready = draft
                ready.document = result; ready.updatedAt = Date()
                try library.save(draft: ready)
                let published = try library.publish(draftID: ready.id, availablePages: pages.count)
                if let onReady { onReady(published) } else { document = published }
            } catch is CancellationError { }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}
