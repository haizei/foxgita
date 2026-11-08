import SwiftUI
import UIKit

#if DEBUG && targetEnvironment(simulator)
@MainActor enum ScoreReviewUITestFixture {
    static func prepare(library: ScoreLibrary) throws -> ScoreImportSelection {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 300,height: 120)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0,y: 0,width: 300,height: 120))
            ("识谱校正测试原件" as NSString).draw(at: CGPoint(x: 20,y: 40),withAttributes: [.foregroundColor: UIColor.black])
        }
        let selection = try ScoreImportSelection.images([image.jpegData(compressionQuality: 0.9)!])
        let full = ScoreEvent(tick: 0,duration: 3840,tones: [.init(midi: 64)])
        let draft = RecognizedScoreDraft(score: .init(title: "识谱校正测试",bars: [
            .init(number: 1,events: []),
            .init(number: 2,events: [.init(tick: 0,duration: 960,tones: [.init(midi: 64)])]),
            .init(number: 3,events: [full]),
            .init(number: 4,events: [.init(tick: 0,duration: 3840,tones: [.init(midi: 60)])])
        ]),issues: [.init(field: "recognition",message: "请核对第4小节音高。",bar: 4)])
        try ScoreSourceVault.save(selection,profileID: library.profileID)
        try ScoreSourceVault.saveDraft(draft,profileID: library.profileID,sourceID: selection.id)
        return selection
    }
}
#endif

struct ScoreImportView: View {
    @Environment(\.dismiss) private var dismiss
    let selection: ScoreImportSelection
    let library: ScoreLibrary
    @State private var draft: RecognizedScoreDraft?
    @State private var readingLocally = false
    @State private var processing = false
    @State private var error: String?
    @State private var task: Task<Void,Never>?
    @State private var localJob: ScoreLocalRecognitionJob?
    @State private var localRunID: UUID?
    @State private var pageStatuses: [Int:String] = [:]
    @State private var ready = false
    @State private var upgradingDraft = false
    @State private var draftLoadWarning: String?
    @State private var request: ScoreSourceVault.RecognitionRequest?
    @State private var client = ScoreRecognitionClient()
    var body: some View {
        Group {
            if upgradingDraft {
                ProgressView("正在本机更新识别结果…")
            } else if let draft {
                ScoreDraftEditor(initial: draft,selection: selection,library: library,loadWarning: draftLoadWarning) { dismiss() }
            } else {
                ScrollView {
                    VStack(alignment: .leading,spacing: 20) {
                        Text("导入谱页").font(GitaFont.title())
                        Text("共\(selection.pages.count)页 · 印刷六线谱或五线谱").font(GitaFont.callout()).foregroundStyle(GitaTheme.textSecondary)
                        ForEach(selection.pages.indices,id: \.self) { i in
                            Text("第\(i+1)页 · \(pageStatuses[i+1] ?? "待识谱")").font(GitaFont.caption(.bold)).foregroundStyle(GitaTheme.textSecondary)
                            if let image = UIImage(data: selection.pages[i]) {
                                NavigationLink { ScoreOriginalPageView(image: image).navigationTitle("第\(i+1)页") } label: { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220).clipShape(RoundedRectangle(cornerRadius: 12)) }.disabled(processing)
                            }
                        }
                        if request == nil && !processing {
                            Button("在本机识别六线谱") { startLocal() }.buttonStyle(ScorePrimaryStyle())
                                .disabled(!ready).accessibilityIdentifier("score.local-tab")
                            Text("适用于清晰、正面的印刷六线谱，谱页不会上传。").font(GitaFont.caption())
                        }
                        Text("使用云端识谱会将以上谱页发送到\(client.destinationLabel)。结果需要对照原谱校正并确认；你的弹奏音频不会上传。").font(GitaFont.callout()).foregroundStyle(GitaTheme.textSecondary)
                        if processing {
                            if readingLocally {
                                ProgressView("正在本机读取六线谱…")
                            } else if request?.phase == .cancelling {
                                ProgressView("正在取消识谱…")
                            } else if request?.jobID != nil {
                                ProgressView("正在识谱，原件已保留…").accessibilityIdentifier("score.job-running")
                            } else {
                                ProgressView("正在提交谱页…")
                            }
                            if request?.phase != .cancelling {
                                Button("取消识谱") { cancel() }
                                    .disabled(!readingLocally && client.managedDestination != nil && request?.jobID == nil)
                            }
                        } else {
                            Button(actionTitle) { start() }.buttonStyle(ScorePrimaryStyle())
                                .disabled(!ready).accessibilityIdentifier("score.recognize")
                            if matchingRequest?.phase == .active, matchingRequest?.jobID != nil {
                                Button("取消识谱") { cancel() }
                            }
                        }
                        if let error { Text(error).font(GitaFont.callout()).foregroundStyle(GitaTheme.statusError) }
                    }.padding(20)
                }
            }
        }.background(GitaTheme.bgDefault).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { cancelLocal(); task?.cancel(); dismiss() }.disabled(processing && request?.phase == .cancelling)
                }
            }
            .task {
                guard !ready else { return }
                do {
                    try ScoreSourceVault.save(selection,profileID: library.profileID)
                    if let saved = try ScoreSourceVault.draft(profileID: library.profileID,sourceID: selection.id) {
                        let pages = selection.pages
                        let repaired = await Task.detached(priority: .userInitiated) {
                            LocalTabReader.removingHeaderPanels(from: saved,pages: pages)
                        }.value
                        guard !Task.isCancelled else { return }
                        if repaired.needsLocalRecognitionUpgrade {
                            upgradingDraft = true
                            let worker = Task.detached(priority: .userInitiated) {
                                let fresh = try LocalTabReader.draft(pages: pages)
                                return repaired.refreshingUneditedBars(from: fresh).draft
                            }
                            do {
                                let updated = try await withTaskCancellationHandler {
                                    try await worker.value
                                } onCancel: { worker.cancel() }
                                try Task.checkCancellation()
                                try ScoreSourceVault.saveDraft(updated,profileID: library.profileID,sourceID: selection.id)
                                draft = updated
                            } catch {
                                guard !Task.isCancelled else { upgradingDraft = false; return }
                                draftLoadWarning = "自动更新识别未完成，已保留原有草稿。\(error.localizedDescription)"
                                draft = repaired
                            }
                            upgradingDraft = false
                        } else { draft = repaired }
                    }
                    request = try ScoreSourceVault.recognitionRequest(profileID: library.profileID, sourceID: selection.id)
                    ready = true
                    if draft == nil, let matchingRequest, matchingRequest.phase != .needsRetry {
                        start()
                    } else if draft == nil, request != nil, matchingRequest == nil {
                        error = "识谱服务已更改。请核对新的上传目标并重新同意。"
                    }
                } catch { self.error = error.localizedDescription }
            }
            .onDisappear { cancelLocal(); task?.cancel() }
            .interactiveDismissDisabled(processing && request?.phase == .cancelling)
    }

    private var matchingRequest: ScoreSourceVault.RecognitionRequest? {
        guard let request, request.destination == client.managedDestination else { return nil }
        return request
    }

    private var actionTitle: String {
        switch matchingRequest?.phase {
        case .cancelling: return "重试取消"
        case .active: return "继续识谱"
        case .needsRetry: return "重试识谱"
        case nil: return pageStatuses.isEmpty ? "同意上传并识谱" : "重试识谱"
        }
    }

    private func persist(_ value: ScoreSourceVault.RecognitionRequest?) throws {
        try ScoreSourceVault.saveRequest(value, profileID: library.profileID, sourceID: selection.id)
        request = value
    }

    private func startLocal() {
        guard ready, !processing, request == nil else { return }
        error = nil; processing = true; readingLocally = true
        let pages = selection.pages
        let runID = UUID()
        localRunID = runID
        localJob = ScoreLocalRecognitionJob.start(timeout: max(30, Double(pages.count) * 10), operation: { check in
            try LocalTabReader.draft(pages: pages, checkCancellation: check)
        }, completion: { result in
            guard localRunID == runID else { return }
            localRunID = nil; localJob = nil
            processing = false; readingLocally = false
            do {
                let result = try result.get()
                guard result.localReadings?.values.contains(where: { !$0.attacks.isEmpty }) == true else {
                    error = "未读到可靠的六线谱符号。请换用清晰、正面的原图，或自行选择云端识谱。"
                    return
                }
                try ScoreSourceVault.saveDraft(result, profileID: library.profileID, sourceID: selection.id)
                draft = result
            } catch { if !(error is CancellationError) { self.error = error.localizedDescription } }
        })
    }

    private func cancelLocal() {
        guard readingLocally else { return }
        localRunID = nil
        localJob?.cancel(); localJob = nil
        processing = false; readingLocally = false
    }

    private func start() {
        guard ready, !processing else { return }
        if matchingRequest?.phase == .cancelling { cancel(); return }
        error = nil
        do {
            var next = matchingRequest
            if let destination = client.managedDestination {
                if next == nil { next = .init(destination: destination, requestID: selection.id) }
                if next?.phase == .needsRetry {
                    next?.phase = .active
                    next?.jobID = nil
                }
            }
            // Commit consent and the stable key before the first byte can leave the device.
            try persist(next)
        } catch { self.error = error.localizedDescription; return }
        processing = true
        client.onProgress = { pageStatuses = $0 }
        task = Task {
            do {
                let result = try await client.recognize(pages: selection.pages,
                    requestID: request?.requestID ?? selection.id, existingJobID: request?.jobID,
                    onJobAccepted: { id in
                        guard var current = request else { throw ScoreRecognitionError.malformed }
                        current.jobID = id
                        try persist(current)
                    }, onRetryRequired: {
                        guard var current = request else { throw ScoreRecognitionError.malformed }
                        current.phase = .needsRetry
                        try persist(current)
                    })
                try Task.checkCancellation()
                try ScoreSourceVault.saveDraft(result,profileID: library.profileID,sourceID: selection.id)
                draft = result
                try persist(nil)
            } catch {
                if !Task.isCancelled, !(error is CancellationError) { self.error = error.localizedDescription }
            }
            if !Task.isCancelled || request?.phase != .cancelling { processing = false }
        }
    }

    private func cancel() {
        if readingLocally { cancelLocal(); return }
        guard var current = matchingRequest, let jobID = current.jobID else {
            task?.cancel()
            return
        }
        do {
            current.phase = .cancelling
            try persist(current)
        } catch { self.error = error.localizedDescription; return }
        let observer = task
        observer?.cancel()
        processing = true
        error = nil
        task = Task {
            await observer?.value
            do {
                try await client.cancelManagedJob(jobID, destination: current.destination)
                current.phase = .needsRetry
                try persist(current)
                pageStatuses = Dictionary(uniqueKeysWithValues: selection.pages.indices.map { ($0 + 1, "已取消") })
            } catch { self.error = error.localizedDescription }
            processing = false
        }
    }
}

struct ScoreDraftEditor: View {
    @State var draft: RecognizedScoreDraft
    let selection: ScoreImportSelection
    let library: ScoreLibrary
    var onSaved: () -> Void
    @State private var checked = false
    @State private var error: String?
    @State private var filter: ScoreBarReviewState?
    @State private var refreshing = false
    @State private var refreshTask: Task<Void,Never>?
    @State private var refreshMessage: String?
    @State private var reviewGroup: ScoreReviewGroup?
    init(initial: RecognizedScoreDraft,selection: ScoreImportSelection,library: ScoreLibrary,loadWarning: String? = nil,onSaved: @escaping () -> Void) {
        var initial = initial
        initial.updateLocalPitches()
        let legacyReviewed = initial.score.bars.filter {
            initial.reviewedBars?[$0.id] == $0 && initial.reviewedEvidence?[$0.id] == nil
        }.map(\.id)
        initial.acknowledgeReview(of: legacyReviewed)
        _error = State(initialValue: loadWarning)
        _draft = State(initialValue: initial); self.selection = selection; self.library = library; self.onSaved = onSaved
    }
    var body: some View {
        List {
            reviewOverview
            if !draft.reviewGroups.isEmpty {
                Section("集中核对相同疑点") {
                    Text("只处理下面的具体疑点。相同问题可一起核对，无需逐小节确认。")
                        .font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
                    ForEach(draft.reviewGroups) { group in
                        Button { error = nil; reviewGroup = group } label: {
                            Label("核对\(group.concern.title) · \(group.barIDs.count)个小节",systemImage: "checklist")
                        }.accessibilityIdentifier("score.review.group.\(group.concern.rawValue)")
                    }
                }
            }
            if draft.localReadings != nil && !draft.isConfirmed {
                Section {
                    Button("重新识别待处理小节") { refreshRecognition() }
                        .accessibilityIdentifier("score.review.refresh")
                    if refreshing { ProgressView("正在本机重新识别…") }
                    Text(refreshMessage ?? "保留已核对或手动修改的小节，尝试补齐其余内容；原谱不会上传。")
                        .font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
                }
            }
            Section("对照原谱") {
                ForEach(selection.pages.indices,id: \.self) { i in
                    if let image = UIImage(data: selection.pages[i]) { NavigationLink("查看原谱第\(i+1)页") { ScoreOriginalPageView(image: image).navigationTitle("原谱第\(i+1)页") } }
                }
            }
            Section {
                DisclosureGroup("曲谱信息 · 曲名、速度与调弦") {
                TextField("曲名",text: $draft.score.title)
                TextField("作者",text: $draft.score.composer)
                HStack { Text("原速 BPM"); TextField("速度",value: $draft.score.tempo.bpm,format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                Picker("计拍单位",selection: $draft.score.tempo.beatUnit) { Text("二分音符").tag(2); Text("四分音符").tag(4); Text("八分音符").tag(8); Text("十六分音符").tag(16) }
                Stepper("变调夹：\(draft.score.capo)品",value: $draft.score.capo,in: 0...12)
                ForEach(0..<6,id: \.self) { i in
                    Picker("\(6-i)弦调弦",selection: $draft.score.tuning[i]) { ForEach(28...88,id: \.self) { Text(ScoreNoteName.name($0)).tag($0) } }
                }
                }
            }
            if !draft.issues.isEmpty {
                Section("需要你核对") {
                    ForEach(draft.issues) { issue in
                        VStack(alignment: .leading,spacing: 8) {
                            Text(draft.localReadings != nil && issue.field == "setup" ? RecognizedScoreDraft.localSetupMessage : issue.message)
                                .font(GitaFont.callout()).foregroundStyle(GitaTheme.brand500)
                            if let page = issue.page { ScoreSourceLink(location: .init(page: page,box: issue.box),pages: selection.pages) }
                        }
                    }
                }
            }
            Section("校正音符与节奏") {
                Picker("筛选小节", selection: $filter) {
                    Text("全部").tag(nil as ScoreBarReviewState?)
                    Text("待校正").tag(ScoreBarReviewState.needsCorrection as ScoreBarReviewState?)
                    Text("未识别").tag(ScoreBarReviewState.unrecognized as ScoreBarReviewState?)
                    Text("已识别").tag(ScoreBarReviewState.recognized as ScoreBarReviewState?)
                }.pickerStyle(.segmented).accessibilityIdentifier("score.review.filter")
                ForEach($draft.score.bars) { $bar in
                    let state = draft.reviewState(for: bar)
                    if filter == nil || filter == state {
                        NavigationLink { correctionView(bar: $bar) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("第\(bar.number)小节 · \(bar.numerator)/\(bar.denominator)").font(GitaFont.callout(.bold))
                                Label(state.title, systemImage: state.symbol)
                                    .font(GitaFont.caption(.bold)).foregroundStyle(reviewColor(state))
                                Text(draft.reviewReason(for: bar)).font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
                                Text(state == .unrecognized ? "对照原谱，补录内容" : state == .needsCorrection ? "查看具体疑点" : "查看内容（可选）")
                                    .font(GitaFont.caption(.bold)).foregroundStyle(GitaTheme.brand500)
                            }.padding(.vertical, 6)
                        }.accessibilityIdentifier("score.review.bar.\(bar.id.uuidString)")
                    }
                }
                if let filter, !draft.score.bars.contains(where: { draft.reviewState(for: $0) == filter }) {
                    Text("没有\(filter.title)的小节。可切换筛选查看其他小节。")
                        .font(GitaFont.callout()).foregroundStyle(GitaTheme.textSecondary)
                }
            }
            if draft.localReadings == nil { Section("校正小节线") {
                ForEach(draft.score.bars.indices,id: \.self) { index in
                    NavigationLink("第\(index+1)小节：拆分或合并") { ScoreBarBoundaryEditor(score: $draft.score,index: index) }
                }
            }
            }
            if (try? draft.score.validate()) != nil {
                Section("谱面预览") {
                    if let bar = draft.score.bars.first(where: { !$0.events.isEmpty }) {
                        let index = draft.score.bars.firstIndex(where: { $0.id == bar.id }) ?? 0
                        Text("第\(bar.number)小节附近 · 仅预览已读出的内容，请以原谱为准")
                            .font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
                        ScoreCanvasView(score: draft.score,tick: draft.score.startTick(ofBar: index),notation: .combined).frame(height: 260).listRowInsets(EdgeInsets())
                    } else {
                        Label("暂无可预览的音乐内容", systemImage: "music.note.list")
                        Text("请先进入未识别的小节，对照原谱补录音符或休止。")
                            .font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
                    }
                }
            }
            Section {
                Toggle("我已对照原谱核对音符、节奏、调弦和速度",isOn: $checked)
                if let error { Text(error).foregroundStyle(GitaTheme.statusError) }
                if let incomplete = firstIncompleteBar {
                    Text("还有\(problemCount)个小节需要处理。先处理第\(incomplete.number)小节，再核对整首曲谱。")
                    Text(draft.reviewReason(for: incomplete)).font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
                    if let index = draft.score.bars.firstIndex(where: { $0.id == incomplete.id }) {
                        NavigationLink("处理第\(incomplete.number)小节") { correctionView(bar: $draft.score.bars[index]) }
                    }
                } else {
                    Text(checked ? "可以确认保存曲谱。" : "所有小节数据已完整。请核对曲谱信息，并打开上方确认开关。")
                        .font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
                }
                Button("确认曲谱，加入我的曲谱") { publish() }.disabled(!checked || firstIncompleteBar != nil).accessibilityIdentifier("score.publish")
            }
        }.disabled(refreshing).navigationTitle("识谱校正").navigationBarTitleDisplayMode(.inline)
            .onChange(of: draft.score) { _, _ in checked = false }
            .onChange(of: draft.score.capo) { _, _ in draft.updateLocalPitches() }
            .onChange(of: draft.score.tuning) { _, _ in draft.updateLocalPitches() }
            .sheet(item: $reviewGroup) { group in groupReview(group) }
            .onDisappear {
                refreshTask?.cancel()
                do { try ScoreSourceVault.saveDraft(draft,profileID: library.profileID,sourceID: selection.id) } catch { self.error = error.localizedDescription }
            }
    }
    private func refreshRecognition() {
        guard !refreshing else { return }
        refreshing = true; error = nil; refreshMessage = nil
        let original = draft, pages = selection.pages
        refreshTask = Task { @MainActor in
            defer { refreshing = false }
            do {
                let fresh = try await Task.detached(priority: .userInitiated) {
                    try LocalTabReader.draft(pages: pages)
                }.value
                guard !Task.isCancelled else { return }
                let result = original.refreshingUneditedBars(from: fresh)
                draft = result.draft; checked = false
                try ScoreSourceVault.saveDraft(draft,profileID: library.profileID,sourceID: selection.id)
                refreshMessage = result.updated == 0 ? "没有发现可自动更新的内容，已保留当前校正结果。" : "已更新\(result.updated)个小节。已核对或手动修改的内容已保留，请对照原谱检查新结果。"
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
        }
    }
    private var firstIncompleteBar: ScoreBar? {
        draft.score.bars.first { draft.reviewState(for: $0) != .recognized }
    }
    private var problemCount: Int { draft.score.bars.filter { draft.reviewState(for: $0) != .recognized }.count }

    private func reviewColor(_ state: ScoreBarReviewState) -> Color {
        switch state {
        case .recognized: GitaTheme.statusSuccessText
        case .needsCorrection: GitaTheme.brand500
        case .unrecognized: GitaTheme.textSecondary
        }
    }

    private var reviewOverview: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                Text(problemCount == 0 ? "已处理全部疑点，可确认曲谱" : draft.score.bars.allSatisfy(draft.canReview) ? "已生成音乐内容，只需核对具体疑点" : "识谱尚未完成，先处理问题小节")
                    .font(GitaFont.title())
                HStack(alignment: .top, spacing: 12) {
                    ForEach(ScoreBarReviewState.allCases, id: \.self) { state in
                        Button { filter = state } label: {
                            VStack(spacing: 6) {
                                Text("\(draft.score.bars.filter { draft.reviewState(for: $0) == state }.count)").font(GitaFont.title())
                                Label(state.title, systemImage: state.symbol).font(GitaFont.caption(.bold))
                            }.frame(maxWidth: .infinity).foregroundStyle(reviewColor(state))
                        }.buttonStyle(.plain).accessibilityLabel("\(state.title)，\(draft.score.bars.filter { draft.reviewState(for: $0) == state }.count)个小节，点击筛选")
                    }
                }
                Text("已识别的小节无需逐个确认。只核对有具体疑点的部分，最后确认整首曲谱信息。")
                    .font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
                Text("关闭后可在“待识谱／待校正原件”中继续处理。")
                    .font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
            }.padding(.vertical, 8)
            if let bar = firstIncompleteBar, let index = draft.score.bars.firstIndex(where: { $0.id == bar.id }) {
                NavigationLink { correctionView(bar: $draft.score.bars[index]) } label: {
                    Label("\(bar.events.isEmpty ? "开始补录" : "继续校正")：第\(bar.number)小节", systemImage: "arrow.right.circle.fill")
                }.font(GitaFont.callout(.bold)).accessibilityIdentifier("score.review.next")
            }
        }
    }

    private func correctionView(bar: Binding<ScoreBar>) -> some View {
        ScoreBarCorrectionView(bar: bar,tuning: draft.score.tuning,capo: draft.score.capo,ticksPerQuarter: draft.score.ticksPerQuarter,sourcePages: selection.pages,
            reading: Binding(get: { draft.localReadings?[bar.wrappedValue.id] }, set: { draft.localReadings?[bar.wrappedValue.id] = $0 }),
            reviewState: draft.reviewState(for: bar.wrappedValue),reviewReason: draft.reviewReason(for: bar.wrappedValue),canMarkReviewed: draft.canReview(bar.wrappedValue),
            onReviewed: { draft.acknowledgeReview(of: [bar.wrappedValue.id]) })
    }

    private func groupReview(_ group: ScoreReviewGroup) -> some View {
        NavigationStack {
            Form {
                Section("只核对这一项") {
                    Text(group.concern.message)
                    if group.concern == .strumRange {
                        Text("当前按每张指法图中标明可弹的琴弦生成扫弦。请检查原谱是否要求缩小范围或闷音；有不同要求的小节可返回单独校正。")
                            .font(GitaFont.callout())
                    } else {
                        Text("这些小节具有相同的击弦连接和时值。请核对原谱中的两个音及连接方式。")
                            .font(GitaFont.callout())
                    }
                }
                Section("涉及的原谱位置") {
                    ForEach(draft.score.bars.filter { group.barIDs.contains($0.id) }) { bar in
                        VStack(alignment: .leading,spacing: 6) {
                            Text("第\(bar.number)小节").font(GitaFont.callout(.bold))
                            if let source = bar.source { ScoreSourceLink(location: source,pages: selection.pages) }
                        }
                    }
                }
                Section {
                    if let error { Text(error).foregroundStyle(GitaTheme.statusError) }
                    Button("已核对，确认这\(group.barIDs.count)个小节") {
                        var updated = draft
                        guard updated.confirmReviewGroup(group) else {
                            error = "疑点或音乐内容已变化，请返回后重新选择。"; return
                        }
                        do {
                            try ScoreSourceVault.saveDraft(updated,profileID: library.profileID,sourceID: selection.id)
                            draft = updated; checked = false; reviewGroup = nil
                        } catch { self.error = error.localizedDescription }
                    }.accessibilityIdentifier("score.review.group.confirm")
                    Text("这次只确认上面列出的小节与疑点，其他问题仍会保留。")
                        .font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
                }
            }.navigationTitle("核对\(group.concern.title)").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("返回校正") { reviewGroup = nil } } }
        }
    }

    private func publish() {
        do {
            guard firstIncompleteBar == nil else { return }
            if draft.localReadings != nil {
                if let gap = draft.score.bars.first(where: { !draft.hasReviewedCoverage($0) }) {
                    throw ScoreValidationError.invalidEvent(gap.number)
                }
                for b in draft.score.bars.indices {
                    for e in draft.score.bars[b].events.indices {
                        var event = draft.score.bars[b].events[e]
                        for i in event.tones.indices {
                            if let s = event.tones[i].string, (1...6).contains(s), let f = event.tones[i].fret {
                                event.tones[i].midi = draft.score.tuning[6-s] + draft.score.capo + f
                            }
                        }
                        draft.score.bars[b].events[e] = event
                    }
                }
            }
            try draft.score.validate()
            guard !draft.score.soundingEvents.isEmpty else { throw ScoreRecognitionError.malformed }
            draft.score.sourceID = selection.id
            draft.isConfirmed = true
            try ScoreSourceVault.saveDraft(draft,profileID: library.profileID,sourceID: selection.id)
            try library.save(score: draft.score)
            onSaved()
        } catch { self.error = error.localizedDescription }
    }
}

private struct ScoreBarBoundaryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var score: ScoreDocument
    let index: Int
    @State private var afterBeats = 1
    @State private var error: String?
    var body: some View {
        Form {
            if score.bars.indices.contains(index) {
                Section("补充漏识别的小节线") {
                    Stepper("在第\(afterBeats)拍后拆分",value: $afterBeats,in: 1...max(1,min(32,score.bars[index].numerator)-1))
                    Button("拆成两个小节") { apply { try ScoreCorrection.split(score: &$0,barIndex: index,afterBeats: afterBeats) } }
                        .disabled(score.bars[index].numerator < 2)
                }
                Section("移除误识别的小节线") {
                    Text("只合并拍号相同且边界没有速度或段落变化的相邻小节。音符和总时长会保留。").font(GitaFont.caption())
                    Button("与下一小节合并") { apply { try ScoreCorrection.mergeWithNext(score: &$0,barIndex: index) } }.disabled(index+1 >= score.bars.count)
                }
            }
            if let error { Text(error).foregroundStyle(GitaTheme.statusError) }
        }.navigationTitle("小节线校正")
    }
    private func apply(_ operation: (inout ScoreDocument) throws -> Void) {
        do { try operation(&score); dismiss() } catch { self.error = error.localizedDescription }
    }
}

private struct ScoreBarCorrectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var bar: ScoreBar
    let tuning: [Int]
    let capo: Int
    let ticksPerQuarter: Int
    var sourcePages: [Data] = []
    @Binding var reading: TabReading?
    var reviewState: ScoreBarReviewState? = nil
    var reviewReason: String? = nil
    var canMarkReviewed = false
    var onReviewed: (() -> Void)? = nil
    var body: some View {
        Form {
            if let reviewState {
                Section("本小节状态") {
                    Label(reviewState.title, systemImage: reviewState.symbol)
                    if let reviewReason { Text(reviewReason).font(GitaFont.callout()) }
                    Text("先查看原谱，再检查下方音符与休止的起拍、时值和弦品。")
                        .font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
                }
            }
            if let source = bar.source { Section("原谱位置") { ScoreSourceLink(location: source,pages: sourcePages) } }
            if let reading {
                Section("本机读到的谱面符号") {
                    if let problem = reading.problem { Text(problem) }
                    if reading.hasFourQuarterBeats {
                        NavigationLink("按和弦指法补录多拍") { TabChordCorrection(bar:$bar,reading:reading,tuning:tuning,capo:capo) }
                    }
                    ForEach(Array(reading.attacks.enumerated()),id: \.offset) { index, a in
                        let symbols = a.effectiveMarks.joined(separator: " · ")
                        let title = reading.hasFourQuarterBeats ? "第\(Double(a.start)/4+1, format: .number)拍" as LocalizedStringKey : "第\(index+1)组"
                        VStack(alignment: .leading) {
                            Text(title)
                            Text(symbols).font(.body.monospaced())
                            if let binding = a.diagramBinding {
                                Text("按指法图推导：" + binding.joined(separator: " · "))
                                if let range = a.strumRange, range.isLocated(in: a.box),
                                   let strings = range.crossedStrings, a.correctedArrow == nil {
                                    Text("原谱扫弦范围：第" + strings.map(String.init).joined(separator: "、") + "弦（已识别）")
                                    if !range.mutedStrings.isEmpty {
                                        Text("指法图静音弦：" + range.mutedStrings.map(String.init).joined(separator: "、"))
                                    }
                                } else if a.effectiveMarks == ["↑"] || a.effectiveMarks == ["↓"] {
                                    Text("箭头端点尚不清楚，请核对实际扫弦范围。")
                                }
                                if let page=bar.source?.page, let box=a.diagramBox {
                                    ScoreSourceLink(location:.init(page:page,box:box),pages:sourcePages)
                                }
                            }
                            if a.durationNeedsReview == true { Text("四分音时值候选，请对照原谱确认。") }
                            if a.marks == ["↑"] || a.marks == ["↓"] || a.marks == ["?"] {
                                Menu("校正扫弦方向") {
                                    Button("向上 ↑") { self.reading?.attacks[index].correctedArrow = "↑" }
                                    Button("向下 ↓") { self.reading?.attacks[index].correctedArrow = "↓" }
                                    Button("恢复识别结果") { self.reading?.attacks[index].correctedArrow = nil }
                                }
                            }
                            if let string=a.hammerString {
                                let next = index+1 < reading.attacks.count ? reading.attacks[index+1] : nil
                                Text(a.hammerEvidence?.matches(a,next: next) == true ? "\(string)弦击弦连接已识别。" : "\(string)弦疑似击弦，请核对连接的两个音。")
                            }
                            if let page=bar.source?.page, let box=a.box {
                                ScoreSourceLink(location:.init(page:page,box:box),pages:sourcePages)
                            }
                            if reading.hasFourQuarterBeats, !bar.events.contains(where: { $0.tick == a.start*240 }) {
                                NavigationLink("补录此拍的弹奏内容") {
                                    LocalAttackCorrection(tick:a.start*240, duration:a.length*240, tuning:tuning, capo:capo) { bar.events.append($0) }
                                }
                            }
                        }
                    }
                    Text("3:2 表示 3 弦 2 品；x3 表示 3 弦上的叉号；箭头表示扫弦方向。请按原谱填写实际弦品或明确的休止。")
                }
            }
            Section("拍号与和弦") {
                Stepper("每小节\(bar.numerator)拍",value: $bar.numerator,in: 1...32)
                Picker("计拍音符",selection: $bar.denominator) { ForEach([2,4,8,16],id: \.self) { Text("\($0)分音符").tag($0) } }
                TextField("段落名称",text: Binding(get: { bar.section ?? "" },set: { bar.section = $0.isEmpty ? nil : $0 }))
            }
            Section("音符／休止符") {
                ForEach($bar.events) { $event in
                    NavigationLink {
                        ScoreEventCorrectionView(event: $event,tuning: tuning,capo: capo,ticksPerQuarter: ticksPerQuarter,beatUnit: bar.denominator,sourcePages: sourcePages)
                    } label: {
                        VStack(alignment: .leading,spacing: 4) {
                            Text(event.isRest ? "休止符" : event.tones.map { ScoreNoteName.name($0.midi) }.joined(separator: " · "))
                            Text("第\(Double(event.tick)/Double(max(1,ticksPerQuarter*4/max(1,bar.denominator)))+1,format: .number.precision(.fractionLength(0...2)))拍").font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
                        }
                    }
                }.onDelete { bar.events.remove(atOffsets: $0) }
                Button("补充漏识别的音符") { bar.events.append(.init(tick: 0,duration: ticksPerQuarter,tones: [.init(midi: 64)])) }
                Button("补充漏识别的休止符") { bar.events.append(.init(tick: 0,duration: ticksPerQuarter,tones: [])) }
            }
            Text("增删仅用于改正识别结果。完成后返回，对照原谱确认整首曲谱。").font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
            if let onReviewed {
                Section {
                    Button("核对无误，返回") { onReviewed(); dismiss() }
                        .disabled(!canMarkReviewed).accessibilityIdentifier("score.review.confirm-bar")
                    if !canMarkReviewed { Text("请先补齐本小节的音符或休止，并消除缺拍、重叠和弦品冲突。")
                        .font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary) }
                }
            }
        }.navigationTitle("第\(bar.number)小节")
    }
}

private struct ScoreEventCorrectionView: View {
    @Binding var event: ScoreEvent
    let tuning: [Int]
    let capo: Int
    let ticksPerQuarter: Int
    let beatUnit: Int
    var sourcePages: [Data] = []
    private var beatTicks: Int { max(1,ticksPerQuarter*4/max(1,beatUnit)) }
    var body: some View {
        Form {
            if let source = event.source { Section("原谱位置") { ScoreSourceLink(location: source,pages: sourcePages) } }
            Section("节奏") {
                TextField("从第几拍开始",value: Binding(get: { Double(event.tick)/Double(beatTicks)+1 },set: { if $0.isFinite { event.tick = Int(max(0,min(32,$0-1))*Double(beatTicks)) } }),format: .number).keyboardType(.decimalPad)
                Picker("时值",selection: $event.duration) {
                    Text("全音符").tag(ticksPerQuarter*4); Text("附点二分").tag(ticksPerQuarter*3)
                    Text("二分音符").tag(ticksPerQuarter*2); Text("附点四分").tag(ticksPerQuarter*3/2)
                    Text("四分音符").tag(ticksPerQuarter); Text("八分音符").tag(ticksPerQuarter/2)
                    Text("十六分音符").tag(ticksPerQuarter/4); Text("八分三连音").tag(ticksPerQuarter/3)
                }
                TextField("和弦名",text: Binding(get: { event.chord ?? "" },set: { event.chord = $0.isEmpty ? nil : $0 }))
                TextField("歌词",text: Binding(get: { event.lyric ?? "" },set: { event.lyric = $0.isEmpty ? nil : $0 }))
            }
            ForEach(event.tones.indices,id: \.self) { i in
                Section("第\(i+1)个音") {
                    Picker("音高",selection: $event.tones[i].midi) { ForEach(28...100,id: \.self) { Text(ScoreNoteName.name($0)).tag($0) } }
                    Picker("琴弦",selection: Binding(get: { event.tones[i].string ?? 0 },set: { value in event.tones[i].string = value == 0 ? nil : value; if value == 0 { event.tones[i].fret = nil } else { event.tones[i].fret = event.tones[i].fret ?? 0; updatePitch(i) } })) {
                        Text("五线谱音高").tag(0); ForEach(1...6,id: \.self) { Text("\($0)弦").tag($0) }
                    }
                    if event.tones[i].string != nil {
                        Stepper("第\(event.tones[i].fret ?? 0)品",value: Binding(get: { event.tones[i].fret ?? 0 },set: { event.tones[i].fret = $0; updatePitch(i) }),in: 0...24)
                    }
                    Toggle("从上一个音延续（连音）",isOn: $event.tones[i].tiedFromPrevious)
                    Button("删除这个音",role: .destructive) { event.tones.remove(at: i) }
                }
            }
            if event.tones.count < 6 { Button("补充同响音") { event.tones.append(.init(midi: 64)) } }
            if !event.tones.isEmpty { Button("改为休止符",role: .destructive) { event.tones = [] } }
        }.navigationTitle("校正音符与节奏")
    }
    private func updatePitch(_ index: Int) {
        guard event.tones.indices.contains(index),let string = event.tones[index].string,let fret = event.tones[index].fret,(1...6).contains(string),(0...24).contains(fret),(0...12).contains(capo),tuning.count == 6,tuning.allSatisfy({ (24...88).contains($0) }) else { return }
        event.tones[index].midi = tuning[6-string]+capo+fret
    }
}

nonisolated enum ScoreNoteName {
    static func name(_ midi: Int) -> String {
        let value = max(0,min(127,midi)), names = ["C","C♯","D","D♯","E","F","F♯","G","G♯","A","A♯","B"]
        return "\(names[value%12])\(value/12-1)"
    }
}

struct ScoreOriginalPageView: UIViewRepresentable {
    let image: UIImage
    var box: [Double]? = nil
    func makeUIView(context: Context) -> UIScrollView {
        let scroll = ScorePageScrollView(); scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 6
        scroll.box = box
        let view = UIImageView(image: image); view.contentMode = .scaleAspectFit; view.tag = 719
        scroll.addSubview(view); scroll.delegate = context.coordinator
        return scroll
    }
    func updateUIView(_ scroll: UIScrollView,context: Context) {
        guard let view = scroll.viewWithTag(719) as? UIImageView else { return }
        view.image = image; view.frame = scroll.bounds; scroll.contentSize = scroll.bounds.size
        (scroll as? ScorePageScrollView)?.box = box
        scroll.setNeedsLayout()
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator: NSObject,UIScrollViewDelegate {
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { scrollView.viewWithTag(719) }
    }
}

private final class ScorePageScrollView: UIScrollView {
    var box: [Double]?
    override func layoutSubviews() {
        super.layoutSubviews()
        if zoomScale == minimumZoomScale,let image = viewWithTag(719) {
            image.frame = bounds
            contentSize = bounds.size
        }
        if let view = viewWithTag(719) as? UIImageView,let image = view.image {
            view.layer.sublayers?.filter { $0.name == "score-source" }.forEach { $0.removeFromSuperlayer() }
            if let box = ScoreSourceLocation(page: 1,box: box).validBox {
                let scale = min(view.bounds.width/image.size.width,view.bounds.height/image.size.height)
                let width = image.size.width*scale,height = image.size.height*scale
                let rect = CGRect(x: (view.bounds.width-width)/2+width*box[0],y: (view.bounds.height-height)/2+height*box[1],width: width*box[2],height: height*box[3])
                let layer = CAShapeLayer(); layer.name = "score-source"; layer.path = UIBezierPath(rect: rect).cgPath
                layer.strokeColor = UIColor.systemOrange.cgColor; layer.fillColor = UIColor.systemOrange.withAlphaComponent(0.12).cgColor; layer.lineWidth = 2
                view.layer.addSublayer(layer)
            }
        }
    }
}

private struct ScoreSourceLink: View {
    let location: ScoreSourceLocation
    let pages: [Data]
    var body: some View {
        if location.page > 0,pages.indices.contains(location.page-1),let image = UIImage(data: pages[location.page-1]) {
            NavigationLink("对照原谱第\(location.page)页\(location.validBox == nil ? "" : " · 已标出位置")") {
                ScoreOriginalPageView(image: image,box: location.validBox).navigationTitle("原谱第\(location.page)页")
            }
        }
    }
}

private struct LocalAttackCorrection: View {
    @Environment(\.dismiss) var dismiss
    let tick: Int
    let duration: Int
    let tuning: [Int]
    let capo: Int
    var save: (ScoreEvent) -> Void
    @State private var string = 1
    @State private var fret = 0
    var body: some View {
        Form {
            Picker("琴弦",selection:$string) { ForEach(1...6,id:\.self) { Text("\($0)弦").tag($0) } }
            Stepper("第\(fret)品",value:$fret,in:0...24)
            Button("确认弦品") {
                save(.init(tick:tick,duration:duration,tones:[.init(midi:tuning[6-string]+capo+fret,string:string,fret:fret)])); dismiss()
            }
            Button("确认为休止符") { save(.init(tick:tick,duration:duration,tones:[])); dismiss() }
        }.navigationTitle("对照原谱补录")
    }
}
