import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

enum ScoreHubEntry { case tool, newPractice, existing(UUID) }

struct ScoreHubView: View {
    @Environment(PracticeStore.self) private var store
    let entry: ScoreHubEntry
    @State private var library: ScoreLibrary?
    @State private var error: String?
    @State private var search = ""
    @State private var fileImport = false
    @State private var photoPickerPresented = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var camera = false
    @State private var loading = false
    @State private var importSelection: ScoreImportSelection?
    @State private var pendingImports: [ScoreSourceVault.Pending] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading,spacing: 20) {
                HStack { Text("我的曲谱").font(GitaFont.largeTitle()); Spacer(); importMenu }
                TextField("搜索曲名",text: $search).padding(12).background(GitaTheme.bgSubtle,in: RoundedRectangle(cornerRadius: 12))
                if loading { ProgressView("正在读取谱页…").frame(maxWidth: .infinity) }
                if let error { Text(error).foregroundStyle(GitaTheme.statusError).font(GitaFont.callout()) }
                if let library {
                    if !pendingImports.isEmpty {
                        Text("待识谱／待校正原件").font(GitaFont.callout(.bold))
                        ForEach(pendingImports) { pending in
                            Button { do { importSelection = try ScoreSourceVault.restore(profileID: library.profileID,sourceID: pending.id) } catch { self.error = error.localizedDescription } } label: {
                                Label("\(pending.title) · \(pending.pageCount)页",systemImage: "doc.text.magnifyingglass").font(GitaFont.callout())
                            }.accessibilityIdentifier("score.pending.\(pending.id.uuidString)")
                        }
                    }
                    Text("最近使用").font(GitaFont.callout(.bold))
                    ForEach(library.scores.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }) { score in
                        NavigationLink { ScoreDetailView(score: score,library: library,entry: entry) } label: { ScoreRowContent(score: score) }
                            .buttonStyle(.plain).accessibilityIdentifier("score.library.\(score.id.uuidString)")
                    }
                    if !library.results.isEmpty {
                        NavigationLink { ScoreResultsView(library: library) } label: { Label("跟谱练习记录",systemImage: "clock.arrow.circlepath").font(GitaFont.callout(.bold)) }.padding(.vertical,8)
                    }
                }
                Text("内置原创练习可直接跟练。PDF和图片需要识谱、校正并确认后使用。").font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
            }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }.background(GitaTheme.bgDefault).navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible,for: .navigationBar)
            .task {
                do {
                    library = try ScoreLibraryProvider.library(profileID: store.scoreProfileID())
                    loadPending()
                    #if DEBUG && targetEnvironment(simulator)
                    if ProcessInfo.processInfo.arguments.contains("-UITesting"),
                       ProcessInfo.processInfo.arguments.contains("-ScoreReviewFixture"), let library {
                        importSelection = try ScoreReviewUITestFixture.prepare(library: library)
                    }
                    #endif
                } catch { self.error = error.localizedDescription }
            }
            .fileImporter(isPresented: $fileImport,allowedContentTypes: [.pdf,.image],allowsMultipleSelection: true) { result in
                do { let urls = try result.get(); read(urls: urls) } catch { self.error = error.localizedDescription }
            }
            .photosPicker(isPresented: $photoPickerPresented,selection: $photos,
                          maxSelectionCount: 20,selectionBehavior: .ordered,
                          matching: .images,preferredItemEncoding: .compatible)
            .onChange(of: photos) { _, _ in
                readPhotosIfDismissed()
            }
            .onChange(of: photoPickerPresented) { _, presented in
                if !presented { readPhotosIfDismissed() }
            }
            .sheet(isPresented: $camera) {
                StillImageCameraPicker(isPresented: $camera,onPicked: { data in
                    do { importSelection = try ScoreImportSelection.images([data]) } catch { self.error = error.localizedDescription }
                },onCancel: {})
            }
            .sheet(item: $importSelection,onDismiss: { loadPending() }) { selection in
                if let library { NavigationStack { ScoreImportView(selection: selection,library: library) } }
            }
            .accessibilityIdentifier("score.library")
    }
    private var importMenu: some View {
        Menu {
            Button("导入 PDF 或图片",systemImage: "doc") {
                #if DEBUG && targetEnvironment(simulator)
                // XCUITest supplies a simulator-readable page in place of a Files picker selection.
                let process = ProcessInfo.processInfo
                if process.arguments.contains("-ScoreRecoveryFixture"),
                   process.arguments.contains("-UITesting"),
                   let raw=process.environment["GITA_RECOVERY_PAGE_PATHS"],
                   let bytes=raw.data(using:.utf8),
                   let paths=try? JSONDecoder().decode([String].self,from:bytes),
                   !paths.isEmpty,paths.count<=20 {
                    read(urls:paths.map {URL(fileURLWithPath:$0)})
                    return
                }
                if process.arguments.contains("-ScoreRecoveryFixture"),
                   process.arguments.contains("-UITesting"),
                   let path = process.environment["GITA_RECOVERY_PAGE_PATH"] {
                    read(urls: [URL(fileURLWithPath: path)])
                    return
                }
                #endif
                fileImport = true
            }
            Button("从相册选择",systemImage: "photo") {
                error = nil
                photoPickerPresented = true
            }.accessibilityIdentifier("score.import.photos")
            Button("拍摄谱页",systemImage: "camera") { camera = true }
        } label: { Label("导入",systemImage: "plus").font(GitaFont.callout(.bold)).foregroundStyle(GitaTheme.brand500) }
        .disabled(loading || library == nil).accessibilityIdentifier("score.import")
    }
    private func readPhotosIfDismissed() {
        // The picker and import preview share a presenter; wait for the picker to close.
        guard !photoPickerPresented, !photos.isEmpty, !loading else { return }
        let selection = photos
        loading = true
        error = nil
        Task { @MainActor in
            defer { photos = []; loading = false }
            do {
                var data: [Data] = []
                var totalBytes = 0
                for (index, photo) in selection.enumerated() {
                    guard let bytes = try await photo.loadTransferable(type: Data.self) else {
                        throw ScoreRecognitionError.invalidFile
                    }
                    totalBytes += bytes.count
                    guard totalBytes <= 30_000_000 else {
                        error = "所选照片总大小超过30 MB，请减少谱页后重试。"
                        return
                    }
                    data.append(bytes)
                    // Yield between pages so loading feedback remains responsive.
                    if index < selection.count - 1 { await Task.yield() }
                }
                importSelection = try ScoreImportSelection.images(data)
            } catch {
                self.error = "无法读取所选照片，请重新选择。\(error.localizedDescription)"
            }
        }
    }
    private func read(urls: [URL]) {
        loading = true
        Task {
            do { importSelection = try await ScoreImportSelection.files(urls) } catch { self.error = error.localizedDescription }
            loading = false
        }
    }
    private func loadPending() {
        guard let library else { return }
        do { pendingImports = try ScoreSourceVault.pending(profileID: library.profileID,library: library) }
        catch { self.error = error.localizedDescription }
    }
}

private struct ScoreRowContent: View {
    let score: ScoreDocument
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform").font(.title3).foregroundStyle(GitaTheme.brand500).frame(width: 44,height: 44).background(GitaTheme.brand50,in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading,spacing: 4) { Text(score.title).font(GitaFont.callout(.bold)).foregroundStyle(GitaTheme.textPrimary); Text("\(score.composer) · \(score.bars.count)小节").font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary) }
            Spacer(); Image(systemName: "chevron.right").foregroundStyle(GitaTheme.iconSecondary).font(.caption)
        }.padding(16).background(GitaTheme.bgSurface,in: RoundedRectangle(cornerRadius: 20))
    }
}

struct ScoreDetailView: View {
    @Environment(PracticeStore.self) private var store
    @Environment(AppRouter.self) private var router
    let score: ScoreDocument
    let library: ScoreLibrary
    let entry: ScoreHubEntry
    @State private var range: ScoreRange
    @State private var speed = 0.75
    @State private var mode = ScoreRunMode.practice
    @State private var notation = ScoreNotation.tablature
    @State private var loops = 5
    @State private var playerSession: ScorePlayerSession?
    @State private var lastStartedSession: ScorePlayerSession?
    @State private var chooseItem = false
    @State private var pendingStart: ScoreItemChoice?
    @State private var todayItems: [PracticeItemSnapshot] = []
    @State private var selectedPassage: ScorePassage?
    @State private var resumeTick: Int?
    @State private var error: String?
    @State private var launchError: String?
    @State private var showMastered = false
    @State private var editing: ScorePassage?
    @State private var launchToken = UUID()
    @State private var createdItemID: UUID?
    @State private var showSavedResult = false
    @State private var revision: ScoreImportSelection?
    @State private var revisionDraft: RecognizedScoreDraft?
    @State private var materialSaved = false

    init(score: ScoreDocument,library: ScoreLibrary,entry: ScoreHubEntry) {
        self.score = score; self.library = library; self.entry = entry
        _range = State(initialValue: score.fullRange)
    }
    private var passages: [ScorePassage] { library.passages.filter { $0.versionID == score.versionID && (showMastered || $0.status != .mastered) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading,spacing: 20) {
                ScoreRowContent(score: score)
                if case .existing(let itemID) = entry {
                    Button(materialSaved ? "已关联到练习" : "关联到这个练习") {
                        do {
                            _ = try store.editableScorePracticeItem(id: itemID,completedIDs: router.completedPracticeItemIds,now: Date())
                            try library.save(link: .init(practiceItemID: itemID,versionID: score.versionID,range: range,speed: mode == .performance ? 1 : speed))
                            materialSaved = true
                        } catch { self.error = error.localizedDescription }
                    }.font(GitaFont.callout(.bold)).accessibilityIdentifier("score.associate")
                }
                if let resume = library.resume(for: score.versionID) {
                    HStack {
                        VStack(alignment: .leading,spacing: 4) { Text("上次进度 · 第\(score.barIndex(atTick: resume.tick)+1)小节").font(GitaFont.callout(.bold)); Text("继续上次停下的位置").font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary) }
                        Spacer(); Button("继续") { range = resume.range; speed = resume.speed; notation = resume.notation; resumeTick = resume.tick; selectedPassage = nil; launch() }
                    }.scoreSurface()
                }
                prepare
                ScoreCanvasView(score: score,tick: score.startTick(ofBar: range.firstBar),range: range,notation: notation).frame(height: notation == .combined ? 240 : 160)
                Button("开始跟练") { selectedPassage = nil; resumeTick = nil; launch() }.buttonStyle(ScorePrimaryStyle()).accessibilityIdentifier("score.start")
                HStack { Text("我的难点").font(GitaFont.title()); Spacer(); Button("＋ 标记") { editing = .init(versionID: score.versionID,title: "第\(range.firstBar+1)–\(range.lastBar+1)小节",range: range,speed: speed) } }
                ForEach(passages) { passage in passageCard(passage) }
                if passages.isEmpty { Text("在这里保存需要反复练的片段，下次直接专项练习。").font(GitaFont.callout()).foregroundStyle(GitaTheme.textSecondary) }
                Toggle("显示已掌握片段",isOn: $showMastered).font(GitaFont.callout())
                NavigationLink("查看跟谱记录") { ScoreResultsView(library: library,versionID: score.versionID) }.font(GitaFont.callout())
                let previousVersions = library.versions(for: score.id).filter { $0.versionID != score.versionID }
                if !previousVersions.isEmpty {
                    Text("其他版本与原有难点").font(GitaFont.callout(.bold))
                    ForEach(previousVersions,id: \.versionID) { previous in
                        NavigationLink { ScoreDetailView(score: previous,library: library,entry: entry) } label: {
                            Text("\(previous.title) · \(previous.bars.count)小节 · \(library.passages.filter { $0.versionID == previous.versionID }.count)个难点")
                        }
                    }
                    Text("旧难点保留在原版本。修订后小节可能改变，请在新版本核对范围后重新标记。").font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
                }
                if let sourceID = score.sourceID {
                    Button("对照原谱，修订为新版本") {
                        do {
                            var copy = score; copy.versionID = UUID()
                            revisionDraft = .init(score: copy,issues: [])
                            revision = try ScoreSourceVault.restore(profileID: library.profileID,sourceID: sourceID)
                        } catch { self.error = error.localizedDescription }
                    }.font(GitaFont.callout())
                }
                if let error { Text(error).foregroundStyle(GitaTheme.statusError) }
            }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }.background(GitaTheme.bgDefault).navigationTitle("准备跟练").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $chooseItem,onDismiss: {
                guard let choice = pendingStart else { return }
                pendingStart = nil
                start(preferred: choice.itemID)
            }) { itemChoice }
            .sheet(item: $editing) { passage in NavigationStack { ScorePassageEditor(library: library,versionID: score.versionID,range: passage.range,speed: passage.speed,existing: passage) } }
            .fullScreenCover(item: $playerSession,onDismiss: {
                showSavedResult = (lastStartedSession?.model.run.elapsedSeconds ?? 0) > 0
                lastStartedSession = nil; createdItemID = nil; launchToken = UUID()
            }) { session in ScorePlayerView(model: session.model) }
            .alert("无法开始跟练",isPresented: Binding(get: { launchError != nil },set: { if !$0 { launchError = nil } })) {
                Button("知道了",role: .cancel) { launchError = nil }
            } message: { Text(launchError ?? "") }
            .navigationDestination(isPresented: $showSavedResult) {
                ScoreResultsView(library: library,versionID: score.versionID)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showSavedResult = false } } }
            }
            .sheet(item: $revision) { selection in
                if let revisionDraft { NavigationStack { ScoreDraftEditor(initial: revisionDraft,selection: selection,library: library) { revision = nil } } }
            }
            .task {
                if case .existing(let id) = entry, let link = library.link(for: id),link.versionID == score.versionID {
                    range = link.range; speed = link.speed
                }
            }
    }
    private var prepare: some View {
        VStack(spacing: 12) {
            Picker("模式",selection: $mode) { ForEach(ScoreRunMode.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            Stepper("开始：第\(range.firstBar+1)小节",value: $range.firstBar,in: 0...max(0,range.lastBar))
            Stepper("结束：第\(range.lastBar+1)小节",value: $range.lastBar,in: range.firstBar...max(range.firstBar,score.bars.count-1))
            Picker("播放速度",selection: $speed) { ForEach([0.25,0.5,0.75,1.0,1.25],id: \.self) { Text("\(Int($0*100))%").tag($0) } }.disabled(mode == .performance)
            Picker("谱面",selection: $notation) { ForEach(ScoreNotation.allCases) { Text($0.title).tag($0) } }
            if mode == .practice { Stepper("循环\(loops)次",value: $loops,in: 1...99) }
            else { Text("原速连贯演奏，结束后查看复盘。").font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary) }
        }.font(GitaFont.callout()).scoreSurface()
    }
    private func passageCard(_ passage: ScorePassage) -> some View {
        VStack(alignment: .leading,spacing: 12) {
            HStack {
                Text(passage.title).font(GitaFont.headline()); Spacer()
                Menu(passage.status.title) {
                    ForEach(ScorePassageStatus.allCases) { status in Button(status.title) { var next = passage; next.status = status; next.updatedAt = Date(); do { try library.save(passage: next) } catch { self.error = error.localizedDescription } } }
                    Button("编辑") { editing = passage }
                    Button("删除",role: .destructive) { do { try library.deletePassage(passage.id) } catch { self.error = error.localizedDescription } }
                }.font(GitaFont.caption())
            }
            Text("第\(passage.range.firstBar+1)–\(passage.range.lastBar+1)小节 · \(Int(passage.speed*100))%速度 · 循环\(passage.loops)次").font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
            if !passage.note.isEmpty { Text(passage.note).font(GitaFont.callout()).foregroundStyle(GitaTheme.textSecondary) }
            ScoreCanvasView(score: score,tick: score.startTick(ofBar: passage.range.firstBar),range: passage.range).frame(height: 100)
            Button("开始专项练习") { selectedPassage = passage; resumeTick = nil; range = passage.range; speed = passage.speed; mode = .practice; launch() }.buttonStyle(ScorePrimaryStyle()).accessibilityIdentifier("score.passage.start")
        }.padding(16).background(GitaTheme.brand50,in: RoundedRectangle(cornerRadius: 20)).overlay { RoundedRectangle(cornerRadius: 20).stroke(GitaTheme.brand500,lineWidth: 1) }
    }
    private func launch() {
        switch entry {
        case .existing(let id): start(preferred: id)
        case .newPractice: start(preferred: createdItemID)
        case .tool:
            do {
                let profile = try store.scoreProfileID(), day = PracticeDayKey.make(from: Date(),calendar: .current)
                todayItems = try store.practiceItemSnapshots(profileId: profile).filter { !$0.isDeleted && $0.practiceDayKey == day && !router.completedPracticeItemIds.contains($0.id) }
                pendingStart = nil
                chooseItem = true
            } catch { launchError = error.localizedDescription }
        }
    }
    private var itemChoice: some View {
        NavigationStack {
            List {
                Section("今天的练习") { ForEach(todayItems,id: \.id) { item in Button { pendingStart = .existing(item.id); chooseItem = false } label: { VStack(alignment: .leading) { Text(item.title); Text("今天已练\(item.durationSeconds/60)分钟").font(.caption).foregroundStyle(.secondary) } } } }
                Button("新建今日练习") { pendingStart = .new; chooseItem = false }.font(GitaFont.callout(.bold))
            }.navigationTitle("保存到哪个练习？").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { pendingStart = nil; chooseItem = false } } }
        }.presentationDetents([.medium,.large])
    }
    private func start(preferred: UUID?) {
        guard playerSession == nil else { return }
        do {
            let item = try store.openScorePractice(score: score,preferredItemID: preferred ?? createdItemID,completedIDs: router.completedPracticeItemIds,now: Date(),calendar: .current,origin: launchToken.uuidString)
            createdItemID = item.id
            try library.save(link: .init(practiceItemID: item.id,versionID: score.versionID,range: range,speed: mode == .performance ? 1 : speed))
            let model = try ScoreRuntimeModel(score: score,item: item,library: library,store: store,range: range,speed: speed,loops: selectedPassage?.loops ?? (mode == .practice ? loops : 1),mode: mode,passageID: selectedPassage?.id,resumeTick: resumeTick)
            model.notation = notation
            let session = ScorePlayerSession(model: model)
            lastStartedSession = session
            playerSession = session
        } catch { launchError = error.localizedDescription }
    }
}

/// The item is both the presentation trigger and its nonoptional content payload.
@MainActor struct ScorePlayerSession: Identifiable {
    let id = UUID()
    let model: ScoreRuntimeModel
}

private enum ScoreItemChoice {
    case new,existing(UUID)
    var itemID: UUID? { if case .existing(let id) = self { id } else { nil } }
}

struct ScoreResultsView: View {
    let library: ScoreLibrary
    var versionID: UUID? = nil
    private var results: [ScorePracticeResult] { library.results.filter { versionID == nil || $0.versionID == versionID } }
    var body: some View {
        List {
            ForEach(results) { result in
                VStack(alignment: .leading,spacing: 8) {
                    Text(library.score(versionID: result.versionID)?.title ?? "历史曲谱").font(GitaFont.headline())
                    Text(result.createdAt,style: .date).font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
                    Text("\(result.mode.title) · 第\(result.range.firstBar+1)–\(result.range.lastBar+1)小节 · \(Int(result.speed*100))%速度").font(GitaFont.caption())
                    Text(String(format: "%02d:%02d",result.seconds/60,result.seconds%60)).font(GitaFont.title())
                    Text("已同步到当天练习 · 完整循环\(result.completedLoops)次").font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
                    if result.mode == .performance { Text(result.completePerformance == true ? "原速连贯完成" : "部分／中断演奏").font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary) }
                    if let total = result.totalScore { Text("\(total)分 · 音高\(Int((result.pitchAccuracy ?? 0)*100))% · 节奏\(Int((result.rhythmAccuracy ?? 0)*100))%").foregroundStyle(GitaTheme.brand500) }
                    else { Text("可判定内容不足，未生成总分").font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary) }
                }.padding(.vertical,8)
            }
            if results.isEmpty { ContentUnavailableView("还没有跟谱记录",systemImage: "music.note",description: Text("开始跟练后，实际时长会保存到当天练习。")) }
        }.navigationTitle("跟谱记录")
    }
}

extension View {
    func scoreSurface() -> some View { padding(16).background(GitaTheme.bgSurface,in: RoundedRectangle(cornerRadius: 20)) }
}
