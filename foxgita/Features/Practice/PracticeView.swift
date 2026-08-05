//
//  PracticeView.swift
//  foxgita
//

import SwiftData
import SwiftUI

struct PracticeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(PracticeStore.self) private var store
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
    @State private var showSheet = false
    @State private var pendingTaskId: String?
    @State private var editingTaskId: String?
    @State private var editingSessionId: String?
    @State private var deleteTaskId: String?
    @State private var deleteSessionId: String?
    @State private var openSwipeRowId: String?

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
        tasks.filter { $0.status == .active }
    }

    private var daySessions: [PracticeSession] {
        sessions.filter { calendar.isDate($0.endedAt, inSameDayAs: selectedDay) }
    }

    private var streak: Int { StatsAggregator.streakDays(from: sessions) }
    private var weekDays: [StatsAggregator.WeekDay] { StatsAggregator.weekDays(from: sessions) }
    private var weekDone: Int { weekDays.filter(\.practiced).count }
    private var totalTarget: Int { activeTasks.reduce(0) { $0 + $1.targetMin } }
    private var weekMinutes: Int {
        StatsAggregator.totalMinutes(sessions, in: StatsAggregator.week())
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
        return String(localized: "\(daySessions.count) 次记录")
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
                            weekDays: weekDays,
                            weekDone: weekDone,
                            selectedDay: $selectedDay
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

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("本周节奏")
                                    .font(.system(size: 16, weight: .bold))
                                Text("已练 \(weekDone) 天 · 累计 \(weekMinutes) 分钟")
                                    .font(.system(size: 12))
                                    .foregroundStyle(GitaTheme.textSecondary)
                            }
                            Spacer()
                            Button {
                                router.selectedTab = .record
                            } label: {
                                Text("查看记录")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(GitaTheme.textPrimary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(GitaTheme.bgSurface)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .frame(minHeight: 72)
                        .background(GitaTheme.bgSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
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
            .onChange(of: selectedDay) { _, _ in
                openSwipeRowId = nil
            }
            .onChange(of: router.openTodayFirstPractice) { _, requested in
                guard requested else { return }
                router.openTodayFirstPractice = false
                selectedDay = calendar.startOfDay(for: Date())
                guard let first = activeTasks.first else { return }
                router.selectedTab = .practice
                router.practicePath = [.detail(taskId: first.id)]
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
                    title: String(localized: "还没有练习"),
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
        } else if daySessions.isEmpty {
            lockedEmpty(
                title: String(localized: "这天没有练习"),
                subtitle: String(localized: "选中的日期没有留下记录")
            )
        } else {
            ForEach(daySessions, id: \.id) { session in
                SwipeableSessionRow(
                    session: session,
                    openRowId: $openSwipeRowId,
                    onOpen: {
                        openSwipeRowId = nil
                        router.selectedTab = .record
                    },
                    onEdit: {
                        editingSessionId = session.id
                    },
                    onDelete: {
                        deleteSessionId = session.id
                    }
                )
            }
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
