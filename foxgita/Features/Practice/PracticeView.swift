//
//  PracticeView.swift
//  foxgita
//

import SwiftData
import SwiftUI

struct PracticeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(PracticeStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Query(
        filter: #Predicate<TaskItem> { !$0.isTemplate && $0.deletedAt == nil },
        sort: \TaskItem.sortOrder
    )
    private var tasks: [TaskItem]
    @Query(
        filter: #Predicate<PracticeSession> { $0.deletedAt == nil },
        sort: \PracticeSession.endedAt, order: .reverse
    )
    private var sessions: [PracticeSession]

    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var toast: String?
    @State private var weekAnchor = StatsAggregator.week().start
    @State private var showSheet = false
    @State private var pendingTaskId: String?
    @State private var editingTaskId: String?
    @State private var editingSessionId: String?
    @State private var deleteTaskId: String?
    @State private var deleteSessionId: String?
    @State private var openSwipeRowId: String?
    @State private var lastSeenTodayStart: Date?

    private var editingTask: TaskItem? {
        editingTaskId.flatMap { id in tasks.first { $0.id == id } }
    }

    private var editingSession: PracticeSession? {
        editingSessionId.flatMap { id in sessions.first { $0.id == id } }
    }

    private var deleteTask: TaskItem? {
        deleteTaskId.flatMap { id in tasks.first { $0.id == id } }
    }

    private var deleteSession: PracticeSession? {
        deleteSessionId.flatMap { id in sessions.first { $0.id == id } }
    }

    private var calendar: Calendar { .current }
    private var isSelectedToday: Bool { calendar.isDateInToday(selectedDay) }
    private var isSelectedFuture: Bool {
        calendar.startOfDay(for: selectedDay) > calendar.startOfDay(for: Date())
    }

    private var activeTasks: [TaskItem] {
        let now = Date()
        return tasks.filter {
            PracticeTaskRules.isVisibleToday(task: $0, on: now, calendar: calendar)
        }
    }

    private var dayGroups: [StatsAggregator.DayTaskGroup] {
        StatsAggregator.dayTaskGroups(sessions: sessions, on: selectedDay)
    }

    private var streak: Int { StatsAggregator.streakDays(from: sessions) }
    private var weekDays: [StatsAggregator.WeekDay] {
        StatsAggregator.weekDays(from: sessions, containing: weekAnchor)
    }
    private var weekDone: Int { weekDays.filter(\.practiced).count }
    private var totalTarget: Int { activeTasks.reduce(0) { $0 + $1.targetMin } }
    private var isVisibleWeekCurrent: Bool {
        calendar.isDate(weekAnchor, inSameDayAs: StatsAggregator.week().start)
    }

    private var sectionTitle: String {
        if isSelectedToday { return String(localized: "今日练习") }
        if isSelectedFuture { return String(localized: "尚未到来") }
        return String(localized: "当天练习")
    }

    private var sectionMeta: String {
        if isSelectedToday {
            return String(localized: "\(activeTasks.count) 项 · \(totalTarget) 分钟")
        }
        if isSelectedFuture {
            return String(localized: "先练今天")
        }
        return String(localized: "\(dayGroups.count) 项")
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        if h < 12 { return String(localized: "上午好") }
        if h < 18 { return String(localized: "下午好") }
        return String(localized: "晚上好")
    }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.practicePath) {
            ZStack(alignment: .bottomTrailing) {
                PageBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(greeting)
                                .font(GitaFont.title())
                                .foregroundStyle(GitaTheme.textPrimary)
                            Text("今天只练一点点")
                                .font(GitaFont.caption())
                                .foregroundStyle(GitaTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        StreakCard(
                            streak: streak,
                            sessions: sessions,
                            weekDone: weekDone,
                            isCurrentWeek: isVisibleWeekCurrent,
                            selectedDay: $selectedDay,
                            weekAnchor: $weekAnchor
                        )

                        HStack {
                            Text(sectionTitle)
                                .font(.system(size: 18, weight: .bold))
                            Spacer()
                            Text(sectionMeta)
                                .font(.system(size: 12))
                                .foregroundStyle(GitaTheme.textSecondary)
                        }

                        taskList
                    }
                    .padding(.horizontal, GitaTheme.pagePadding)
                    .padding(.bottom, 120)
                }

                if isSelectedToday {
                    Button {
                        showSheet = true
                    } label: {
                        Text("＋")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(GitaTheme.brandOn)
                            .frame(width: 56, height: 56)
                            .background(GitaTheme.brand500)
                            .clipShape(Circle())
                            .shadow(color: GitaTheme.shadowFab, radius: 10, y: 6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("添加练习"))
                    .padding(.trailing, 22)
                    .padding(.bottom, 24)
                }

                if let toast {
                    VStack {
                        Spacer()
                        ToastBanner(text: toast).padding(.bottom, 40)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .onAppear { applyTodaySnap() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { applyTodaySnap() }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: PracticeRoute.self) { route in
                switch route {
                case .detail(let id): PracticeDetailView(taskId: id)
                }
            }
            .sheet(isPresented: $showSheet) {
                guard let taskId = pendingTaskId else { return }
                pendingTaskId = nil
                router.practicePath.append(.detail(taskId: taskId))
            } content: {
                RecommendSheet(selection: $pendingTaskId)
            }
            .sheet(isPresented: Binding(
                get: { editingTaskId != nil },
                set: { if !$0 { editingTaskId = nil } }
            )) {
                if let task = editingTask {
                    EditTaskSheet(task: task) { title, subtitle, minutes in
                        store.updateTask(task.id, title: title, subtitle: subtitle, minutes: minutes)
                    }
                }
            }
            .sheet(isPresented: Binding(
                get: { editingSessionId != nil },
                set: { if !$0 { editingSessionId = nil } }
            )) {
                if let session = editingSession {
                    EditSessionSheet(session: session) { title, note, minutes in
                        store.updateSession(
                            session.id, title: title, note: note, minutes: minutes
                        )
                    }
                }
            }
            .confirmationDialog(
                "删除练习",
                isPresented: Binding(
                    get: { deleteTaskId != nil },
                    set: { if !$0 { deleteTaskId = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    if let id = deleteTaskId { store.softDeleteTask(id) }
                    deleteTaskId = nil
                }
                Button("取消", role: .cancel) { deleteTaskId = nil }
            } message: {
                if let title = deleteTask?.title {
                    Text("确定删除「\(title)」？历史练习记录仍会保留。")
                } else {
                    Text("删除后可在记录里继续查看历史练习。")
                }
            }
            .confirmationDialog(
                "删除这条记录",
                isPresented: Binding(
                    get: { deleteSessionId != nil },
                    set: { if !$0 { deleteSessionId = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    if let id = deleteSessionId { store.softDeleteSession(id) }
                    deleteSessionId = nil
                }
                Button("取消", role: .cancel) { deleteSessionId = nil }
            } message: {
                if let title = deleteSession?.taskTitle {
                    Text("确定删除「\(title)」这次练习记录？删除后不可恢复。")
                } else {
                    Text("删除后这条练习记录将从历史中消失。")
                }
            }
            .onChange(of: selectedDay) { _, newDay in
                openSwipeRowId = nil
                let start = StatsAggregator.week(containing: newDay).start
                if !calendar.isDate(start, inSameDayAs: weekAnchor) {
                    weekAnchor = start
                }
            }
            .onChange(of: router.openTodayFirstPractice) { _, requested in
                guard requested else { return }
                router.openTodayFirstPractice = false
                selectedDay = calendar.startOfDay(for: Date())
                lastSeenTodayStart = calendar.startOfDay(for: Date())
                weekAnchor = StatsAggregator.week().start
                guard let first = activeTasks.first else { return }
                router.selectedTab = .practice
                router.practicePath = [.detail(taskId: first.id)]
            }
            .onChange(of: router.returnPracticeToToday) { _, requested in
                guard requested else { return }
                router.returnPracticeToToday = false
                selectedDay = calendar.startOfDay(for: Date())
                lastSeenTodayStart = calendar.startOfDay(for: Date())
                weekAnchor = StatsAggregator.week().start
            }
            .onChange(of: router.practiceToast) { _, message in
                guard let message else { return }
                router.practiceToast = nil
                showToast(message)
            }
        }
    }

    @ViewBuilder
    private var taskList: some View {
        if isSelectedFuture {
            lockedEmpty(
                title: String(localized: "这一天还没到"),
                subtitle: String(localized: "先把今天练完，未来自然会解锁")
            )
        } else if isSelectedToday {
            if activeTasks.isEmpty {
                lockedEmpty(
                    title: String(localized: "今天还没加练习"),
                    subtitle: String(localized: "点右下角加号，挑一项开始")
                )
            } else {
                ForEach(Array(activeTasks.enumerated()), id: \.element.id) { index, task in
                    SwipeableTaskRow(
                        task: task,
                        solidCTA: index == 0,
                        openRowId: $openSwipeRowId,
                        onStart: {
                            openSwipeRowId = nil
                            router.practicePath.append(.detail(taskId: task.id))
                        },
                        onEdit: {
                            editingTaskId = task.id
                        },
                        onDelete: {
                            deleteTaskId = task.id
                        }
                    )
                }
            }
        } else if dayGroups.isEmpty {
            lockedEmpty(
                title: String(localized: "这天没有练习"),
                subtitle: String(localized: "选中的日期没有留下记录")
            )
        } else {
            ForEach(dayGroups) { group in
                DaySessionCard(
                    title: group.title,
                    minutes: group.totalMinutes,
                    category: group.category
                ) {
                    openPastGroup(group)
                }
            }
        }
    }

    private func applyTodaySnap() {
        let result = PracticeTaskRules.snapSelectedDayIfItWasToday(
            selectedDay: selectedDay,
            lastSeenTodayStart: lastSeenTodayStart,
            now: Date(),
            calendar: calendar
        )
        selectedDay = result.selectedDay
        lastSeenTodayStart = result.lastSeenTodayStart
    }

    private func openPastGroup(_ group: StatsAggregator.DayTaskGroup) {
        if tasks.contains(where: { $0.id == group.taskId }) {
            router.practicePath.append(.detail(taskId: group.taskId))
        } else {
            showToast(String(localized: "练习已删除，无法再练"))
        }
    }

    private func showToast(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toast == message { toast = nil }
        }
    }

    private func lockedEmpty(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(GitaFont.body(.bold))
                .foregroundStyle(GitaTheme.textPrimary)
            Text(subtitle)
                .font(GitaFont.caption())
                .foregroundStyle(GitaTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(GitaTheme.bgSubtle)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
    }
}

private struct EditTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    let task: TaskItem
    let onSave: (String, String, Int) -> Void

    @State private var title: String
    @State private var subtitle: String
    @State private var minutes: Int

    init(task: TaskItem, onSave: @escaping (String, String, Int) -> Void) {
        self.task = task
        self.onSave = onSave
        _title = State(initialValue: task.title)
        _subtitle = State(initialValue: task.subtitle)
        _minutes = State(initialValue: task.targetMin)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("练习") {
                    TextField("标题", text: $title)
                    TextField("备注", text: $subtitle)
                    Stepper("目标 \(minutes) 分钟", value: $minutes, in: 1...60)
                }
            }
            .navigationTitle("编辑练习")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(title, subtitle, minutes)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct EditSessionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let session: PracticeSession
    let onSave: (String, String, Int) -> Void

    @State private var title: String
    @State private var note: String
    @State private var minutes: Int

    init(session: PracticeSession, onSave: @escaping (String, String, Int) -> Void) {
        self.session = session
        self.onSave = onSave
        _title = State(initialValue: session.taskTitle)
        _note = State(initialValue: session.noteText)
        _minutes = State(initialValue: max(1, session.durationMinutes))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("当天记录") {
                    TextField("标题", text: $title)
                    TextField("笔记", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                    Stepper("已练 \(minutes) 分钟", value: $minutes, in: 1...180)
                }
            }
            .navigationTitle("编辑记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(title, note, minutes)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
