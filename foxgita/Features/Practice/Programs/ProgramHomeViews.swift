import SwiftUI

private enum ProgramScreen: String, Identifiable {
    case preferences, editor, details, training
    var id: String { rawValue }
}

struct ProgramHero: View {
    @Environment(PracticePrograms.self) private var programs
    @Environment(PracticeStore.self) private var store
    let checkedDays: Set<String>
    @State private var screen: ProgramScreen?

    private var routine: PracticeRoutine { programs.savedRoutine ?? DNARecommendations.routine(for: nil) }
    private var paused: ProgramTraining? { programs.trainings.last { !$0.ended && $0.entry == .routine } }
    private var streak: Int {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: Date())
        if !checkedDays.contains(PracticeDayKey.make(from: day, calendar: calendar)) {
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        var result = 0
        while checkedDays.contains(PracticeDayKey.make(from: day, calendar: calendar)) {
            result += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return result
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("连续练习").font(.headline)
                HStack(alignment: .firstTextBaseline) {
                    Text("\(streak)").font(.system(size: 48, weight: .bold)).foregroundStyle(GitaTheme.brand500)
                    Text("天").foregroundStyle(.secondary)
                }
                Text("从今天开始积累").font(.caption).foregroundStyle(.secondary)
            }.frame(width: 100, alignment: .leading)
            Rectangle().fill(GitaTheme.brand500.opacity(0.15)).frame(width: 1)
            VStack(alignment: .leading, spacing: 10) {
                Text(programs.savedRoutine == nil ? "通用方案" : "已保存方案")
                    .font(.subheadline.bold()).foregroundStyle(GitaTheme.brand500)
                Button { screen = .details } label: {
                    HStack {
                        Text(routine.name).font(.headline).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                    }.foregroundStyle(GitaTheme.textPrimary)
                }.accessibilityIdentifier("program.details")
                Text("\(routine.minutes) 分钟 · \(routine.exercises.count) 个分段").font(.subheadline)
                HStack(spacing: 0) {
                    ForEach(Array(routine.exercises.enumerated()), id: \.element.id) { _, exercise in
                        exercise.category.accent.frame(maxWidth: .infinity).frame(height: 8)
                    }
                }.clipShape(Capsule())
                HStack {
                    Text(paused == nil ? (programs.savedRoutine == nil ? "完善偏好，找到自己的方向" : "按自己的方向练习") : "训练已暂停 · 可继续")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button {
                        if programs.beginRoutine(store: store) { screen = .training }
                    } label: {
                        Image(systemName: paused == nil ? "play.fill" : "play.circle.fill")
                            .foregroundStyle(GitaTheme.brand500).frame(width: 40, height: 40)
                            .background(.white, in: Circle())
                    }.accessibilityIdentifier("program.start-routine")
                }
            }
        }
        .padding(16)
        .background(LinearGradient(colors: [GitaTheme.bgSurface, GitaTheme.brand50], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 20))
        .fixedSize(horizontal: false, vertical: true)
        .sheet(item: $screen) { route in ProgramSheet(screen: route, close: { screen = nil }, change: { screen = $0 }) }
    }
}

struct ProgramRecommendationsView: View {
    @Environment(PracticePrograms.self) private var programs
    @Environment(PracticeStore.self) private var store
    let snapshots: [PracticeItemSnapshot]
    @State private var screen: ProgramScreen?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if programs.preferences == nil {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("根据偏好，找到适合你的练习").font(.subheadline.bold())
                        Text("补充信息，获取个性化推荐").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 6)
                    Button("补充信息") { screen = .preferences }
                        .buttonStyle(.bordered).accessibilityIdentifier("program.preferences")
                }
            } else {
                HStack {
                    Label("为你推荐", systemImage: "sparkles").font(.headline)
                    Spacer()
                    Button("调整偏好") { screen = .preferences }.accessibilityIdentifier("program.preferences")
                }
                Text("根据你的偏好 · 每次 \(programs.preferences?.minutes ?? 30) 分钟")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(programs.candidates) { exercise in
                    let existing = programs.candidateItem(exercise, snapshots: snapshots)
                    HStack {
                        Image(systemName: "music.note").foregroundStyle(exercise.category.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.title).font(.subheadline.bold())
                            Text("\(exercise.minutes) 分钟 · \(exercise.subtitle)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(existing == nil ? "添加" : "已添加") {
                            if let existing {
                                programs.focusedChecklistItemID = existing.id
                            } else {
                                _ = programs.addCandidate(exercise, store: store)
                            }
                        }.accessibilityIdentifier("program.add.\(exercise.id)")
                    }
                    if exercise.id != programs.candidates.last?.id { Divider() }
                }
            }
            if programs.routineDraft != nil {
                Button("查看待确认的新方案") { screen = .editor }.accessibilityIdentifier("program.draft")
                Text("当前首页方案保持原样，保存新方案后才替换。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message = programs.message { Text(message).font(.footnote).foregroundStyle(.red) }
        }
        .padding(16)
        .background(GitaTheme.brand50, in: RoundedRectangle(cornerRadius: 20))
        .sheet(item: $screen) { route in ProgramSheet(screen: route, close: { screen = nil }, change: { screen = $0 }) }
    }
}

struct ProgramChecklistButton: View {
    @Environment(PracticePrograms.self) private var programs
    @Environment(PracticeStore.self) private var store
    let snapshots: [PracticeItemSnapshot]
    @State private var showingTraining = false

    var body: some View {
        VStack(spacing: 6) {
            if let budget = programs.preferences?.minutes {
                let total = snapshots.reduce(0) { $0 + $1.targetMin }
                if total > budget {
                    Text("超出建议预算 \(total - budget) 分钟，仍可开始").font(.caption).foregroundStyle(GitaTheme.brand500)
                }
            }
            Button {
                showingTraining = programs.beginChecklist(snapshots, store: store)
            } label: {
                Text("开始今日练习").font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(GitaTheme.brandOn).frame(maxWidth: .infinity).frame(height: 54)
                    .background(GitaTheme.brand500, in: Capsule())
            }
            .accessibilityIdentifier("program.start-checklist")
        }
        .sheet(isPresented: $showingTraining) {
            NavigationStack { ProgramTrainingView(onClose: { showingTraining = false }) }
        }
    }
}

private struct ProgramSheet: View {
    @Environment(PracticePrograms.self) private var programs
    @Environment(PracticeStore.self) private var store
    let screen: ProgramScreen
    let close: () -> Void
    let change: (ProgramScreen) -> Void

    var body: some View {
        NavigationStack {
            switch screen {
            case .preferences:
                DNAPreferencesView(onSubmitted: { change(.editor) }, onClose: close)
            case .editor:
                if let draft = programs.routineDraft {
                    PracticeRoutineEditor(routine: draft, onSaved: close, onClose: close)
                }
            case .details:
                Form {
                    let routine = programs.savedRoutine ?? DNARecommendations.routine(for: nil)
                    Section(routine.name) {
                        Text("\(routine.minutes) 分钟 · \(routine.exercises.count) 个分段")
                        Text(programs.savedRoutine == nil ? "通用方案 · 尚未根据你的偏好生成" : "当前已保存方案")
                    }
                    ForEach(routine.exercises) { exercise in
                        Section(exercise.title) {
                            Text(exercise.subtitle)
                            Text("\(exercise.minutes) 分钟")
                            Text(exercise.reason).font(.footnote)
                        }
                    }
                    Button("按此方案开始训练") {
                        if programs.beginRoutine(store: store) { change(.training) }
                    }
                    if programs.savedRoutine != nil {
                        Button("编辑此方案") {
                            if programs.editDraft(routine) { change(.editor) }
                        }.accessibilityIdentifier("program.edit")
                    }
                    if let message = programs.message { Text(message).foregroundStyle(.red) }
                }
                .navigationTitle("方案详情")
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button("关闭", action: close) } }
            case .training:
                ProgramTrainingView(onClose: close)
            }
        }
    }
}
