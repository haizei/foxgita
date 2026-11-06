import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

nonisolated enum ScorePlayAlongMethod: String, CaseIterable, Identifiable {
    case structured = "曲谱跟练"
    case original = "原谱跟弹"
    var id: String { rawValue }
}

struct ScorePracticeLibraryView: View {
    let entry: ScoreHubEntry
    var settings = OriginalScoreSettings()
    var automaticallyImport = false
    @State var method: ScorePlayAlongMethod = .structured

    var body: some View {
        VStack(spacing: 0) {
            Picker("跟弹方式", selection: $method) {
                ForEach(ScorePlayAlongMethod.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).padding(.horizontal, 20).padding(.vertical, 10)
            .accessibilityIdentifier("score.method")
            if method == .structured { ScoreHubView(entry: entry) }
            else { OriginalScoreLibraryView(entry: entry, settings: settings, automaticallyImport: automaticallyImport) }
        }
        .background(GitaTheme.bgDefault)
    }
}

struct OriginalScoreLibraryView: View {
    @Environment(PracticeStore.self) private var store
    let entry: ScoreHubEntry
    let settings: OriginalScoreSettings
    var automaticallyImport = false
    @State private var library: OriginalScoreLibrary?
    @State private var error: String?
    @State private var files = false
    @State private var album = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var loading = false
    @State private var draft: OriginalScoreDraft?
    @State private var search = ""
    @State private var generation = UUID()
    @State private var uploadPrompt = false
    @State private var didPrompt = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("我的曲谱").font(GitaFont.largeTitle())
                Text("上传自己的谱子，标记谱行，跟着线弹奏。")
                    .font(GitaFont.callout()).foregroundStyle(GitaTheme.textSecondary)
                Menu {
                    Button("导入 PDF 或图片") { selectFiles() }
                    Button("从相册选择") { album = true }
                } label: {
                    Label("上传谱子", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity).padding(14)
                        .foregroundStyle(.white).background(GitaTheme.brand500, in: RoundedRectangle(cornerRadius: 12))
                }.accessibilityIdentifier("original.upload").disabled(loading)
                Text("最多 20 页、30 MB · 无需识谱").font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
                if loading { ProgressView("正在读取谱页…") }
                if let error { Text(error).foregroundStyle(GitaTheme.statusError).accessibilityIdentifier("original.error") }
                TextField("搜索曲名", text: $search).textFieldStyle(.roundedBorder)
                if let library {
                    if !library.drafts.isEmpty {
                        Text("标记草稿").font(GitaFont.callout(.bold))
                        ForEach(library.drafts) { item in
                            HStack {
                                Button { draft = item } label: { Label(item.document.title, systemImage: "pencil.and.outline") }
                                Spacer()
                                Button("删除", role: .destructive) { attempt { try library.discardDraft(item.id) } }
                            }
                        }
                    }
                    Text("原谱跟弹").font(GitaFont.callout(.bold))
                    ForEach(library.documents.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }) { document in
                        NavigationLink {
                            OriginalScorePlayerView(document: document, library: library, entry: entry, settings: settings)
                        } label: {
                            HStack {
                                Image(systemName: "doc.richtext").foregroundStyle(GitaTheme.brand500)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(document.title).font(GitaFont.callout(.bold))
                                    Text("\(document.pageCount) 页 · \(document.rows.count) 行 · \(document.numerator)/\(document.denominator)")
                                        .font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
                                }
                                Spacer(); Image(systemName: "chevron.right")
                            }.padding(14).background(GitaTheme.bgSurface, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).accessibilityIdentifier("original.material.\(document.id.uuidString)")
                        .contextMenu {
                            Button("修订标记") { attempt { draft = try library.beginRevision(document) } }
                            Button("从我的曲谱删除", role: .destructive) { attempt { try library.hide(document.id) } }
                        }
                    }
                    if !library.records.isEmpty {
                        Text("原谱练习记录").font(GitaFont.callout(.bold))
                        ForEach(library.records) { record in
                            if let document = library.version(record.versionID) {
                                NavigationLink {
                                    OriginalScoreHistoryView(document: document, record: record, profileID: library.profileID)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(document.title)
                                        Text("\(record.date.formatted(date: .abbreviated, time: .shortened)) · \(Int(record.seconds)) 秒 · \(Int(record.bpm)) BPM")
                                            .font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
                                    }
                                }.accessibilityIdentifier("original.history.\(record.id.uuidString)")
                            }
                        }
                    }
                }
            }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task {
            attempt { library = try OriginalScoreLibraryProvider.library(profileID: store.scoreProfileID()) }
            if automaticallyImport, !didPrompt, library != nil { didPrompt = true; uploadPrompt = true }
        }
        .confirmationDialog("上传谱子", isPresented: $uploadPrompt) {
            Button("导入 PDF 或图片") { selectFiles() }
            Button("从相册选择") { album = true }
        }
        .fileImporter(isPresented: $files, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else {
                if case .failure(let problem) = result, (problem as NSError).code != NSUserCancelledError { error = problem.localizedDescription }
                return
            }
            let token = generation; loading = true
            Task { @MainActor in
                do {
                    let selection = try await ScoreImportSelection.files(urls)
                    guard generation == token, !Task.isCancelled else { return }
                    try importPages(selection)
                } catch { if generation == token { self.error = error.localizedDescription } }
                if generation == token { loading = false }
            }
        }
        .photosPicker(isPresented: $album, selection: $photos, maxSelectionCount: 20,
                      selectionBehavior: .ordered, matching: .images, preferredItemEncoding: .compatible)
        .onChange(of: album) { _, visible in if !visible { loadPhotos() } }
        .onChange(of: photos) { _, _ in if !album { loadPhotos() } }
        .sheet(item: $draft) { item in
            if let library {
                NavigationStack {
                    OriginalScoreMarkingView(draft: item, library: library, entry: entry, settings: settings)
                }.interactiveDismissDisabled()
            }
        }
        .onDisappear { generation = UUID(); loading = false }
        .accessibilityIdentifier("original.library")
    }

    private func attempt(_ operation: () throws -> Void) {
        do { try operation(); error = nil } catch { self.error = error.localizedDescription }
    }
    private func importPages(_ selection: ScoreImportSelection) throws {
        guard let library else { throw OriginalScoreError.missingVersion }
        try OriginalScoreSources.save(selection, profileID: library.profileID)
        let title = String(((selection.names.first ?? "未命名曲谱") as NSString).deletingPathExtension.prefix(120))
        var document = OriginalScoreDocument(title: title.isEmpty ? "未命名曲谱" : title, pageCount: selection.pages.count,
            numerator: settings.numerator, denominator: settings.denominator, initialBPM: settings.bpm)
        document.sourceID = selection.id
        let next = OriginalScoreDraft(document: document)
        try library.save(draft: next); draft = next
    }
    private func loadPhotos() {
        guard !photos.isEmpty, !loading else { return }
        let selected = photos; photos = []; loading = true
        let token = generation
        Task { @MainActor in
            do {
                var data: [Data] = []
                var totalBytes = 0
                for item in selected {
                    guard let image = try await item.loadTransferable(type: Data.self) else { throw OriginalScoreError.invalidDocument }
                    guard image.count <= 30_000_000 - totalBytes else { throw ScoreRecognitionError.invalidFile }
                    totalBytes += image.count
                    data.append(image)
                }
                guard token == generation, !Task.isCancelled else { return }
                try importPages(ScoreImportSelection.images(data))
            } catch { if token == generation { self.error = error.localizedDescription } }
            if token == generation { loading = false }
        }
    }
    private func selectFiles() {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-OriginalScoreFixture") {
            attempt { try importPages(ScoreImportSelection.images([OriginalScoreUITestPage.data])) }
            return
        }
        #endif
        files = true
    }
}
