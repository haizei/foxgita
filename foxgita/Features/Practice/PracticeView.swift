//
//  PracticeView.swift
//  foxgita
//

import SwiftData
import SwiftUI

struct PracticeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(PracticeStore.self) private var store
    @Environment(PracticePrograms.self) private var programs
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<PracticeItem> { $0.deletedAt == nil })
    private var practiceItems: [PracticeItem]
    @Query(filter: #Predicate<LocalProfile> { $0.isActive == true })
    private var profiles: [LocalProfile]
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil })
    private var projects: [Project]

    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var toast: String?
    @State private var weekAnchor = StatsAggregator.week().start
    @State private var showSheet = false
    @State private var pendingItemId: String?
    @State private var lastSeenTodayStart: Date?
    @State private var openSwipeRowId: String?
    @State private var deleteItemId: UUID?
    @State private var editingItemId: UUID?
    @State private var showCreateFromPracticeItemId: UUID?

    private var calendar: Calendar { .current }
    private var isSelectedToday: Bool { calendar.isDateInToday(selectedDay) }

    private var isSelectedFuture: Bool {
        calendar.startOfDay(for: selectedDay) > calendar.startOfDay(for: Date())
    }

    private var currentProfileId: UUID? {
        profiles.first.flatMap { UUID(uuidString: $0.id) }
    }

    private var allSnapshots: [PracticeItemSnapshot] {
        guard let profileId = currentProfileId else { return [] }
        return practiceItems
            .filter { $0.profileId == profileId }
            .map(PracticeStore.snapshot(from:))
    }

    private var allSnapshotIds: [UUID] { allSnapshots.map(\.id) }

    private var justCompletedItem: PracticeItemSnapshot? {
        guard isSelectedToday, let id = router.lastCompletedPracticeItemId else { return nil }
        return allSnapshots.first { $0.id == id }
    }

    private var profileProjects: [ProjectSnapshot] {
        guard let profileId = currentProfileId else { return [] }
        return projects
            .filter { $0.profileId == profileId }
            .map(ProjectRules.snapshot(from:))
    }

    private var homeState: PracticeHomeState {
        PracticeHomeState.make(
            selectedDayKey: PracticeDayKey.make(from: selectedDay, calendar: calendar),
            allItems: allSnapshots.filter { !($0.originId?.hasPrefix("program.routine.") ?? false) }
        )
    }

    private var sectionTitle: String {
        if isSelectedToday { return String(localized: "今日练习") }
        if isSelectedFuture { return String(localized: "尚未到来") }
        return String(localized: "当天练习")
    }

    private var sectionMeta: String {
        if isSelectedFuture {
            return String(localized: "先练今天")
        }
        let minutes = isSelectedToday ? homeState.items.reduce(0) { $0 + $1.targetMin } : minutesFromSeconds(homeState.totalDurationSeconds)
        return String(localized: "\(homeState.items.count) 项 · \(minutes) 分钟")
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
                ScrollViewReader { proxy in
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

                        if isSelectedToday {
                            ProgramHero(checkedDays: Set(allSnapshots.filter(PracticeItemRules.isEffective).map(\.practiceDayKey)))
                        } else {
                        StreakCard(
                            checkedInDayKeys: homeState.checkedInDayKeys,
                            selectedDay: $selectedDay,
                            weekAnchor: $weekAnchor
                        )
                        }

                        justCompletedCard

                        HStack {
                            Text(sectionTitle)
                                .font(.system(size: 18, weight: .bold))
                            Spacer()
                            Text(sectionMeta)
                                .font(.system(size: 12))
                                .foregroundStyle(GitaTheme.textSecondary)
                            if isSelectedToday {
                                Button { showSheet = true } label: { Image(systemName: "plus.circle.fill") }
                                    .accessibilityLabel("添加练习")
                                    .accessibilityIdentifier("practice.start-button")
                            }
                        }

                        taskList
                        if isSelectedToday { ProgramRecommendationsView(snapshots: homeState.items) }
                    }
                    .padding(.horizontal, GitaTheme.pagePadding)
                    .padding(.bottom, isSelectedToday ? 112 : 24)
                }
                .task(id: programs.focusedChecklistItemID) {
                    guard let id = programs.focusedChecklistItemID else { return }
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    proxy.scrollTo(id, anchor: .center)
                    programs.focusedChecklistItemID = nil
                }
                }

                if let toast {
                    VStack {
                        Spacer()
                        ToastBanner(text: toast).padding(.bottom, 40)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isSelectedToday {
                    ProgramChecklistButton(snapshots: homeState.items)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .background(GitaTheme.bgDefault)
                }
            }
            .onAppear {
                applyTodaySnap()
                clearStaleJustCompletedIfNeeded()
            }
            .task(id: currentProfileId) {
                if let id = currentProfileId { programs.load(profileID: id) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { applyTodaySnap() }
            }
            .onChange(of: router.lastCompletedPracticeItemId) { _, _ in
                clearStaleJustCompletedIfNeeded()
            }
            .onChange(of: allSnapshotIds) { _, _ in
                clearStaleJustCompletedIfNeeded()
            }
            .navigationBarHidden(true)
            .navigationDestination(for: PracticeRoute.self) { route in
                switch route {
                case .detail(let id): PracticeDetailView(itemId: id)
                }
            }
            .sheet(isPresented: $showSheet) {
                guard let raw = pendingItemId else { return }
                pendingItemId = nil
                guard let route = PracticeDetailState.practiceRoute(fromSheetSelection: raw) else {
                    return
                }
                router.practicePath.append(route)
            } content: {
                RecommendSheet(selection: $pendingItemId)
            }
            .onChange(of: selectedDay) { _, newDay in
                let start = StatsAggregator.week(containing: newDay).start
                if !calendar.isDate(start, inSameDayAs: weekAnchor) {
                    weekAnchor = start
                }
                if !calendar.isDateInToday(newDay) {
                    router.clearJustCompleted()
                }
            }
            .onChange(of: router.openTodayFirstPractice) { _, requested in
                guard requested else { return }
                router.openTodayFirstPractice = false
                selectedDay = calendar.startOfDay(for: Date())
                lastSeenTodayStart = calendar.startOfDay(for: Date())
                weekAnchor = StatsAggregator.week().start
                router.selectedTab = .practice
                router.practicePath = []
                let todayKey = PracticeDayKey.make(from: Date(), calendar: calendar)
                let todayItems = PracticeHomeState.make(
                    selectedDayKey: todayKey, allItems: allSnapshots
                ).items
                guard let first = todayItems.first else { return }
                router.practicePath = [.detail(itemId: first.id)]
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
            .onChange(of: router.selectedTab) { _, tab in
                if tab != .practice {
                    showCreateFromPracticeItemId = nil
                }
            }
            .confirmationDialog(
                "删除练习",
                isPresented: Binding(
                    get: { deleteItemId != nil },
                    set: { if !$0 { deleteItemId = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    if let id = deleteItemId {
                        do {
                            try store.softDeletePracticeItem(id: id, now: Date())
                        } catch {
                            showToast(
                                store.lastError?.localizedDescription
                                    ?? error.localizedDescription
                            )
                        }
                    }
                    deleteItemId = nil
                    openSwipeRowId = nil
                }
                Button("取消", role: .cancel) { deleteItemId = nil }
            } message: {
                if let title = homeState.items.first(where: { $0.id == deleteItemId })?.title {
                    Text("确定删除「\(title)」？")
                } else {
                    Text("删除后这条练习会从今日列表消失。")
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { showCreateFromPracticeItemId != nil },
                    set: { if !$0 { showCreateFromPracticeItemId = nil } }
                )
            ) {
                if let itemId = showCreateFromPracticeItemId {
                    ProjectCreateFromPracticeView(itemId: itemId, fromPracticeTab: true)
                }
            }
            .sheet(item: editSheetItem) { item in
                EditPracticeItemSheet(
                    title: item.title,
                    subtitle: item.subtitle,
                    minutes: PracticeHomeState.initialTargetMin(item.targetMin)
                ) { title, subtitle, minutes in
                    do {
                        try store.updatePracticeItem(
                            id: item.id,
                            title: title,
                            subtitle: subtitle,
                            minutes: minutes,
                            now: Date()
                        )
                    } catch {
                        showToast(
                            store.lastError?.localizedDescription
                                ?? error.localizedDescription
                        )
                    }
                    editingItemId = nil
                    openSwipeRowId = nil
                }
            }
        }
    }

    @ViewBuilder
    private var justCompletedCard: some View {
        if let item = justCompletedItem {
            let hasNote = !item.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let createProject: (() -> Void)? = item.projectId == nil
                ? {
                    RecordAnalytics.projectCreateEntryViewed(source: "practice_complete")
                    RecordAnalytics.projectCreateStarted(source: "practice_complete")
                    showCreateFromPracticeItemId = item.id
                }
                : nil
            JustCompletedCard(
                title: item.title,
                minutes: JustCompletedCopy.minutesLabel(
                    durationSec: item.durationSeconds,
                    hasNote: hasNote,
                    mediaCount: item.recordingCount
                ),
                summary: {
                    var parts: [String] = []
                    if hasNote { parts.append("笔记") }
                    if item.recordingCount > 0 { parts.append("录音 \(item.recordingCount)") }
                    return parts.joined(separator: " · ")
                }(),
                onPracticeAgain: { router.practicePath.append(.detail(itemId: item.id)) },
                onViewRecord: { router.practicePath.append(.detail(itemId: item.id)) },
                onCreateProject: createProject
            )
        }
    }

    @ViewBuilder
    private var taskList: some View {
        if isSelectedFuture {
            lockedEmpty(
                title: String(localized: "这一天还没到"),
                subtitle: String(localized: "先把今天练完，未来自然会解锁")
            )
        } else if homeState.items.isEmpty {
            if isSelectedToday {
                lockedEmpty(
                    title: String(localized: "今天还没加练习"),
                    subtitle: String(localized: "添加一项，开始今天的练习")
                )
            } else {
                lockedEmpty(
                    title: String(localized: "这天没有练习"),
                    subtitle: String(localized: "选中的日期没有留下记录")
                )
            }
        } else {
            ForEach(Array(homeState.items.enumerated()), id: \.element.id) { index, item in
                todayOrPastRow(item, index: index)
                    .id(item.id)
            }
        }
    }

    @ViewBuilder
    private func todayOrPastRow(_ item: PracticeItemSnapshot, index: Int) -> some View {
        let cta = isSelectedToday && programs.isChecklistCompleted(item.id) ? "已完成" : PracticeHomeState.ctaTitle(
            isSelectedToday: isSelectedToday,
            durationSeconds: item.durationSeconds
        )
        let minutesLabel = PracticeHomeState.cardMinutesLabel(
            isSelectedToday: isSelectedToday,
            targetMin: item.targetMin,
            durationSeconds: item.durationSeconds
        )
        let projectCapsule: String? = {
            guard let pid = item.projectId,
                  let projectName = ProjectRules.projectName(id: pid, in: profileProjects) else { return nil }
            return "项目 · \(projectName)"
        }()
        let openProject = {
            if let pid = item.projectId {
                router.showProjectDetail(pid, fromPracticeTab: true)
            }
        }
        let card = DaySessionCard(
            title: item.title,
            minutes: minutesFromSeconds(item.durationSeconds),
            category: category(for: item),
            actionTitle: cta,
            solidCTA: index == 0 && isSelectedToday,
            showsShadow: false,
            subtitle: projectCapsule == nil ? item.subtitle : "",
            minutesText: minutesLabel,
            projectCapsule: projectCapsule,
            onProjectCapsule: projectCapsule == nil ? nil : openProject
        )
        if PracticeHomeState.allowsSwipeDelete(isSelectedToday: isSelectedToday) {
            SwipeRevealRow(
                id: item.id.uuidString,
                openRowId: $openSwipeRowId,
                onTap: {
                    openSwipeRowId = nil
                    router.practicePath.append(.detail(itemId: item.id))
                },
                onEdit: PracticeHomeState.allowsSwipeEdit(isSelectedToday: isSelectedToday)
                    ? { editingItemId = item.id }
                    : nil,
                onDelete: { deleteItemId = item.id }
            ) {
                card
            }
        } else {
            DaySessionCard(
                title: item.title,
                minutes: minutesFromSeconds(item.durationSeconds),
                category: category(for: item),
                actionTitle: cta,
                subtitle: projectCapsule == nil ? item.subtitle : "",
                minutesText: minutesLabel,
                projectCapsule: projectCapsule,
                onProjectCapsule: projectCapsule == nil ? nil : openProject
            ) {
                router.practicePath.append(.detail(itemId: item.id))
            }
        }
    }

    private var editSheetItem: Binding<PracticeItemSnapshot?> {
        Binding(
            get: { homeState.items.first { $0.id == editingItemId } },
            set: { if $0 == nil { editingItemId = nil } }
        )
    }

    private func category(for item: PracticeItemSnapshot) -> PracticeCategory {
        practiceItems.first { $0.id == item.id }
            .flatMap { PracticeCategory(rawValue: $0.categoryRaw) } ?? .chord
    }

    private func minutesFromSeconds(_ seconds: Int) -> Int {
        let clamped = max(0, seconds)
        guard clamped > 0 else { return 0 }
        return max(1, Int((Double(clamped) / 60.0).rounded(.up)))
    }

    private func clearStaleJustCompletedIfNeeded() {
        guard isSelectedToday, router.lastCompletedPracticeItemId != nil, justCompletedItem == nil else {
            return
        }
        router.clearJustCompleted()
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

private struct EditPracticeItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (String, String, Int) -> Void

    @State private var title: String
    @State private var subtitle: String
    @State private var minutes: Int

    init(
        title: String,
        subtitle: String,
        minutes: Int,
        onSave: @escaping (String, String, Int) -> Void
    ) {
        self.onSave = onSave
        _title = State(initialValue: title)
        _subtitle = State(initialValue: subtitle)
        _minutes = State(initialValue: minutes)
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
                }
            }
        }
    }
}
