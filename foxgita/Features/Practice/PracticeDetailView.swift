//
//  PracticeDetailView.swift
//  foxgita
//

import SwiftData
import SwiftUI

struct PracticeDetailView: View {
    let taskId: String
    @Environment(AppRouter.self) private var router
    @Environment(PracticeStore.self) private var store
    @Query private var tasks: [TaskItem]

    @State private var metronome = MetronomeEngine()
    @State private var practiceTimer = PracticeTimer()
    @State private var recorder = AudioRecorderService()
    @State private var video = VideoRecorderService()
    @State private var steps: [String] = []
    @State private var noteText = ""
    @State private var showNote = true
    @State private var toast: String?
    @State private var confirmExit = false
    @State private var isCompleting = false

    init(taskId: String) {
        self.taskId = taskId
        _tasks = Query(filter: #Predicate<TaskItem> { $0.id == taskId && $0.deletedAt == nil })
    }

    private var task: TaskItem? { tasks.first }

    /// Anything worth losing a confirmation tap over.
    private var hasUnsavedWork: Bool {
        practiceTimer.elapsedSec > 0
            || !recorder.pending.isEmpty
            || !video.pending.isEmpty
            || !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            PageBackground()
            if let task {
                content(task)
            } else {
                Text("任务不存在").foregroundStyle(GitaTheme.textSecondary)
            }

            if let toast {
                VStack {
                    Spacer()
                    ToastBanner(text: toast).padding(.bottom, 40)
                }
            }
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            guard let task else { return }
            metronome.setBpm(task.defaultBpm)
            steps = task.steps.isEmpty ? [String(localized: "新步骤")] : task.steps
            AudioSessionCoordinator.shared.onInterruption = { [metronome, practiceTimer, recorder] in
                metronome.stop()
                practiceTimer.pause()
                if recorder.isRecording { recorder.stop() }
            }
        }
        .onDisappear {
            AudioSessionCoordinator.shared.onInterruption = nil
            practiceTimer.pause()
            metronome.stop()
            if recorder.isRecording { recorder.stop() }
            // Takes never attached to a session would otherwise linger on disk.
            recorder.discardPending()
            for clip in video.takeAll() {
                RecordingStore.delete(fileName: clip.fileName)
            }
        }
        .onChange(of: recorder.lastError) { _, value in
            if let value { show(value) }
        }
        .onChange(of: video.lastError) { _, value in
            if let value { show(value) }
        }
        .onChange(of: store.lastError) { _, value in
            if let value { show(value.localizedDescription) }
        }
        .fullScreenCover(isPresented: Binding(
            get: { video.isPresenting },
            set: { if !$0 { video.dismiss() } }
        )) {
            VideoCameraPicker(
                isPresented: Binding(
                    get: { video.isPresenting },
                    set: { if !$0 { video.dismiss() } }
                ),
                onPicked: { url in
                    video.ingest(tempURL: url, label: task?.title ?? "")
                },
                onCancel: { video.dismiss() }
            )
            .ignoresSafeArea()
        }
        .confirmationDialog(
            "这次练习还没保存", isPresented: $confirmExit, titleVisibility: .visible
        ) {
            Button("放弃并返回", role: .destructive) { leave() }
            Button("继续练习", role: .cancel) {}
        } message: {
            Text("返回会丢掉本次计时、录音和笔记。")
        }
    }

    @ViewBuilder
    private func content(_ task: TaskItem) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button("返回") { requestExit() }
                    .font(.system(size: 14))
                    .foregroundStyle(GitaTheme.textSecondary)
                    .frame(minWidth: 40, alignment: .leading)
                Text(task.title)
                    .font(.system(size: 20, weight: .bold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                Button("完成") { complete(task) }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GitaTheme.brand500)
                    .frame(minWidth: 40, alignment: .trailing)
            }
            .frame(minHeight: 56)
            .padding(.horizontal, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if AIPracticePresentation.isAIGenerated(subtitle: task.subtitle) {
                        HStack {
                            let chords = AIPracticePresentation.chords(fromSubtitle: task.subtitle)
                            if !chords.isEmpty {
                                Text("识别：\(chords.joined(separator: " · "))")
                            }
                            Spacer()
                            Text("目标 \(task.targetMin) 分钟")
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(GitaTheme.textSecondary)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("已从图片生成")
                                .font(.system(size: 14, weight: .semibold))
                            Text("识别出 \(task.steps.count) 个步骤，可直接修改")
                                .font(.system(size: 12))
                                .foregroundStyle(GitaTheme.textSecondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(GitaTheme.bgSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else {
                        HStack {
                            Text(task.subtitle)
                            Spacer()
                            Text(task.timeSig)
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(GitaTheme.textSecondary)
                    }

                    metronomeCard
                    timerCard(task)
                    stepsCard
                    toolsRow(task)

                    if recorder.isRecording {
                        recordingActivePanel(task)
                    }

                    if showNote {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("记录一点感受…", text: $noteText, axis: .vertical)
                                .font(.system(size: 14))
                                .lineLimit(3...6)
                            Text("记录一点感受，下次继续从这里开始")
                                .font(.system(size: 12))
                                .foregroundStyle(GitaTheme.textSecondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(GitaTheme.bgSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    let clipCount = recorder.pending.count + video.pending.count
                    if clipCount > 0 {
                        Text("本次已录 \(clipCount) 段")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(GitaTheme.brand500)
                    }

                    Button { complete(task) } label: {
                        Text("完成本次练习")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(GitaTheme.brandOn)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(GitaTheme.brand500)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
    }

    private var metronomeCard: some View {
        VStack(spacing: 14) {
            HStack {
                Text("节拍器").font(GitaFont.headline())
                Spacer()
                Text("木质短音")
                    .font(GitaFont.caption())
                    .foregroundStyle(GitaTheme.textSecondary)
            }
            HStack {
                circleBtn("－", label: String(localized: "降低 5 BPM")) { metronome.bump(-5) }
                VStack(spacing: 0) {
                    Text("\(metronome.bpm)")
                        .font(GitaFont.timer())
                    Text("BPM")
                        .font(GitaFont.caption())
                        .foregroundStyle(GitaTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("当前速度 \(metronome.bpm) BPM"))
                circleBtn("＋", label: String(localized: "提高 5 BPM"), accent: true) {
                    metronome.bump(5)
                }
            }
        }
        .padding(18)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: GitaTheme.shadowCard, radius: 8, y: 4)
    }

    private func timerCard(_ task: TaskItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(practiceTimer.display)
                    .font(GitaFont.timer())
                Text("目标 \(task.targetMin):00")
                    .font(GitaFont.caption())
                    .foregroundStyle(GitaTheme.textSecondary)
            }
            Spacer()
            Button("RESET") {
                practiceTimer.reset()
                metronome.stop()
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(GitaTheme.textSecondary)
            .padding(.horizontal, 12)
            .frame(minHeight: 38)
            .background(GitaTheme.bgSubtle)
            .clipShape(Capsule())

            Button(practiceTimer.isRunning ? "暂停" : "开始") { togglePlay() }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GitaTheme.brandOn)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(GitaTheme.brand500)
                .clipShape(Capsule())
        }
        .padding(16)
        .frame(minHeight: 100)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: GitaTheme.shadowCard, radius: 8, y: 4)
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("练习步骤").font(.system(size: 18, weight: .bold))
                Spacer()
                Button("新增步骤") { steps.append(String(localized: "新步骤")) }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GitaTheme.brand500)
            }
            .padding(.bottom, 8)
            ForEach(Array(steps.enumerated()), id: \.offset) { index, _ in
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(GitaTheme.brand500)
                        .frame(minWidth: 28, minHeight: 28)
                        .background(GitaTheme.brand50)
                        .clipShape(Circle())
                    TextField("步骤", text: binding(index))
                        .font(.system(size: 14))
                    if let minutes = AIPracticePresentation.stepParts(steps[index]).minutes {
                        Text("\(minutes) 分钟")
                            .font(.system(size: 12))
                            .foregroundStyle(GitaTheme.textSecondary)
                    }
                    if steps.count > 1 {
                        Button("删除") { steps.remove(at: index) }
                            .font(.system(size: 12))
                            .foregroundStyle(GitaTheme.textTertiary)
                    }
                }
                .padding(.vertical, 10)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func toolsRow(_ task: TaskItem) -> some View {
        HStack(spacing: 10) {
            tool(
                title: recorder.isRecording ? String(localized: "录音中") : String(localized: "录音"),
                systemImage: recorder.isRecording ? "mic.fill" : "mic",
                on: recorder.isRecording
            ) {
                Task {
                    if recorder.isRecording {
                        recorder.stop(label: task.title)
                    } else {
                        showNote = false
                        await recorder.start(label: task.title)
                    }
                }
            }
            tool(title: String(localized: "写笔记"), systemImage: "square.and.pencil", on: showNote) {
                showNote = true
            }
            tool(
                title: String(localized: "录视频"),
                systemImage: "video.fill",
                on: !video.pending.isEmpty
            ) {
                if recorder.isRecording { recorder.stop(label: task.title) }
                video.presentCamera()
            }
        }
    }

    private func recordingActivePanel(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(GitaTheme.statusError)
                    .frame(width: 8, height: 8)
                    .opacity(recorder.isPaused ? 0.35 : 1)
                Text(recorder.isPaused ? "已暂停" : "正在录音")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GitaTheme.textPrimary)
                Spacer()
                Text(recorder.elapsedDisplay)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(GitaTheme.statusError)
            }

            HStack(spacing: 3) {
                ForEach(0..<24, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(GitaTheme.statusError.opacity(recorder.isPaused ? 0.25 : 0.55))
                        .frame(width: 3, height: waveHeight(index))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 28)

            HStack(spacing: 10) {
                Button {
                    if recorder.isPaused { recorder.resume() } else { recorder.pause() }
                } label: {
                    Text(recorder.isPaused ? "继续" : "暂停")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GitaTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 40)
                        .background(GitaTheme.bgSurface)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    recorder.stop(label: task.title)
                } label: {
                    Text("停止")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GitaTheme.brandOn)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 40)
                        .background(GitaTheme.statusError)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(GitaTheme.brand50)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(GitaTheme.statusError.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("正在录音 \(recorder.elapsedDisplay)"))
    }

    private func waveHeight(_ index: Int) -> CGFloat {
        let pattern: [CGFloat] = [8, 14, 20, 12, 22, 10, 18, 14]
        let base = pattern[index % pattern.count]
        return recorder.isPaused ? max(6, base * 0.45) : base
    }

    private func circleBtn(
        _ title: String, label: String, accent: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(accent ? GitaTheme.brand500 : GitaTheme.textSecondary)
                .frame(minWidth: 48, minHeight: 48)
                .background(accent ? GitaTheme.brand50 : GitaTheme.bgSubtle)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    private func tool(
        title: String, systemImage: String, on: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(on ? GitaTheme.brand500 : GitaTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .background(GitaTheme.bgSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(on ? GitaTheme.brand500 : Color.clear, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: GitaTheme.shadowCard, radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    private func binding(_ index: Int) -> Binding<String> {
        Binding(
            get: { index < steps.count ? steps[index] : "" },
            set: { if index < steps.count { steps[index] = $0 } }
        )
    }

    private func togglePlay() {
        if practiceTimer.isRunning {
            practiceTimer.pause()
            metronome.stop()
        } else {
            practiceTimer.start()
            metronome.start()
        }
    }

    private func requestExit() {
        practiceTimer.pause()
        metronome.stop()
        if hasUnsavedWork {
            confirmExit = true
        } else {
            leave()
        }
    }

    private func leave() {
        router.practicePath.removeAll()
    }

    private func complete(_ task: TaskItem) {
        guard !isCompleting else { return }
        isCompleting = true

        if recorder.isRecording { recorder.stop(label: task.title) }
        practiceTimer.pause()
        metronome.stop()

        if !hasUnsavedWork {
            router.practiceToast = String(localized: "这次没有留下记录")
            router.returnPracticeToToday = true
            router.practicePath.removeAll()
            return
        }

        var clips = recorder.consume()
        clips += video.takeAll().map {
            AudioRecorderService.Clip(
                id: $0.id,
                fileName: $0.fileName,
                bytes: $0.bytes,
                durationSec: $0.durationSec,
                createdAt: $0.createdAt,
                label: $0.label
            )
        }

        let end = Date()
        let elapsed = practiceTimer.elapsedSec
        let saved = store.finishSession(
            taskId: task.id,
            steps: steps,
            note: noteText,
            startedAt: practiceTimer.startedAt ?? end.addingTimeInterval(TimeInterval(-elapsed)),
            endedAt: end,
            durationSec: elapsed,
            bpm: metronome.bpm,
            recordings: clips
        )
        guard saved else {
            isCompleting = false
            return
        }
        Haptics.success()
        router.returnPracticeToToday = true
        router.practicePath.removeAll()
    }

    private func show(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toast == message { toast = nil }
        }
    }
}
