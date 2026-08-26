//
//  PracticeView.swift
//  foxgita
//

import SwiftData
import SwiftUI

struct PracticeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<PracticeItem> { $0.deletedAt == nil })
    private var practiceItems: [PracticeItem]
    @Query(filter: #Predicate<LocalProfile> { $0.isActive == true })
    private var profiles: [LocalProfile]

    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var toast: String?
    @State private var weekAnchor = StatsAggregator.week().start
    @State private var showSheet = false
    @State private var pendingItemId: String?
    @State private var lastSeenTodayStart: Date?

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

    private var homeState: PracticeHomeState {
        PracticeHomeState.make(
            selectedDayKey: PracticeDayKey.make(from: selectedDay, calendar: calendar),
            allItems: allSnapshots
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
        let minutes = minutesFromSeconds(homeState.totalDurationSeconds)
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
                            checkedInDayKeys: homeState.checkedInDayKeys,
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
                    subtitle: String(localized: "点右下角加号，挑一项开始")
                )
            } else {
                lockedEmpty(
                    title: String(localized: "这天没有练习"),
                    subtitle: String(localized: "选中的日期没有留下记录")
                )
            }
        } else {
            ForEach(homeState.items) { item in
                DaySessionCard(
                    title: item.title,
                    minutes: minutesFromSeconds(item.durationSeconds),
                    category: category(for: item)
                ) {
                    router.practicePath.append(.detail(itemId: item.id))
                }
            }
        }
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
