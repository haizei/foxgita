import SwiftUI

struct DNAPreferencesView: View {
    @Environment(PracticePrograms.self) private var programs
    let onSubmitted: () -> Void
    let onClose: () -> Void

    private var page: Int { min(8, max(0, programs.answers.page)) }
    private var question: DNAQuestion { DNAQuestion.all[min(page, 7)] }
    private var canContinue: Bool { question.optional || !(programs.answers.selections[question.id] ?? []).isEmpty }

    var body: some View {
        Form {
            if page == 8 {
                Section {
                    Text("这是你的音乐方向").font(.title2.bold())
                    Text("确认后，我们将为你整理练习建议。这不是演奏能力测评。")
                }
                ForEach(DNAQuestion.all) { q in
                    Section(q.title) {
                        Text(programs.answers.labels(for: q).isEmpty ? "暂时跳过" : programs.answers.labels(for: q))
                        if q.id == "minutes" { Text("每周 \(programs.answers.daysPerWeek) 天") }
                        Button("修改") { change { $0.page = DNAQuestion.all.firstIndex { $0.id == q.id } ?? 0 } }
                            .accessibilityIdentifier("dna.edit.\(q.id)")
                    }
                }
                Button("提交答案，查看方案") {
                    if programs.submitAnswers() { onSubmitted() }
                }
                .accessibilityIdentifier("dna.submit")
            } else {
                Section {
                    Text(String(format: "%02d / 08", page + 1)).foregroundStyle(GitaTheme.brand500)
                    Text(question.prompt).font(.title2.bold())
                    Text(question.multiple ? "多选 · 可以跳过" : "单选 · 请选择一项")
                        .foregroundStyle(.secondary)
                }
                if question.id == "traits" {
                    traits
                } else {
                    Section {
                        ForEach(question.choices) { choice in
                            choiceButton(choice, question: question)
                        }
                        if question.id == "artists" {
                            TextField("输入其他吉他手名字", text: Binding(
                                get: { programs.answers.customArtist },
                                set: { name in change { $0.customArtist = String(name.prefix(100)) } }
                            ))
                            .disabled((programs.answers.selections["artists"] ?? []).count >= 3 && programs.answers.customArtist.isEmpty)
                            Text("最多选择三位吉他手（含自行填写）").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if question.id == "minutes" {
                    Section("每周计划练习几天？") {
                        Stepper("\(programs.answers.daysPerWeek) 天", value: Binding(
                            get: { programs.answers.daysPerWeek },
                            set: { days in change { $0.daysPerWeek = days } }
                        ), in: 1...7)
                    }
                }
                Button(question.optional ? "继续（可以跳过）" : "下一题") { change { $0.page = page + 1 } }
                    .disabled(!canContinue)
                    .accessibilityIdentifier("dna.next")
            }
            if let message = programs.message { Text(message).foregroundStyle(.red) }
        }
        .id(page)
        .navigationTitle(page == 8 ? "确认答案" : question.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if page > 0 { Button("上一题") { change { $0.page = page - 1 } } }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存并退出", action: onClose).accessibilityIdentifier("dna.exit")
            }
        }
    }

    @ViewBuilder private var traits: some View {
        let artists = DNAQuestion.all[1].choices.filter { (programs.answers.selections["artists"] ?? []).contains($0.id) }
        if artists.isEmpty && programs.answers.customArtist.isEmpty {
            Section {
                Text("先从自己的方向出发")
                Text("你暂时没有选择吉他手，这一题可以直接继续。")
            }
        } else {
            ForEach(artists + (programs.answers.customArtist.isEmpty ? [] : [DNAChoice(id: "custom", title: programs.answers.customArtist)])) { artist in
                Section(artist.title) {
                    ForEach(question.choices) { choice in
                        Button {
                            change { answers in
                                var selected = answers.artistTraits[artist.id] ?? []
                                if selected.contains(choice.id) { selected.removeAll { $0 == choice.id } }
                                else { selected.append(choice.id) }
                                answers.artistTraits[artist.id] = selected
                                answers.selections["traits"] = Array(Set(answers.artistTraits.values.flatMap { $0 })).sorted()
                            }
                        } label: {
                            HStack {
                                Text(choice.title)
                                Spacer()
                                if (programs.answers.artistTraits[artist.id] ?? []).contains(choice.id) { Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
            }
        }
    }

    private func choiceButton(_ choice: DNAChoice, question: DNAQuestion) -> some View {
        let selected = (programs.answers.selections[question.id] ?? []).contains(choice.id)
        return Button {
            change { answers in
                var selections = answers.selections[question.id] ?? []
                if question.multiple {
                    if selected { selections.removeAll { $0 == choice.id } }
                    else if question.id != "artists" || selections.count < (answers.customArtist.isEmpty ? 3 : 2) { selections.append(choice.id) }
                } else { selections = [choice.id] }
                answers.selections[question.id] = selections
                if question.id == "artists" {
                    answers.artistTraits = answers.artistTraits.filter { selections.contains($0.key) || ($0.key == "custom" && !answers.customArtist.isEmpty) }
                    answers.selections["traits"] = Array(Set(answers.artistTraits.values.flatMap { $0 })).sorted()
                }
            }
        } label: {
            HStack {
                Text(choice.title).foregroundStyle(GitaTheme.textPrimary)
                Spacer()
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(GitaTheme.brand500) }
            }
            .padding(.vertical, 6)
        }
        .accessibilityIdentifier("dna.choice.\(choice.id)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func change(_ mutation: (inout DNAAnswers) -> Void) {
        var answers = programs.answers
        mutation(&answers)
        programs.updateAnswers(answers)
    }
}

struct PracticeRoutineEditor: View {
    @Environment(PracticePrograms.self) private var programs
    @State private var routine: PracticeRoutine
    @FocusState private var editingField: String?
    let onSaved: () -> Void
    let onClose: () -> Void

    init(routine: PracticeRoutine, onSaved: @escaping () -> Void, onClose: @escaping () -> Void) {
        _routine = State(initialValue: routine)
        self.onSaved = onSaved
        self.onClose = onClose
    }

    var body: some View {
        Form {
            Section {
                DNADirectionRadar(answers: programs.preferences ?? programs.answers)
                TextField("方案名称", text: $routine.name).focused($editingField, equals: "routine-name").accessibilityIdentifier("program.name")
                Text("\(routine.minutes) 分钟 · \(routine.exercises.count) 个分段")
                if let budget = programs.preferences?.minutes, routine.minutes > budget {
                    Text("超出建议预算 \(routine.minutes - budget) 分钟，仍可保存并开始")
                        .foregroundStyle(GitaTheme.brand500)
                }
            }
            ForEach($routine.exercises) { $exercise in
                Section(exercise.title) {
                    TextField("训练主题", text: $exercise.subtitle).focused($editingField, equals: exercise.id)
                    Stepper("\(exercise.minutes) 分钟", value: $exercise.minutes, in: 1...60)
                    Text(exercise.reason).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .onMove { routine.exercises.move(fromOffsets: $0, toOffset: $1) }
            .onDelete { routine.exercises.remove(atOffsets: $0) }
            Section {
                Menu("添加训练分段") {
                    ForEach(programs.candidates) { candidate in
                        Button(candidate.title) {
                            let added = ProgramExercise(id: UUID().uuidString, title: candidate.title, subtitle: candidate.subtitle,
                                                        minutes: candidate.minutes, category: candidate.category, reason: candidate.reason)
                            routine.exercises.append(added)
                        }
                    }
                }
            }
            Section {
                if let message = programs.message { Text(message).foregroundStyle(.red) }
                Button("保存练习方案") {
                    if programs.editDraft(routine), programs.saveRoutine() { onSaved() }
                }.accessibilityIdentifier("program.save")
                    .disabled(routine.exercises.isEmpty)
                Text("主动保存后才替换首页方案；已有训练和历史保持原样。")
                    .font(.footnote).foregroundStyle(.secondary)
                #if DEBUG
                if programs.isUITesting {
                    Button("测试下次草稿写入失败") { programs.injectDraftSaveFailure() }
                        .accessibilityIdentifier("program.test-draft-save-failure")
                    Button("测试下次保存失败") { programs.injectSaveFailure() }
                        .accessibilityIdentifier("program.test-save-failure")
                }
                #endif
            }
        }
        .navigationTitle("方案预览")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("稍后保存", action: onClose).accessibilityIdentifier("program.close") }
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .keyboard) {
                Button("完成输入") { editingField = nil }.accessibilityIdentifier("program.dismiss-keyboard")
            }
        }
        .onChange(of: routine) { _, updated in programs.editDraft(updated) }
    }
}

/// A preference map. A highlighted direction records an expressed interest;
/// the shape deliberately has no numeric skill scale.
private struct DNADirectionRadar: View {
    let answers: DNAAnswers
    private let labels = ["技术", "表达", "节奏", "和声", "听力"]
    private let keys: [Set<String>] = [
        ["technique", "speed", "bend", "vibrato", "clean"],
        ["story", "phrase", "expression", "improv", "writing", "feeling", "creativity", "tone"],
        ["groove", "timing", "rhythm"], ["harmony", "theory", "chord", "fretboard"], ["ear"]
    ]
    private var interests: [Bool] {
        let selected = Set(answers.selections.values.flatMap { $0 })
        return keys.map { !$0.isDisjoint(with: selected) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Guitar DNA · 你的练习方向").font(.headline)
            GeometryReader { geometry in
                let center = CGPoint(x: geometry.size.width / 2, y: 100)
                let radius: CGFloat = 70
                ZStack {
                    ForEach(1..<4) { ring in
                        polygon(center: center, radii: Array(repeating: radius * CGFloat(ring) / 3, count: 5))
                            .stroke(GitaTheme.brand500.opacity(0.15), lineWidth: 1)
                    }
                    polygon(center: center, radii: interests.map { radius * ($0 ? 1 : 0.35) })
                        .fill(GitaTheme.brand500.opacity(0.2))
                    polygon(center: center, radii: interests.map { radius * ($0 ? 1 : 0.35) })
                        .stroke(GitaTheme.brand500, lineWidth: 2)
                    ForEach(0..<5) { index in
                        Text(labels[index]).font(.caption)
                            .foregroundStyle(interests[index] ? GitaTheme.brand500 : .secondary)
                            .position(point(center: center, radius: 94, index: index))
                    }
                }
            }.frame(height: 205)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("偏好方向：" + zip(labels, interests).filter { $0.1 }.map { $0.0 }.joined(separator: "、"))
            Text("偏好方向 · 不是能力评分").font(.footnote).foregroundStyle(.secondary)
            Text("亮起的方向来自你的选择，供安排练习时参考。").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func point(center: CGPoint, radius: CGFloat, index: Int) -> CGPoint {
        let angle = Double(index) * 2 * .pi / 5 - .pi / 2
        return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }
    private func polygon(center: CGPoint, radii: [CGFloat]) -> Path {
        Path { path in
            path.move(to: point(center: center, radius: radii[0], index: 0))
            for index in 1..<5 { path.addLine(to: point(center: center, radius: radii[index], index: index)) }
            path.closeSubpath()
        }
    }
}
