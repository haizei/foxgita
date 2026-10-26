import Foundation
import Observation

struct DNAChoice: Identifiable {
    let id: String
    let title: String
}

struct DNAQuestion: Identifiable {
    let id: String
    let title: String
    let prompt: String
    let multiple: Bool
    let optional: Bool
    let choices: [DNAChoice]

    static let all: [DNAQuestion] = [
        .make("vision", "演奏愿景", "三年后，你希望别人怎样评价你的演奏？", [
            ("technique", "技术令人惊叹"), ("story", "独奏像讲故事"), ("groove", "节奏律动出色"),
            ("phrase", "乐句令人动容"), ("fretboard", "熟悉整个指板"), ("improv", "能为任何音乐即兴"), ("tone", "音色令人难忘")]),
        .make("artists", "灵感来源", "哪些吉他手让你想拿起琴练习？", [
            ("mayer", "John Mayer"), ("asato", "Mateus Asato"), ("vai", "Steve Vai"),
            ("metheny", "Pat Metheny"), ("plini", "Plini"), ("johnson", "Eric Johnson")], multiple: true, optional: true),
        .make("traits", "演奏特质", "他们的哪些特点吸引你？", [
            ("technique", "技术"), ("speed", "速度"), ("phrase", "乐句表达"), ("groove", "节奏"),
            ("harmony", "和声"), ("improv", "即兴"), ("creativity", "创造力"), ("expression", "表现力"), ("tone", "音色")], multiple: true, optional: true),
        .make("minutes", "练习时间", "一次练习，你实际能投入多久？", [
            ("15", "15 分钟"), ("20", "20 分钟"), ("30", "30 分钟"), ("45", "45 分钟"), ("60", "60 分钟"), ("90", "90 分钟")]),
        .make("current", "当前状态", "你目前的演奏处于什么状态？", [
            ("finding", "还在寻找音符"), ("connect", "音阶会弹，但连接不起来"),
            ("musical", "速度够快，但不够音乐化"), ("repeat", "即兴总是重复自己"), ("plateau", "遇到了瓶颈")]),
        .make("priority", "优先改善", "你最想改善演奏中的哪个问题？", [
            ("timing", "节拍控制"), ("speed", "速度"), ("bend", "推弦"), ("vibrato", "揉弦"),
            ("ear", "听力"), ("theory", "乐理"), ("improv", "即兴"), ("memory", "记忆"), ("rhythm", "节奏"), ("chord", "和弦")]),
        .make("styles", "风格偏好", "哪些音乐风格吸引你？", [
            ("rock", "摇滚"), ("blues", "布鲁斯"), ("jazz", "爵士"), ("neo", "新灵魂乐"),
            ("metal", "金属"), ("funk", "放克"), ("classical", "古典"), ("ambient", "氛围")], multiple: true, optional: true),
        .make("ability", "理想能力", "如果能改善一项能力，你会选什么？", [
            ("speed", "闪电般的速度"), ("ear", "出色的听力"), ("fretboard", "熟悉指板"),
            ("improv", "即兴演奏"), ("writing", "创作歌曲"), ("feeling", "凭感觉演奏"), ("clean", "干净地演奏"), ("theory", "理解乐理")])
    ]

    private static func make(_ id: String, _ title: String, _ prompt: String,
                             _ values: [(String, String)], multiple: Bool = false, optional: Bool = false) -> Self {
        Self(id: id, title: title, prompt: prompt, multiple: multiple, optional: optional,
             choices: values.map { DNAChoice(id: $0.0, title: $0.1) })
    }
}

struct DNAAnswers: Codable, Equatable {
    var selections: [String: [String]] = [:]
    var daysPerWeek = 4
    var customArtist = ""
    var artistTraits: [String: [String]] = [:]
    var page = 0

    var minutes: Int { Int(selections["minutes"]?.first ?? "30") ?? 30 }
    var complete: Bool { DNAQuestion.all.filter { !$0.optional }.allSatisfy { !(selections[$0.id] ?? []).isEmpty } }
    func labels(for question: DNAQuestion) -> String {
        let chosen = selections[question.id] ?? []
        let labels = question.choices.filter { chosen.contains($0.id) }.map(\.title)
        if question.id == "artists" { return (labels + (customArtist.isEmpty ? [] : [customArtist])).joined(separator: "、") }
        return labels.joined(separator: "、")
    }
}

struct ProgramExercise: Codable, Identifiable, Equatable {
    let id: String
    var title: String
    var subtitle: String
    var minutes: Int
    var category: PracticeCategory
    var reason: String

    var contentIdentity: String {
        Data([category.rawValue, title, subtitle].joined(separator: "\u{1F}").utf8).base64EncodedString()
    }
}

struct PracticeRoutine: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var exercises: [ProgramExercise]
    var minutes: Int { exercises.reduce(0) { $0 + $1.minutes } }
}

/// A transparent local recommendation: the selected priority chooses the focus;
/// styles and traits choose the themes. It makes no claim to score playing ability.
enum DNARecommendations {
    static func routine(for answers: DNAAnswers?) -> PracticeRoutine {
        let budget = answers?.minutes ?? 30
        let priority = answers?.selections["priority"]?.first ?? "improv"
        let label = DNAQuestion.all.first { $0.id == "priority" }?.choices.first { $0.id == priority }?.title ?? "即兴"
        let styleQuestion = DNAQuestion.all.first { $0.id == "styles" }!
        let style = answers?.labels(for: styleQuestion) ?? ""
        let lead: (String, String, PracticeCategory)
        switch priority {
        case "chord", "theory": lead = ("和弦转换", "C · G · Am · F", .chord)
        case "rhythm", "timing": lead = ("节奏训练", "八分音符与重音变化", .rhythm)
        case "ear": lead = ("听力训练", "音程辨认与跟唱", .scale)
        case "speed", "bend", "vibrato": lead = ("技术练习", "慢速清晰地练习" + label, .left)
        default: lead = ("即兴演奏", "乐句表达 · 和弦音独奏", .scale)
        }
        let selectedTraits = answers?.selections["traits"] ?? []
        let expression = selectedTraits.contains("groove") ? "律动感 · 力度变化" : "乐句呼吸 · 力度变化"
        let themes = style.isEmpty ? "熟悉乐句的连接与变化" : style + "乐句的连接与变化"
        let shares = [9, 8, 7, 6]
        var minutes = shares.map { max(1, budget * $0 / 30) }
        var extra = budget - minutes.reduce(0, +)
        var index = 0
        while extra > 0 { minutes[index % 4] += 1; extra -= 1; index += 1 }
        let definitions: [(String, String, String, PracticeCategory, String)] = [
            (priority, lead.0, lead.1, lead.2, answers == nil ? "通用方案 · 练习乐句与音乐表达" : "因为你优先想改善" + label),
            ("expression", "音乐表现力", expression, .both, "为练习保留音乐表达与力度变化"),
            ("vocabulary", "音乐词汇", themes, .song, style.isEmpty ? "从熟悉的乐句积累音乐词汇" : "根据你选择的风格：" + style),
            ("listening", "听力训练", "音程辨认 · 和弦辨认", .scale, "用听觉巩固练习内容")
        ]
        return PracticeRoutine(name: label + "与音乐表达练习", exercises: definitions.enumerated().map { i, item in
            ProgramExercise(id: "dna.\(item.0)", title: item.1, subtitle: item.2,
                            minutes: minutes[i], category: item.3, reason: item.4)
        })
    }
}

enum ProgramEntry: String, Codable { case routine, checklist
    var label: String { self == .routine ? "方案练习" : "今日清单" }
}

enum ProgramStageResult: String, Codable { case pending, completed, skipped }

struct ProgramFact: Codable, Identifiable {
    var id = UUID()
    let itemID: UUID
    let day: String
    /// Offset into a reused daily item, not another elapsed-time record.
    let initialSeconds: Int
    var finalSeconds: Int?
}

struct ProgramStage: Codable, Identifiable {
    var id = UUID()
    var exercise: ProgramExercise
    var result: ProgramStageResult = .pending
    var facts: [ProgramFact] = []
    var checklistItemID: UUID?
    var dailyFacts: [ProgramFact] {
        var seen = Set<UUID>()
        return facts.filter { seen.insert($0.itemID).inserted }
    }
}

struct ProgramTraining: Codable, Identifiable {
    var id = UUID()
    let entry: ProgramEntry
    let name: String
    var stages: [ProgramStage]
    var index = 0
    var ended = false
    var note = ""
    var completedCount: Int { stages.filter { $0.result == .completed }.count }
    var status: String { ended ? (completedCount == stages.count ? "已完成" : "部分完成") : "训练已暂停 · 可继续" }

    func seconds(in snapshots: [PracticeItemSnapshot]) -> Int {
        stages.reduce(0) { $0 + Self.seconds(for: $1, in: snapshots) }
    }
    static func seconds(for stage: ProgramStage, in snapshots: [PracticeItemSnapshot]) -> Int {
        stage.facts.reduce(0) { total, ref in
            let current = snapshots.first { $0.id == ref.itemID && !$0.isDeleted }?.durationSeconds ?? 0
            return total + max(0, min(current, ref.finalSeconds ?? current) - ref.initialSeconds)
        }
    }
}

private struct ProgramDocument: Codable {
    var draftAnswers = DNAAnswers()
    var preferences: DNAAnswers?
    var routineDraft: PracticeRoutine?
    var savedRoutine: PracticeRoutine?
    var trainings: [ProgramTraining] = []
    var dailyCompleted: [String: [UUID]] = [:]
}

@MainActor
final class ProgramClock {
    private var offset: TimeInterval = 0
    private let testEpoch: Date? = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-DNAProgramsUITesting") {
            return Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())
        }
        #endif
        return nil
    }()
    func now() -> Date { (testEpoch ?? Date()).addingTimeInterval(offset) }
    #if DEBUG
    func advance(_ seconds: TimeInterval) { offset += seconds }
    #endif
}

/// Stores arrangements and references. PracticeStore remains the only writer of
/// actual practice duration; all totals are projected from its daily facts.
@Observable @MainActor
final class PracticePrograms {
    private var document = ProgramDocument()
    private(set) var profileID: UUID?
    private(set) var activeTrainingID: UUID?
    var message: String?
    var focusedChecklistItemID: UUID?
    let clock: ProgramClock
    let timer: PracticeTimer
    @ObservationIgnored private var fileURL: URL?
    @ObservationIgnored private var activeFact: ProgramFact?
    @ObservationIgnored private var spanStartedAt: Date?
    @ObservationIgnored private var baseDuration = 0
    @ObservationIgnored private var failNextRoutineSave = false
    @ObservationIgnored private var failNextDraftSave = false
    @ObservationIgnored private var loadFailed = false

    init() {
        let clock = ProgramClock()
        self.clock = clock
        timer = PracticeTimer(now: { clock.now() })
    }

    var preferences: DNAAnswers? { document.preferences }
    var answers: DNAAnswers { document.draftAnswers }
    var routineDraft: PracticeRoutine? { document.routineDraft }
    var savedRoutine: PracticeRoutine? { document.savedRoutine }
    var trainings: [ProgramTraining] { document.trainings }
    var currentTraining: ProgramTraining? { trainings.first { $0.id == activeTrainingID } }
    var isUITesting: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-DNAProgramsUITesting")
        #else
        false
        #endif
    }

    func load(profileID: UUID) {
        guard self.profileID != profileID else { return }
        guard !timer.isRunning else { message = "请先暂停当前训练，再切换档案"; return }
        self.profileID = profileID
        activeTrainingID = nil
        activeFact = nil
        timer.reset()
        document = ProgramDocument()
        loadFailed = false
        if isUITesting {
            fileURL = nil
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-DNAProgramsPreferencesFixture") {
                var answers = DNAAnswers()
                answers.selections = ["vision": ["story"], "minutes": ["30"], "current": ["connect"], "priority": ["improv"], "ability": ["improv"]]
                answers.page = 8
                document.draftAnswers = answers
                document.preferences = answers
                document.savedRoutine = DNARecommendations.routine(for: answers)
            }
            #endif
            return
        }
        let root = URL.applicationSupportDirectory.appending(path: "PracticePrograms", directoryHint: .isDirectory)
        fileURL = root.appending(path: profileID.uuidString + ".json")
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do { document = try JSONDecoder().decode(ProgramDocument.self, from: Data(contentsOf: fileURL)) }
        catch { loadFailed = true; message = "练习安排读取失败，原文件已保留。请重新打开应用后重试。" }
    }

    func updateAnswers(_ answers: DNAAnswers) {
        mutate { $0.draftAnswers = answers }
    }

    @discardableResult func submitAnswers() -> Bool {
        guard answers.complete else { message = "请先完成必选问题"; return false }
        return mutate {
            $0.preferences = $0.draftAnswers
            $0.routineDraft = DNARecommendations.routine(for: $0.draftAnswers)
        }
    }

    @discardableResult func editDraft(_ routine: PracticeRoutine) -> Bool {
        if failNextDraftSave {
            failNextDraftSave = false
            message = "草稿暂时没能保存，当前修改仍在此页，请重试"
            return false
        }
        return mutate { $0.routineDraft = routine }
    }

    @discardableResult func saveRoutine() -> Bool {
        guard let draft = routineDraft, !draft.exercises.isEmpty,
              draft.exercises.allSatisfy({ $0.minutes > 0 }) else { return false }
        if failNextRoutineSave {
            failNextRoutineSave = false
            message = "暂时没能保存方案，草稿已保留，请重试"
            return false
        }
        return mutate { $0.savedRoutine = draft; $0.routineDraft = nil }
    }

    var candidates: [ProgramExercise] { preferences.map { DNARecommendations.routine(for: $0).exercises } ?? [] }

    func candidateItem(_ exercise: ProgramExercise, snapshots: [PracticeItemSnapshot]) -> PracticeItemSnapshot? {
        let day = PracticeDayKey.make(from: clock.now(), calendar: .current)
        return snapshots.first {
            !$0.isDeleted && $0.practiceDayKey == day
                && !($0.originId?.hasPrefix("program.routine.") ?? false)
                && ($0.originId == "program.candidate.\(exercise.contentIdentity)"
                    || ($0.title == exercise.title && $0.subtitle == exercise.subtitle && $0.categoryRaw == exercise.category.rawValue))
        }
    }

    func addCandidate(_ exercise: ProgramExercise, store: PracticeStore) -> UUID? {
        do {
            let snapshots = try snapshots(store)
            if let existing = candidateItem(exercise, snapshots: snapshots) { return existing.id }
            return try store.createPracticeItem(input: input(exercise, origin: "program.candidate.\(exercise.contentIdentity)"),
                                                now: clock.now(), calendar: .current).id
        } catch { message = error.localizedDescription; return nil }
    }

    func beginRoutine(store: PracticeStore) -> Bool {
        let routine = savedRoutine ?? DNARecommendations.routine(for: nil)
        return begin(entry: .routine, name: routine.name, stages: routine.exercises.map { ProgramStage(exercise: $0) }, store: store)
    }

    func beginChecklist(_ items: [PracticeItemSnapshot], store: PracticeStore) -> Bool {
        let day = PracticeDayKey.make(from: clock.now(), calendar: .current)
        let done = document.dailyCompleted[day] ?? []
        let pending = items.filter { $0.practiceDayKey == day && !$0.isDeleted && !done.contains($0.id) }
        guard !pending.isEmpty || trainings.contains(where: { !$0.ended && $0.entry == .checklist }) else { message = "请先添加一项今日练习，或开始一套方案"; return false }
        return begin(entry: .checklist, name: "今日练习", stages: pending.map { item in
            ProgramStage(exercise: ProgramExercise(id: item.id.uuidString, title: item.title, subtitle: item.subtitle,
                minutes: item.targetMin, category: PracticeCategory(rawValue: item.categoryRaw) ?? .both, reason: "自己安排，按顺序练习"), checklistItemID: item.id)
        }, store: store)
    }

    private func begin(entry: ProgramEntry, name: String, stages: [ProgramStage], store: PracticeStore) -> Bool {
        guard pause(store: store) else { return false }
        if let previous = trainings.last(where: { !$0.ended && $0.entry == entry }) {
            activeTrainingID = previous.id
        } else {
            let training = ProgramTraining(entry: entry, name: name, stages: stages)
            guard mutate({ $0.trainings.append(training) }) else { return false }
            activeTrainingID = training.id
        }
        return resume(store: store)
    }

    func openTraining(_ id: UUID, store: PracticeStore) -> Bool {
        guard pause(store: store), let training = trainings.first(where: { $0.id == id }), !training.ended else { return false }
        activeTrainingID = id
        return true
    }

    @discardableResult func resume(store: PracticeStore) -> Bool {
        if activeFact != nil && !pause(store: store) { return false }
        guard !timer.isRunning, let run = currentTraining, !run.ended, run.index < run.stages.count else { return false }
        do {
            let stage = run.stages[run.index]
            let day = PracticeDayKey.make(from: clock.now(), calendar: .current)
            let snapshots = try snapshots(store)
            let existing = stage.facts.last { ref in ref.day == day && ref.finalSeconds == nil && snapshots.contains { $0.id == ref.itemID && !$0.isDeleted } }
            let fact: ProgramFact
            if let existing { fact = existing }
            else {
                let itemID: UUID
                let initial: Int
                if run.entry == .checklist, let id = stage.checklistItemID,
                   let item = snapshots.first(where: { $0.id == id && $0.practiceDayKey == day && !$0.isDeleted }) {
                    itemID = id; initial = item.durationSeconds
                } else {
                    let origin = "program.\(run.entry.rawValue).\(run.id).\(stage.id).\(day)"
                    if let item = snapshots.first(where: { $0.originId == origin && !$0.isDeleted }) {
                        itemID = item.id
                    } else {
                        itemID = try store.createPracticeItem(input: input(stage.exercise, origin: origin),
                                                              now: clock.now(), calendar: .current).id
                    }
                    initial = 0
                }
                let actual = snapshots.first { $0.id == itemID }?.durationSeconds ?? initial
                fact = ProgramFact(itemID: itemID, day: day, initialSeconds: actual)
                guard updateTraining({ $0.stages[$0.index].facts.append(fact) }) else { return false }
            }
            activeFact = fact
            baseDuration = try self.snapshots(store).first { $0.id == fact.itemID }?.durationSeconds ?? 0
            spanStartedAt = clock.now()
            timer.restore(elapsedSec: 0, startedAt: nil)
            timer.start()
            return true
        } catch { message = error.localizedDescription; return false }
    }

    @discardableResult func pause(store: PracticeStore) -> Bool {
        guard timer.isRunning || activeFact != nil else { return true }
        timer.pause()
        guard let fact = activeFact, let started = spanStartedAt, let training = currentTraining else { return true }
        do {
            let stage = training.stages[training.index]
            var cursor = started
            var remaining = timer.elapsedSec
            var first = true
            // Split the actual running span at local midnight. Each later-day
            // item has a stable span origin, making retries idempotent.
            repeat {
                let calendar = Calendar.current
                let day = PracticeDayKey.make(from: cursor, calendar: calendar)
                guard let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: cursor)) else { throw StoreError.invalidInput }
                let chunk = min(remaining, max(1, Int(ceil(end.timeIntervalSince(cursor)))))
                let items = try snapshots(store)
                let itemID: UUID
                let initial: Int
                if first { itemID = fact.itemID; initial = baseDuration }
                else {
                    let origin = "program.\(training.entry.rawValue).\(training.id).\(stage.id).span.\(fact.id).\(day)"
                    if let item = items.first(where: { $0.originId == origin && !$0.isDeleted }) { itemID = item.id }
                    else { itemID = try store.createPracticeItem(input: input(stage.exercise, origin: origin), now: cursor, calendar: calendar).id }
                    initial = 0
                }
                guard let item = try snapshots(store).first(where: { $0.id == itemID && !$0.isDeleted }) else { throw StoreError.notFound }
                try store.savePracticeItem(id: itemID, durationSeconds: initial + chunk, note: item.note, now: cursor)
                guard updateTraining({ run in
                    if let i = run.stages[run.index].facts.firstIndex(where: { first ? $0.id == fact.id : $0.itemID == itemID }) {
                        run.stages[run.index].facts[i].finalSeconds = initial + chunk
                    } else {
                        run.stages[run.index].facts.append(ProgramFact(itemID: itemID, day: day, initialSeconds: initial, finalSeconds: initial + chunk))
                    }
                }) else { return false }
                remaining -= chunk
                cursor = end
                first = false
            } while remaining > 0
            activeFact = nil
            spanStartedAt = nil
            timer.reset()
            return true
        } catch { message = error.localizedDescription; return false }
    }

    func advance(skipping: Bool, store: PracticeStore) {
        guard pause(store: store), let run = currentTraining else { return }
        let stage = run.stages[run.index]
        let day = PracticeDayKey.make(from: clock.now(), calendar: .current)
        guard mutate({ document in
            guard let index = document.trainings.firstIndex(where: { $0.id == run.id }) else { return }
            document.trainings[index].stages[run.index].result = skipping ? .skipped : .completed
            document.trainings[index].index += 1
            document.trainings[index].ended = document.trainings[index].index == run.stages.count
            if !skipping, run.entry == .checklist, let id = stage.checklistItemID {
                let completed = [id] + stage.facts.filter { $0.day == day }.map(\.itemID)
                document.dailyCompleted[day] = Array(Set((document.dailyCompleted[day] ?? []) + completed))
            }
        }) else { return }
        if currentTraining?.ended == false { _ = resume(store: store) }
    }

    func end(store: PracticeStore) {
        guard pause(store: store) else { return }
        updateTraining { $0.ended = true }
    }

    func saveNote(_ note: String) { updateTraining { $0.note = note } }
    func isChecklistCompleted(_ id: UUID) -> Bool {
        let day = PracticeDayKey.make(from: clock.now(), calendar: .current)
        return (document.dailyCompleted[day] ?? []).contains(id)
    }
    func entryLabel(for itemID: UUID) -> String? {
        let entries = Set(trainings.filter { run in
            run.stages.contains { $0.facts.contains { $0.itemID == itemID } }
        }.map(\.entry))
        return entries.isEmpty ? nil : entries.map(\.label).sorted().joined(separator: "、")
    }

    func snapshots(_ store: PracticeStore) throws -> [PracticeItemSnapshot] {
        guard let profileID else { throw StoreError.notFound }
        return try store.practiceItemSnapshots(profileId: profileID)
    }

    #if DEBUG
    func injectSaveFailure() { if isUITesting { failNextRoutineSave = true } }
    func injectDraftSaveFailure() { if isUITesting { failNextDraftSave = true } }
    func advanceTestClock(_ seconds: TimeInterval) { if isUITesting { clock.advance(seconds); timer.refresh() } }
    #endif

    private func input(_ exercise: ProgramExercise, origin: String) -> PracticeItemInput {
        PracticeItemInput(title: exercise.title, category: exercise.category, source: .recommend,
                          originId: origin, bpm: nil, timeSignature: nil, steps: [exercise.subtitle],
                          subtitle: exercise.subtitle, targetMin: exercise.minutes)
    }

    @discardableResult private func updateTraining(_ change: (inout ProgramTraining) -> Void) -> Bool {
        guard let id = activeTrainingID else { return false }
        return mutate { doc in
            if let i = doc.trainings.firstIndex(where: { $0.id == id }) { change(&doc.trainings[i]) }
        }
    }

    @discardableResult private func mutate(_ change: (inout ProgramDocument) -> Void) -> Bool {
        guard profileID != nil, !loadFailed else { message = "练习安排暂不可用，请重新打开应用后重试"; return false }
        var next = document
        change(&next)
        do {
            if let fileURL {
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(next).write(to: fileURL, options: .atomic)
            }
            document = next
            message = nil
            return true
        } catch { message = "保存失败，原有安排未更改：" + error.localizedDescription; return false }
    }
}
