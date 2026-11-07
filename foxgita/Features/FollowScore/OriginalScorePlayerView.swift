import SwiftUI
import UIKit

struct OriginalScorePlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PracticeStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State var document: OriginalScoreDocument
    let library: OriginalScoreLibrary
    let entry: ScoreHubEntry
    let settings: OriginalScoreSettings
    var resumeAtRowStart = true
    @State private var runtime: OriginalScoreRuntime?
    @State private var pages: [UIImage] = []
    @State private var error: String?
    @State private var ranges = false
    @State private var editing: OriginalScoreDraft?
    @State private var first = 0
    @State private var last = 0

    var body: some View {
        VStack(spacing: 0) {
            if let runtime {
                controls(runtime)
                ScrollViewReader { reader in
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(pages.indices, id: \.self) { page in
                                OriginalScorePageView(image: pages[page], rows: document.rows.filter { $0.page == page }, numbers: document.rowNumbers,
                                    activeID: runtime.run.row.id, fraction: runtime.run.rowFraction)
                            }
                        }.padding(12)
                    }
                    .onChange(of: runtime.run.row.id) { _, id in
                        withAnimation(.easeOut(duration: 0.18)) { reader.scrollTo(id, anchor: .center) }
                    }
                    .onAppear { reader.scrollTo(runtime.run.row.id, anchor: .center) }
                }
                if let message = runtime.message {
                    HStack {
                        Text(message).font(.caption).foregroundStyle(GitaTheme.statusError)
                        if runtime.saveFailed { Button("重试保存") { runtime.persist() } }
                    }.padding(10)
                }
                HStack {
                    Button { runtime.rewind() } label: { Label("从头", systemImage: "backward.end") }
                    Spacer()
                    Button {
                        if runtime.run.state == .playing || runtime.run.state == .preparing { runtime.pause() }
                        else { runtime.play() }
                    } label: {
                        Label(runtime.run.state == .playing ? "暂停" : "播放",
                              systemImage: runtime.run.state == .playing ? "pause.fill" : "play.fill")
                            .frame(minWidth: 100).padding(14)
                    }.buttonStyle(.borderedProminent).tint(GitaTheme.brand500).accessibilityIdentifier("original.play")
                    Spacer()
                    VStack(spacing: 4) {
                        Text("节拍器").font(.caption2)
                        Toggle("节拍器", isOn: Binding(get: { runtime.metronome }, set: { runtime.setMetronome($0) }))
                            .labelsHidden().accessibilityLabel("节拍器").accessibilityIdentifier("original.metronome")
                    }
                }.padding(16)
            } else if let error { Text(error).foregroundStyle(GitaTheme.statusError).padding() }
            else { ProgressView("读取原谱…") }
            if runtime != nil, let error {
                Text(error).font(.caption).foregroundStyle(GitaTheme.statusError).padding(10)
            }
        }
        .overlay {
            if let runtime, runtime.run.state == .preparing {
                VStack(spacing: 16) {
                    Text("准备弹奏").font(.title2.bold())
                    Text("\(Int(ceil(runtime.run.preparationRemaining)))").font(.system(size: 80, weight: .bold, design: .rounded))
                        .accessibilityIdentifier("original.countdown")
                    Text("准备时间不计入练习时长").font(.caption)
                    Button("取消准备") { runtime.pause() }.buttonStyle(.bordered)
                        .accessibilityIdentifier("original.cancel-prepare")
                }.padding(32).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            }
        }
        .background(GitaTheme.bgDefault).navigationTitle(document.title).navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("关闭") {
                    runtime?.close()
                    if runtime?.saveFailed != true { dismiss() }
                }.accessibilityIdentifier("original.player-close")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("重新读取") {
                    runtime?.pause()
                    guard runtime?.saveFailed != true else { return }
                    do { editing = try library.beginRevision(document) } catch { self.error = error.localizedDescription }
                }.accessibilityIdentifier("original.edit")
            }
        }
        .task { load() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { runtime?.pause() } }
        .onDisappear { runtime?.close() }
        .sheet(isPresented: $ranges) { rangeSheet }
        .sheet(item: $editing) { draft in
            NavigationStack {
                OriginalScoreReadingView(draft: draft, library: library, entry: entry, settings: settings) { latest in
                    runtime?.close(); document = latest; runtime = nil; load(); editing = nil
                }
            }
        }
    }

    private func controls(_ runtime: OriginalScoreRuntime) -> some View {
        VStack(spacing: 10) {
            if let note = document.readingNote {
                Text(note).font(.caption2).foregroundStyle(GitaTheme.textSecondary)
                    .accessibilityIdentifier("original.read-summary")
            }
            HStack {
                Text("原谱跟弹 · \(document.numerator)/\(document.denominator)").font(.caption)
                Spacer()
                Text("第 \((document.rows.firstIndex(where: { $0.id == runtime.run.row.id }) ?? 0) + 1) 行 · \(Int(runtime.run.elapsedSeconds)) 秒")
                    .font(.caption).monospacedDigit().accessibilityIdentifier("original.position")
            }
            Stepper(value: Binding(get: { runtime.run.bpm }, set: { runtime.setBPM($0) }), in: 40...200, step: 1) {
                Text("练习速度 · \(MetronomeMeter.beatUnitName(document.denominator)) = \(Int(runtime.run.bpm)) BPM").font(.callout.bold())
            }.accessibilityIdentifier("original.tempo")
            HStack(spacing: 10) {
                Button {
                    runtime.pause()
                    if let indices = try? document.indices(for: runtime.run.range) {
                        first = indices.lowerBound; last = indices.upperBound; ranges = true
                    }
                } label: {
                    Label(rangeTitle(runtime.run.range), systemImage: "line.3.horizontal.decrease")
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                }.buttonStyle(.bordered).accessibilityIdentifier("original.range")
                Button { runtime.play(preparing: true) } label: {
                    Label("3 秒准备", systemImage: "timer").frame(maxWidth: .infinity).padding(.vertical, 12)
                }.buttonStyle(.bordered).disabled(runtime.run.state == .playing || runtime.run.state == .preparing)
                    .accessibilityIdentifier("original.prepare")
            }
            HStack {
                Text(stateTitle(runtime.run.state)).font(.caption).accessibilityIdentifier("original.state")
                Spacer()
                Toggle("循环", isOn: Binding(get: { runtime.run.looping }, set: { runtime.setLooping($0) }))
                    .font(.caption).fixedSize().accessibilityIdentifier("original.loop")
            }
        }.padding(14).background(GitaTheme.bgSurface)
    }
    private var rangeSheet: some View {
        NavigationStack {
            Form {
                Picker("起始行", selection: $first) {
                    ForEach(document.rows.indices, id: \.self) { Text("第 \($0 + 1) 行").tag($0) }
                }
                Picker("结束行", selection: $last) {
                    ForEach(document.rows.indices, id: \.self) { Text("第 \($0 + 1) 行").tag($0) }
                }
                Button("全部谱行") { first = 0; last = document.rows.count - 1 }
                Button("确认范围") {
                    guard first <= last, document.rows.indices.contains(first), document.rows.indices.contains(last) else { return }
                    runtime?.setRange(.init(first: document.rows[first].id, last: document.rows[last].id)); ranges = false
                }.disabled(first > last).accessibilityIdentifier("original.confirm-range")
            }.navigationTitle("训练范围")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { ranges = false } } }
        }.presentationDetents([.medium])
    }
    private func rangeTitle(_ range: OriginalScoreRange) -> String {
        guard let indices = try? document.indices(for: range) else { return "选择训练范围" }
        if indices == document.rows.indices.lowerBound...document.rows.indices.upperBound - 1 { return "训练全部行" }
        return "训练 \(indices.lowerBound + 1)–\(indices.upperBound + 1) 行"
    }
    private func stateTitle(_ state: OriginalScoreRun.State) -> String {
        switch state { case .idle: "待机"; case .preparing: "准备中"; case .playing: "跟线弹奏中"; case .paused: "已暂停"; case .completed: "本轮已完成" }
    }
    private func load(rowStart: Bool? = nil) {
        guard runtime == nil else { return }
        do {
            pages = try OriginalScoreSources.pages(for: document, profileID: library.profileID).map {
                guard let image = UIImage(data: $0) else { throw OriginalScoreError.missingVersion }
                return image
            }
            runtime = try OriginalScoreRuntime(document: document, library: library, store: store, entry: entry,
                settings: settings, completed: router.completedPracticeItemIds, resumeAtRowStart: rowStart ?? resumeAtRowStart)
        } catch { self.error = error.localizedDescription }
    }
}

struct OriginalScoreHistoryView: View {
    let document: OriginalScoreDocument
    let record: OriginalScorePracticeRecord
    let profileID: UUID
    @State private var pages: [UIImage] = []
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(record.date.formatted()) · \(Int(record.seconds)) 秒 · \(Int(record.bpm)) BPM").font(.callout)
                Text("练习发生时的谱面版本").font(.caption).foregroundStyle(GitaTheme.textSecondary)
                if let error { Text(error).foregroundStyle(GitaTheme.statusError) }
                ForEach(pages.indices, id: \.self) { page in
                    OriginalScorePageView(image: pages[page], rows: document.rows.filter { $0.page == page }, numbers: document.rowNumbers)
                }
            }.padding(16)
        }.navigationTitle(document.title)
        .task {
            do {
                pages = try OriginalScoreSources.pages(for: document, profileID: profileID).map {
                    guard let image = UIImage(data: $0) else { throw OriginalScoreError.missingVersion }
                    return image
                }
            } catch { self.error = error.localizedDescription }
        }
    }
}
