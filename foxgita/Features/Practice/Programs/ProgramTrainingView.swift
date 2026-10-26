import SwiftData
import SwiftUI

struct ProgramTrainingView: View {
    @Environment(PracticePrograms.self) private var programs
    @Environment(PracticeStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<PracticeItem> { $0.deletedAt == nil }) private var items: [PracticeItem]
    let onClose: () -> Void

    private var snapshots: [PracticeItemSnapshot] {
        items.filter { $0.profileId == programs.profileID }.map(PracticeStore.snapshot(from:))
    }

    var body: some View {
        ScrollView {
            if let training = programs.currentTraining {
                VStack(alignment: .leading, spacing: 24) {
                    Text(training.name).font(.title.bold())
                    Text(training.entry.label).foregroundStyle(.secondary)
                    if training.ended {
                        ProgramTrainingSummary(training: training, snapshots: snapshots)
                        TextField("给这次练习留一句话", text: Binding(
                            get: { programs.currentTraining?.note ?? "" }, set: { programs.saveNote($0) }
                        ), axis: .vertical)
                        Button("查看练习记录") {
                            onClose()
                            router.selectedTab = .record
                        }.buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("program.records")
                    } else if training.index < training.stages.count {
                        let stage = training.stages[training.index]
                        Text("第 \(training.index + 1) / \(training.stages.count) 段").foregroundStyle(GitaTheme.brand500)
                        Text(stage.exercise.title).font(.title2.bold())
                        Text(stage.exercise.subtitle)
                        Text("本段目标 \(stage.exercise.minutes) 分钟")
                        let seconds = ProgramTraining.seconds(for: stage, in: snapshots) + programs.timer.elapsedSec
                        Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                            .font(.system(size: 54, weight: .bold, design: .rounded)).monospacedDigit()
                            .accessibilityIdentifier("program.elapsed")
                        Text("已练时长 · 暂停期间不计时").foregroundStyle(.secondary)
                        Button(programs.timer.isRunning ? "暂停训练" : "继续当前训练") {
                            if programs.timer.isRunning { _ = programs.pause(store: store) }
                            else { _ = programs.resume(store: store) }
                        }.buttonStyle(.borderedProminent).accessibilityIdentifier("program.pause-resume")
                        Button("完成本段，继续") { programs.advance(skipping: false, store: store) }
                            .buttonStyle(.bordered).accessibilityIdentifier("program.complete-stage")
                        HStack {
                            Button("跳过本段") { programs.advance(skipping: true, store: store) }
                                .accessibilityIdentifier("program.skip-stage")
                            Spacer()
                            Button("提前结束", role: .destructive) { programs.end(store: store) }
                                .accessibilityIdentifier("program.end")
                        }
                        #if DEBUG
                        if programs.isUITesting {
                            Button("测试推进60秒") { programs.advanceTestClock(60) }.accessibilityIdentifier("program.test-minute")
                            Button("测试推进30秒") { programs.advanceTestClock(30) }.accessibilityIdentifier("program.test-half-minute")
                            Button("测试暂停五分钟") { programs.advanceTestClock(300) }.accessibilityIdentifier("program.test-five-minutes")
                            Button("测试推进本段目标") { programs.advanceTestClock(TimeInterval(stage.exercise.minutes * 60)) }.accessibilityIdentifier("program.test-stage-duration")
                            Button("测试推进到次日") { programs.advanceTestClock(86400) }.accessibilityIdentifier("program.test-next-day")
                        }
                        #endif
                    }
                    if let message = programs.message { Text(message).foregroundStyle(.red) }
                }
                .padding(24)
            }
        }
        .navigationTitle("练习")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("回到首页") { if programs.pause(store: store) { onClose() } }
                    .accessibilityIdentifier("program.training-home")
            }
        }
        .interactiveDismissDisabled()
        .onChange(of: scenePhase) { _, phase in
            // This flow has no background audio. Leaving it explicitly pauses
            // actual time; legacy detail playback keeps its existing contract.
            if phase != .active { _ = programs.pause(store: store) }
        }
    }
}

struct ProgramTrainingSummary: View {
    let training: ProgramTraining
    let snapshots: [PracticeItemSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(training.status).font(.headline)
            Text("完成 \(training.completedCount) / \(training.stages.count) 段").accessibilityIdentifier("program.summary-completed")
            Text("实练 \(training.seconds(in: snapshots)) 秒 · 明细聚合，不重复累计")
                .accessibilityIdentifier("program.summary-seconds")
            ForEach(training.stages) { stage in
                VStack(alignment: .leading, spacing: 6) {
                    Text(stage.exercise.title).bold()
                    Text(stage.exercise.subtitle).font(.footnote).foregroundStyle(.secondary)
                    Text(stage.result == .skipped ? "已跳过" : (stage.result == .completed ? "已完成" : "未完成"))
                    Text("实练 \(ProgramTraining.seconds(for: stage, in: snapshots)) 秒 · \(training.entry.label)")
                    ForEach(stage.dailyFacts) { ref in
                        if let item = snapshots.first(where: { $0.id == ref.itemID && !$0.isDeleted }) {
                            NavigationLink {
                                PracticeDetailView(itemId: item.id, allowPastDayEdits: true, openedFromRecord: true)
                            } label: {
                                Text("\(ref.day) · 查看实际练习明细")
                            }
                        }
                    }
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(GitaTheme.bgSurface, in: RoundedRectangle(cornerRadius: 16))
            }
            if !training.note.isEmpty { Text("复盘笔记：" + training.note) }
        }
    }
}

struct ProgramRecordSection: View {
    @Environment(PracticePrograms.self) private var programs
    @Environment(PracticeStore.self) private var store
    @State private var showingTraining = false
    let snapshots: [PracticeItemSnapshot]

    var body: some View {
        if !programs.trainings.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("方案与清单训练").font(.headline)
                ForEach(programs.trainings.reversed()) { training in
                    NavigationLink {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                ProgramTrainingSummary(training: training, snapshots: snapshots)
                                if !training.ended {
                                    Button("继续这次训练") {
                                        if programs.openTraining(training.id, store: store), programs.resume(store: store) {
                                            showingTraining = true
                                        }
                                    }.buttonStyle(.borderedProminent)
                                    .accessibilityIdentifier("program.resume-record")
                                }
                            }.padding()
                        }.navigationTitle("练习复盘")
                        .sheet(isPresented: $showingTraining) {
                            NavigationStack { ProgramTrainingView(onClose: { showingTraining = false }) }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(training.name).bold()
                            Text("\(training.status) · \(training.seconds(in: snapshots)) 秒")
                                .font(.footnote).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                            .background(GitaTheme.bgSurface, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .accessibilityIdentifier("program.record.\(training.id)")
                }
                Text("以下时间流按实际练习明细统计，汇总不另加时长。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
