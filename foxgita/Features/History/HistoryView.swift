//
//  HistoryView.swift
//  foxgita
//

import Charts
import SwiftData
import SwiftUI

struct HistoryView: View {
    let initialSegment: RecordHistorySegment

    @Environment(AppRouter.self) private var router
    @Environment(PracticeStore.self) private var store
    @Query(filter: #Predicate<PracticeItem> { $0.deletedAt == nil })
    private var practiceItems: [PracticeItem]
    @Query(filter: #Predicate<LocalProfile> { $0.isActive == true })
    private var profiles: [LocalProfile]

    @State private var segment: Int
    @State private var month: Date
    @State private var period: Int
    @State private var periodAnchor: Date
    @State private var didSelectDateInThisStay: Bool

    init(initialSegment: RecordHistorySegment) {
        self.initialSegment = initialSegment
        _segment = State(initialValue: initialSegment == .stats ? 1 : 0)
        _month = State(initialValue: Date())
        _period = State(initialValue: 0)
        _periodAnchor = State(initialValue: Date())
        _didSelectDateInThisStay = State(initialValue: initialSegment == .calendar)
    }

    private var calendar: Calendar { .current }

    private var currentProfileId: UUID? {
        profiles.first.flatMap { UUID(uuidString: $0.id) }
    }

    private var allSnapshots: [PracticeItemSnapshot] {
        guard let profileId = currentProfileId else { return [] }
        return practiceItems
            .filter { $0.profileId == profileId }
            .map(PracticeStore.snapshot(from:))
    }

    private var effectiveItems: [PracticeItemSnapshot] {
        allSnapshots.filter(PracticeItemRules.isEffective)
    }

    private var focusedDayKey: String {
        router.recordFocusDayKey ?? PracticeDayKey.make(from: Date(), calendar: calendar)
    }

    private var cells: [RecordCalendarCell] {
        RecordHistoryRules.calendarCells(
            monthContaining: month,
            now: Date(),
            calendar: calendar,
            effectiveItems: effectiveItems
        )
    }

    private var daySummary: RecordDaySummary? {
        RecordHistoryRules.daySummary(dayKey: focusedDayKey, items: allSnapshots)
    }

    private var monthMetrics: (days: Int, seconds: Int, longestStreak: Int) {
        RecordHistoryRules.monthMetrics(
            monthContaining: month,
            calendar: calendar,
            items: allSnapshots
        )
    }

    private var granularity: RecordHistoryGranularity {
        switch period {
        case 1: return .month
        case 2: return .year
        default: return .week
        }
    }

    private var stats: RecordStatsState {
        RecordHistoryRules.stats(
            granularity: granularity,
            containing: periodAnchor,
            now: Date(),
            calendar: calendar,
            items: allSnapshots
        )
    }

    private var monthTitle: String {
        month.formatted(.dateTime.year().month(.wide))
    }

    private var periodTitle: String {
        switch granularity {
        case .week:
            let interval = StatsAggregator.week(containing: periodAnchor, calendar: calendar)
            return RecordTimelineRules.weekTitle(interval: interval, calendar: calendar)
        case .month:
            let year = calendar.component(.year, from: periodAnchor)
            let monthValue = calendar.component(.month, from: periodAnchor)
            return "\(year) 年 \(monthValue) 月"
        case .year:
            return "\(calendar.component(.year, from: periodAnchor)) 年"
        }
    }

    private var segmentIndex: Binding<Int> {
        Binding(
            get: { segment },
            set: { newValue in
                if newValue == 0 && !didSelectDateInThisStay {
                    snapCalendarToToday()
                }
                segment = newValue
            }
        )
    }

    var body: some View {
        ZStack {
            PageBackground()
            VStack(alignment: .leading, spacing: 16) {
                header
                SegmentedPills(titles: ["月历", "统计"], selection: segmentIndex)
                if store.lastError != nil {
                    loadFailureBanner
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if segment == 0 {
                            calendarPane
                        } else {
                            statsPane
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
            .padding(.horizontal, GitaTheme.pagePadding)
        }
        .navigationBarHidden(true)
        .onAppear {
            applyInitialFocus()
        }
        .onDisappear {
            snapWeekFromFocusedDay()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: goBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(GitaTheme.iconPrimary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("返回"))
            Text("练习历史")
                .font(GitaFont.title())
                .foregroundStyle(GitaTheme.textPrimary)
            Spacer()
        }
    }

    private var loadFailureBanner: some View {
        HStack {
            Text("加载失败，已保留当前月和选中日")
                .font(GitaFont.caption())
                .foregroundStyle(GitaTheme.textSecondary)
            Spacer()
            Button("重试") {
                store.clearError()
            }
            .font(GitaFont.callout(.semibold))
            .foregroundStyle(GitaTheme.brand500)
        }
        .padding(12)
        .background(GitaTheme.bgSubtle)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
    }

    private var calendarPane: some View {
        let metrics = monthMetrics
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button("上月") {
                    month = calendar.date(byAdding: .month, value: -1, to: month) ?? month
                }
                .font(GitaFont.footnote())
                .foregroundStyle(GitaTheme.textSecondary)
                Spacer()
                Text(monthTitle)
                    .font(GitaFont.body(.semibold))
                    .foregroundStyle(GitaTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                Button("下月") {
                    month = calendar.date(byAdding: .month, value: 1, to: month) ?? month
                }
                .font(GitaFont.footnote())
                .foregroundStyle(GitaTheme.textSecondary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(StatsAggregator.weekdaySymbols, id: \.self) { weekday in
                    Text(weekday)
                        .font(GitaFont.micro(.semibold))
                        .foregroundStyle(GitaTheme.textTertiary)
                        .frame(maxWidth: .infinity)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                    dayCell(cell)
                }
            }
            .padding(12)
            .background(GitaTheme.bgSurface)
            .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius20))
            .shadow(color: GitaTheme.shadowCard, radius: 8, y: 4)

            MetricGrid(items: [
                ("\(metrics.days)", "练习天数"),
                ("\(RecordMinutes.display(fromSeconds: metrics.seconds))", "总分钟"),
                ("\(metrics.longestStreak)", "最长连续"),
            ])

            summaryCard
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(RecordTimelineRules.dayTitle(dayKey: focusedDayKey, now: Date(), calendar: calendar))
                    .font(GitaFont.callout(.bold))
                    .foregroundStyle(GitaTheme.textPrimary)
                Spacer()
                if let summary = daySummary {
                    Text("\(RecordMinutes.display(fromSeconds: summary.totalSeconds)) 分钟")
                        .font(GitaFont.footnote())
                        .foregroundStyle(GitaTheme.textSecondary)
                }
            }
            if let summary = daySummary {
                Text(summary.joinedTitles)
                    .font(GitaFont.callout())
                    .foregroundStyle(GitaTheme.textPrimary)
                if !summary.typeLabels.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(summary.typeLabels, id: \.self) { label in
                            Text(label)
                                .font(GitaFont.micro())
                                .foregroundStyle(GitaTheme.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(GitaTheme.bgSurface)
                                .clipShape(Capsule())
                        }
                    }
                }
            } else {
                Text("这天没有练习")
                    .font(GitaFont.callout())
                    .foregroundStyle(GitaTheme.textSecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitaTheme.bgSubtle)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
        .accessibilityAddTraits(.isStaticText)
    }

    private func dayCell(_ cell: RecordCalendarCell) -> some View {
        let selected = cell.dayKey == focusedDayKey
        let isToday = cell.dayKey == PracticeDayKey.make(from: Date(), calendar: calendar)
        let numberColor: Color = {
            if cell.isFuture { return GitaTheme.textTertiary }
            if isToday { return GitaTheme.brandOn }
            if cell.isCurrentMonth { return GitaTheme.textPrimary }
            return GitaTheme.textTertiary
        }()
        let minutesColor: Color = {
            if cell.isFuture { return GitaTheme.textTertiary }
            if cell.minutesLabel == "·" { return GitaTheme.textTertiary }
            return GitaTheme.brand500
        }()
        let content = VStack(alignment: .leading, spacing: 2) {
            Text("\(cell.dayNumber)")
                .font(GitaFont.micro(.semibold))
                .foregroundStyle(numberColor)
                .frame(width: isToday ? 18 : nil, height: isToday ? 18 : nil)
                .background(isToday ? GitaTheme.brand500 : Color.clear)
                .clipShape(Circle())
            Text(cell.minutesLabel)
                .font(GitaFont.micro(.bold))
                .foregroundStyle(minutesColor)
            Spacer(minLength: 0)
        }
        .padding(4)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
        .background(selected ? GitaTheme.brand50 : GitaTheme.bgDefault)
        .overlay(
            RoundedRectangle(cornerRadius: GitaTheme.radius8)
                .stroke(GitaTheme.borderSubtle, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius8))
        .opacity(cell.isCurrentMonth || selected ? 1 : 0.55)

        if cell.isFuture {
            return AnyView(content)
        }
        return AnyView(
            Button {
                selectDay(cell)
            } label: {
                content
            }
            .buttonStyle(.plain)
        )
    }

    private var statsPane: some View {
        let state = stats
        return VStack(alignment: .leading, spacing: 14) {
            SegmentedPills(titles: ["周", "月", "年"], selection: $period)

            HStack(spacing: 8) {
                Button {
                    shiftPeriod(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GitaTheme.iconPrimary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("上一周期"))

                Text(periodTitle)
                    .font(GitaFont.body(.semibold))
                    .foregroundStyle(GitaTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)

                Button {
                    shiftPeriod(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GitaTheme.iconPrimary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("下一周期"))
            }

            practiceTimeCard(state)

            MetricGrid(items: [
                ("\(state.practiceDayCount)", "练习天数"),
                ("\(RecordMinutes.display(fromSeconds: state.totalSeconds))", "总分钟"),
                ("\(state.longestStreak)", "最长连续"),
            ])

            periodChart(state)

            if !state.typeShares.isEmpty {
                typeSharesBlock(state.typeShares)
            }
        }
    }

    private func practiceTimeCard(_ state: RecordStatsState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("练琴时间")
                .font(GitaFont.caption())
                .foregroundStyle(GitaTheme.textSecondary)
            Text("\(RecordMinutes.display(fromSeconds: state.totalSeconds))")
                .font(GitaFont.largeTitle())
                .monospacedDigit()
                .foregroundStyle(GitaTheme.textPrimary)
            Text("分钟")
                .font(GitaFont.caption())
                .foregroundStyle(GitaTheme.textSecondary)
            if let delta = state.deltaSeconds {
                let minutes = RecordMinutes.display(fromSeconds: abs(delta))
                Text(delta >= 0 ? "比上期多 \(minutes) 分钟" : "比上期少 \(minutes) 分钟")
                    .font(GitaFont.caption())
                    .foregroundStyle(GitaTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
        .shadow(color: GitaTheme.shadowCard, radius: 6, y: 3)
    }

    private func periodChart(_ state: RecordStatsState) -> some View {
        let bars = state.bars
        let chart = Chart(Array(bars.enumerated()), id: \.offset) { _, bar in
            BarMark(
                x: .value("label", bar.label),
                y: .value("minutes", RecordMinutes.display(fromSeconds: bar.seconds))
            )
            .foregroundStyle(bar.seconds > 0 ? GitaTheme.brand500 : GitaTheme.bgSubtle)
            .cornerRadius(6)
        }
        .frame(height: 180)

        return Group {
            if granularity == .month {
                ScrollView(.horizontal, showsIndicators: false) {
                    chart
                        .frame(width: max(CGFloat(bars.count) * 18, 280))
                }
            } else {
                chart
            }
        }
        .padding(16)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
    }

    private func typeSharesBlock(_ shares: [RecordTypeShare]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("专项分布")
                .font(GitaFont.callout(.semibold))
                .foregroundStyle(GitaTheme.textPrimary)
            ForEach(shares, id: \.category) { share in
                HStack(spacing: 8) {
                    Capsule()
                        .fill(share.category.accent)
                        .frame(width: 8, height: 16)
                    Text(share.category.label)
                        .font(GitaFont.callout())
                        .foregroundStyle(GitaTheme.textPrimary)
                    Spacer()
                    Text("\(RecordMinutes.display(fromSeconds: share.seconds)) 分钟")
                        .font(GitaFont.caption())
                        .foregroundStyle(GitaTheme.textSecondary)
                }
            }
        }
        .padding(16)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
        .shadow(color: GitaTheme.shadowCard, radius: 6, y: 3)
    }

    private func applyInitialFocus() {
        if let key = router.recordFocusDayKey,
           let date = RecordTimelineRules.date(fromDayKey: key, calendar: calendar) {
            month = date
        } else if initialSegment == .calendar {
            snapCalendarToToday()
        }
    }

    private func snapCalendarToToday() {
        let today = Date()
        month = today
        router.recordFocusDayKey = PracticeDayKey.make(from: today, calendar: calendar)
    }

    private func selectDay(_ cell: RecordCalendarCell) {
        guard !cell.isFuture, let dayKey = cell.dayKey else { return }
        didSelectDateInThisStay = true
        router.recordFocusDayKey = dayKey
        RecordAnalytics.dateSelected(date: dayKey, source: "calendar")
        if !cell.isCurrentMonth, let date = RecordTimelineRules.date(fromDayKey: dayKey, calendar: calendar) {
            month = date
        }
    }

    private func shiftPeriod(by amount: Int) {
        periodAnchor = RecordHistoryRules.shiftPeriod(
            granularity: granularity,
            containing: periodAnchor,
            by: amount,
            calendar: calendar
        )
    }

    private func goBack() {
        snapWeekFromFocusedDay()
        if !router.recordPath.isEmpty {
            router.recordPath.removeLast()
        }
    }

    private func snapWeekFromFocusedDay() {
        guard let key = router.recordFocusDayKey,
              let start = RecordHistoryRules.weekStart(forDayKey: key, calendar: calendar)
        else { return }
        router.recordWeekStart = start
    }
}
