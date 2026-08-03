//
//  PracticeDetailView.swift
//  foxgita
//

import SwiftData
import SwiftUI

struct PracticeDetailView: View {
    let taskId: String
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Query private var tasks: [TaskItem]

    @State private var metronome = MetronomeEngine()
    @State private var practiceTimer = PracticeTimer()
    @State private var recorder = AudioRecorderService()
    @State private var steps: [String] = []
    @State private var noteText = ""
    @State private var showNote = true
    @State private var toast: String?
    @State private var videoAlert = false

    private var task: TaskItem? { tasks.first { $0.id == taskId } }

    var body: some View {
        ZStack {
            PageBackground()
            if let task {
                VStack(spacing: 0) {
                    HStack {
                        Button("返回") {
                            practiceTimer.pause(); metronome.stop()
                            router.practicePath.removeAll()
                        }
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
                    .frame(height: 56)
                    .padding(.horizontal, 16)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text(task.subtitle)
                                Spacer()
                                Text(task.timeSig)
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(GitaTheme.textSecondary)

                            // Metronome card
                            VStack(spacing: 14) {
                                HStack {
                                    Text("节拍器").font(.system(size: 18, weight: .bold))
                                    Spacer()
                                    Text("木质短音")
                                        .font(.system(size: 12))
                                        .foregroundStyle(GitaTheme.textSecondary)
                                }
                                HStack {
                                    circleBtn("－") { metronome.bump(-5) }
                                    VStack(spacing: 0) {
                                        Text("\(metronome.bpm)")
                                            .font(.system(size: 24, weight: .medium))
                                        Text("BPM")
                                            .font(.system(size: 12))
                                            .foregroundStyle(GitaTheme.textSecondary)
                                    }
                                    .frame(width: 100)
                                    circleBtn("＋", accent: true) { metronome.bump(5) }
                                }
                            }
                            .padding(18)
                            .background(GitaTheme.bgSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .shadow(color: GitaTheme.shadowCard, radius: 8, y: 4)

                            // Timer
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(practiceTimer.display)
                                        .font(.system(size: 24, weight: .medium).monospacedDigit())
                                    Text("目标 \(task.targetMin):00")
                                        .font(.system(size: 12))
                                        .foregroundStyle(GitaTheme.textSecondary)
                                }
                                Spacer()
                                Button("RESET") {
                                    practiceTimer.reset(); metronome.stop()
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(GitaTheme.textSecondary)
                                .padding(.horizontal, 12)
                                .frame(height: 38)
                                .background(GitaTheme.bgSubtle)
                                .clipShape(Capsule())

                                Button(practiceTimer.isRunning ? "暂停" : "开始") {
                                    togglePlay()
                                }
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(GitaTheme.brandOn)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 11)
                                .background(GitaTheme.brand500)
                                .clipShape(Capsule())
                            }
                            .padding(16)
                            .frame(height: 100)
                            .background(GitaTheme.bgSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .shadow(color: GitaTheme.shadowCard, radius: 8, y: 4)

                            // Steps
                            VStack(alignment: .leading, spacing: 0) {
                                HStack {
                                    Text("练习步骤").font(.system(size: 18, weight: .bold))
                                    Spacer()
                                    Button("新增步骤") { steps.append("新步骤") }
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(GitaTheme.brand500)
                                }
                                .padding(.bottom, 8)
                                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                                    HStack(spacing: 10) {
                                        Text("\(i + 1)")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(GitaTheme.brand500)
                                            .frame(width: 28, height: 28)
                                            .background(GitaTheme.brand50)
                                            .clipShape(Circle())
                                        TextField("步骤", text: binding(i))
                                            .font(.system(size: 14))
                                        if steps.count > 1 {
                                            Button("删除") { steps.remove(at: i) }
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

                            // Tools
                            HStack(spacing: 10) {
                                tool("录音", on: recorder.isRecording) {
                                    Task {
                                        if recorder.isRecording {
                                            recorder.stop(label: task.title)
                                        } else {
                                            showNote = false
                                            await recorder.start(label: task.title)
                                        }
                                    }
                                }
                                tool("写笔记", on: showNote) { showNote = true }
                                tool("录视频", on: false) {
                                    if router.role == .vip {
                                        toast = "已开始录视频（演示）"
                                    } else {
                                        toast = "坚持练习解锁录视频，先用录音记下今天"
                                    }
                                    hideToastLater()
                                }
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

                            if !recorder.pending.isEmpty {
                                Text("本次已录 \(recorder.pending.count) 段")
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
            steps = task.steps.isEmpty ? ["新步骤"] : task.steps
        }
        .onDisappear {
            practiceTimer.pause(); metronome.stop()
            if recorder.isRecording { recorder.stop() }
        }
        .onChange(of: recorder.lastError) { _, v in
            if let v { toast = v; hideToastLater() }
        }
    }

    private func circleBtn(_ title: String, accent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(accent ? GitaTheme.brand500 : GitaTheme.textSecondary)
                .frame(width: 48, height: 48)
                .background(accent ? GitaTheme.brand50 : GitaTheme.bgSubtle)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func tool(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(on ? GitaTheme.brand500 : GitaTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(GitaTheme.bgSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(on ? GitaTheme.brand500 : Color.clear, lineWidth: 1.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: GitaTheme.shadowCard, radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func binding(_ i: Int) -> Binding<String> {
        Binding(
            get: { i < steps.count ? steps[i] : "" },
            set: { if i < steps.count { steps[i] = $0 } }
        )
    }

    private func togglePlay() {
        if practiceTimer.isRunning {
            practiceTimer.pause(); metronome.stop()
        } else {
            practiceTimer.start(); metronome.start()
        }
    }

    private func complete(_ task: TaskItem) {
        if recorder.isRecording { recorder.stop(label: task.title) }
        practiceTimer.pause(); metronome.stop()
        task.steps = steps
        let end = Date()
        let elapsed = practiceTimer.elapsedSec
        let start = practiceTimer.startedAt ?? end.addingTimeInterval(TimeInterval(-elapsed))
        let session = PracticeSession(
            taskId: task.id, taskTitle: task.title, category: task.category,
            startedAt: start, endedAt: end, durationSec: max(0, elapsed),
            bpm: metronome.bpm, timeSig: task.timeSig, steps: steps, noteText: noteText
        )
        for p in recorder.consume() {
            session.recordings.append(
                RecordingRef(id: p.id, fileName: p.fileName, bytes: p.bytes, createdAt: p.createdAt, label: p.label)
            )
        }
        modelContext.insert(session)
        try? modelContext.save()
        router.practicePath.removeAll()
        router.selectedTab = .record
    }

    private func hideToastLater() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { toast = nil }
    }
}
