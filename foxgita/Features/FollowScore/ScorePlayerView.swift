import SwiftUI

struct ScorePrimaryStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(GitaFont.callout(.bold)).foregroundStyle(GitaTheme.textOnPrimary)
            .frame(maxWidth: .infinity,minHeight: 44)
            .background(GitaTheme.brand500.opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.4),in: Capsule())
    }
}

struct ScorePlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var model: ScoreRuntimeModel
    @State private var range: ScoreRange
    @State private var showPause = false
    @State private var showSettings = false
    @State private var showPassage = false
    @State private var showDifficulties = false
    @State private var showTuner = false

    init(model: ScoreRuntimeModel) {
        _model = State(initialValue: model)
        _range = State(initialValue: model.run.range)
    }
    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            VStack(spacing: landscape ? 8 : 16) {
                header(landscape: landscape)
                lyrics
                ScoreMovingCanvas(score: model.run.score,timeline: model.run.timeline,clock: model.visualClock,range: range,notation: model.notation,showChords: model.showChords)
                    .frame(minHeight: landscape ? 120 : 200,maxHeight: .infinity)
                feedback
                controls
            }
            .padding(.horizontal,landscape ? 24 : 16).padding(.vertical,landscape ? 8 : 16)
            .frame(maxWidth: 1_200).frame(maxWidth: .infinity,maxHeight: .infinity)
            .background(GitaTheme.bgDefault.ignoresSafeArea())
            .overlay { if showPause { pausePanel } }
        }
        .toolbar(.hidden,for: .navigationBar).toolbar(.hidden,for: .tabBar)
        .interactiveDismissDisabled()
        .sheet(isPresented: $showSettings) { settings }
        .sheet(isPresented: $showPassage) {
            NavigationStack { ScorePassageEditor(library: model.library,versionID: model.run.score.versionID,range: range,speed: model.run.speed) }
        }
        .sheet(isPresented: $showDifficulties) {
            NavigationStack {
                ScorePassageList(library: model.library,score: model.run.score) { passage in
                    showDifficulties = false
                    range = passage.range
                    model.configure(range: passage.range,speed: passage.speed,loops: passage.loops)
                }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { showDifficulties = false } } }
            }
        }
        .sheet(isPresented: $showTuner) { TunerView() }
        .alert("提示",isPresented: Binding(get: { model.message != nil },set: { if !$0 { model.message = nil } })) {
            Button("重试保存") { model.persist() }
            Button("知道了",role: .cancel) { model.message = nil }
        } message: { Text(model.message ?? "") }
        .onChange(of: phase) { _, value in if value != .active { model.pause(reason: "已保存进度，点击继续跟练") } }
        .onChange(of: range) { _, _ in
            if model.run.state == .playing || model.run.state == .countingIn { model.pause() }
        }
        .onChange(of: model.run.state) { _, state in if state == .finished { showPause = true } }
        .onDisappear { model.close(); ScoreOrientation.setWorkspaceVisible(false) }
        .task { ScoreOrientation.setWorkspaceVisible(true); await model.start() }
        .accessibilityIdentifier("score.player")
    }

    @ViewBuilder private func header(landscape: Bool) -> some View {
        HStack(spacing: 12) {
            Button { model.pause(); showPause = true } label: { Image(systemName: "chevron.left").frame(width: 36,height: 36) }.accessibilityLabel("暂停并返回")
            VStack(alignment: .leading,spacing: 2) {
                Text(model.run.score.title).font(GitaFont.headline()).lineLimit(1)
                Text(model.run.score.composer).font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary).lineLimit(1)
            }
            if landscape {
                Picker("模式",selection: Binding(get: { model.run.mode },set: { model.changeMode($0) })) {
                    ForEach(ScoreRunMode.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).frame(maxWidth: 160)
            }
            Spacer(minLength: 4)
            Button("我的难点") { model.pause(); showDifficulties = true }.font(GitaFont.callout(.bold))
            if landscape {
                Button { model.rewind() } label: { Image(systemName: "arrow.counterclockwise").frame(width: 36,height: 36) }.accessibilityLabel("从头重练")
            }
            Button { model.pause(); showSettings = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 36,height: 36) }.accessibilityLabel("跟谱设置")
        }.foregroundStyle(GitaTheme.textPrimary)
    }
    private var lyrics: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading,spacing: 4) {
                Text(model.run.mode.title).font(GitaFont.caption(.bold)).foregroundStyle(GitaTheme.brand500)
                Text("第\(model.run.timeline.barIndex(atTick: model.run.tick)+1)小节 · \(model.run.completedLoops)/\(model.run.loopLimit.map(String.init) ?? "∞")次循环")
                    .font(GitaFont.micro()).foregroundStyle(GitaTheme.textSecondary)
                Text("\(Int((currentTempo.bpm*model.run.speed).rounded())) BPM · \(currentTempo.beatUnit)分音符").font(GitaFont.micro()).foregroundStyle(GitaTheme.textSecondary)
            }
            Spacer(minLength: 4)
            if model.showLyrics {
                Text(currentLyric ?? "本曲谱没有歌词").font(GitaFont.callout(.bold)).foregroundStyle(currentLyric == nil ? GitaTheme.textSecondary : GitaTheme.textPrimary)
                    .lineLimit(2).frame(maxWidth: .infinity)
            }
            VStack(alignment: .trailing,spacing: 4) {
                Text(model.listening ? "● 本地听弹中" : "收音未开启").font(GitaFont.micro()).foregroundStyle(model.listening ? GitaTheme.statusSuccess : GitaTheme.textSecondary)
                if model.run.state == .countingIn { Text("预备 \(Int(model.run.countInRemaining.rounded(.up)))秒").font(GitaFont.micro()) }
            }
        }
        .padding(.horizontal,16).padding(.vertical,10).frame(minHeight: 60)
        .background(GitaTheme.bgSurface,in: RoundedRectangle(cornerRadius: 16))
    }
    private var currentLyric: String? {
        model.run.timeline.lyric(atTick: model.run.tick)
    }
    private var currentTempo: ScoreTempo {
        model.run.timeline.tempo(atTick: model.run.tick)
    }
    private var feedback: some View {
        HStack {
            Text(model.feedback).font(GitaFont.caption()).lineLimit(1)
            Spacer()
            if let score = model.grade.totalScore { Text("\(score)分 · 已判定\(Int(model.grade.coverage*100))%").font(GitaFont.caption(.bold)) }
        }.foregroundStyle(GitaTheme.textSecondary)
    }
    private var controls: some View {
        VStack(spacing: 6) {
            ScoreMovingOverview(score: model.run.score,timeline: model.run.timeline,clock: model.visualClock,range: $range) { model.seek(toBar: $0) }
            HStack(spacing: 12) {
                Button { togglePlayback() } label: {
                    Label(isPlaying ? "暂停" : "开始",systemImage: isPlaying ? "pause.fill" : "play.fill")
                }.buttonStyle(ScorePrimaryStyle()).frame(maxWidth: 120).disabled(model.isStarting)
                Text(time(model.run.elapsedSeconds)).font(GitaFont.callout()).monospacedDigit()
                Spacer(minLength: 0)
                Text("\(Int(model.run.speed*100))%").font(GitaFont.callout(.bold))
                if range != model.run.range {
                    Button("应用 A–B") { model.configure(range: range,speed: model.run.speed,loops: model.run.loopLimit) }.font(GitaFont.callout(.bold))
                } else {
                    Button { model.pause(); showPassage = true } label: { Label("标记难点",systemImage: "flag") }.font(GitaFont.callout(.bold))
                }
            }
        }
    }
    private var isPlaying: Bool { model.run.state == .playing || model.run.state == .countingIn }
    private func togglePlayback() {
        if isPlaying { model.pause(); showPause = true }
        else { Task { await model.start() } }
    }
    private func time(_ value: Double) -> String { String(format: "%02d:%02d",Int(value)/60,Int(value)%60) }
    private var pausePanel: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(alignment: .leading,spacing: 16) {
                Text(model.run.state == .finished ? "本轮练习已结束" : "暂停跟练").font(GitaFont.title())
                Text("本次已练 \(time(model.run.elapsedSeconds)) · 第\(range.firstBar+1)–\(range.lastBar+1)小节")
                    .font(GitaFont.callout()).foregroundStyle(GitaTheme.textSecondary)
                if let score = model.grade.totalScore {
                    HStack { Text("\(score)分").font(GitaFont.largeTitle()).foregroundStyle(GitaTheme.brand500); Spacer(); Text("音高\(Int((model.grade.pitchAccuracy ?? 0)*100))% · 节奏\(Int((model.grade.rhythmAccuracy ?? 0)*100))%").font(GitaFont.caption()) }
                } else { Text("当前可判定内容不足，暂不生成总分。").font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary) }
                Button("继续跟练") { showPause = false; Task { await model.start() } }.buttonStyle(ScorePrimaryStyle())
                Button("保存并结束") { model.close(); if model.lastSaveSucceeded { dismiss() } }.font(GitaFont.callout(.bold)).frame(maxWidth: .infinity,minHeight: 44)
                    .background(GitaTheme.bgSubtle,in: Capsule())
            }.padding(24).frame(maxWidth: 430).background(GitaTheme.bgSurface,in: RoundedRectangle(cornerRadius: 24)).padding(20)
        }
    }
    private var settings: some View {
        NavigationStack {
            Form {
                Section("跟练") {
                    Picker("模式",selection: Binding(get: { model.run.mode },set: { model.changeMode($0) })) { ForEach(ScoreRunMode.allCases) { Text($0.title).tag($0) } }
                    Picker("谱面",selection: $model.notation) { ForEach(ScoreNotation.allCases) { Text($0.title).tag($0) } }
                    Toggle("显示歌词",isOn: $model.showLyrics)
                    Toggle("显示和弦",isOn: $model.showChords)
                    Button("从头重练") { model.rewind(); showSettings = false }
                }
                Section("速度与循环") {
                    ForEach([0.5,0.75,1.0],id: \.self) { speed in
                        Button("\(Int(speed*100))% 速度") { model.configure(range: range,speed: speed,loops: model.run.loopLimit); showSettings = false }
                            .disabled(model.run.mode == .performance)
                    }
                    Button("循环5次") { model.configure(range: range,speed: model.run.speed,loops: 5); showSettings = false }.disabled(model.run.mode == .performance)
                    Button("持续循环") { model.configure(range: range,speed: model.run.speed,loops: nil); showSettings = false }.disabled(model.run.mode == .performance)
                }
                Section("音频") {
                    Text("有声跟练请连接耳机。外放时不评分；关闭示范音与节拍器后，可单独收吉他声。").font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
                    LabeledContent("示范音") { Slider(value: $model.demoVolume,in: 0...1).frame(maxWidth: 180) }
                    LabeledContent("节拍器") { Slider(value: $model.clickVolume,in: 0...1).frame(maxWidth: 180) }
                    Button("调音器") { showSettings = false; showTuner = true }
                }
            }.navigationTitle("跟谱设置").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showSettings = false } } }
        }
    }
}

struct ScorePassageEditor: View {
    @Environment(\.dismiss) private var dismiss
    let library: ScoreLibrary
    @State private var passage: ScorePassage
    @State private var error: String?
    init(library: ScoreLibrary,versionID: UUID,range: ScoreRange,speed: Double,existing: ScorePassage? = nil) {
        self.library = library
        _passage = State(initialValue: existing ?? .init(versionID: versionID,title: "第\(range.firstBar+1)–\(range.lastBar+1)小节",range: range,speed: speed))
    }
    private var count: Int { library.score(versionID: passage.versionID)?.bars.count ?? 1 }
    var body: some View {
        Form {
            Section("难点名称") { TextField("例如：A5换弦",text: $passage.title) }
            Section("练习范围") {
                Stepper("A：第\(passage.range.firstBar+1)小节",value: $passage.range.firstBar,in: 0...max(0,passage.range.lastBar))
                Stepper("B：第\(passage.range.lastBar+1)小节",value: $passage.range.lastBar,in: passage.range.firstBar...max(passage.range.firstBar,count-1))
            }
            Section("练法") {
                HStack { Text("练习速度"); Slider(value: $passage.speed,in: 0.25...1.5,step: 0.05); Text("\(Int(passage.speed*100))%") }
                Stepper("循环\(passage.loops)次",value: $passage.loops,in: 1...99)
                Picker("状态",selection: $passage.status) { ForEach(ScorePassageStatus.allCases) { Text($0.title).tag($0) } }
            }
            Section("练习备注") { TextField("需要注意什么",text: $passage.note,axis: .vertical).lineLimit(3...5) }
            if let error { Text(error).foregroundStyle(GitaTheme.statusError) }
            Text("保存在这首曲谱中，下次可以直接开始专项练习。").font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
        }.navigationTitle("保存难点").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { do { passage.updatedAt = Date(); try library.save(passage: passage); dismiss() } catch { self.error = error.localizedDescription } } }
            }
    }
}

struct ScorePassageList: View {
    let library: ScoreLibrary
    let score: ScoreDocument
    var onSelect: (ScorePassage) -> Void
    @State private var editing: ScorePassage?
    @State private var showMastered = false
    @State private var error: String?
    private var passages: [ScorePassage] { library.passages.filter { $0.versionID == score.versionID && (showMastered || $0.status != .mastered) } }
    var body: some View {
        List {
            if passages.isEmpty { ContentUnavailableView("还没有难点",systemImage: "flag",description: Text("在跟谱工作台圈选 A–B，标记需要反复练的片段。")) }
            ForEach(passages) { passage in
                VStack(alignment: .leading,spacing: 8) {
                    HStack { Text(passage.title).font(GitaFont.headline()); Spacer(); Text(passage.status.title).font(GitaFont.caption()).foregroundStyle(GitaTheme.brand500) }
                    Text("第\(passage.range.firstBar+1)–\(passage.range.lastBar+1)小节 · \(Int(passage.speed*100))%速度 · 循环\(passage.loops)次").font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
                    if !passage.note.isEmpty { Text(passage.note).font(GitaFont.callout()) }
                    Button("开始专项练习") { onSelect(passage) }.buttonStyle(ScorePrimaryStyle())
                    Button("编辑难点") { editing = passage }.font(GitaFont.caption())
                }.padding(.vertical,8)
                .swipeActions { Button("删除",role: .destructive) { do { try library.deletePassage(passage.id) } catch { self.error = error.localizedDescription } } }
            }
            Toggle("显示已掌握片段",isOn: $showMastered)
            if let error { Text(error).foregroundStyle(GitaTheme.statusError) }
        }.navigationTitle("我的难点")
            .sheet(item: $editing) { passage in NavigationStack { ScorePassageEditor(library: library,versionID: score.versionID,range: passage.range,speed: passage.speed,existing: passage) } }
    }
}
